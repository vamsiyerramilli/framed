import DiskArbitration
import Foundation
import ImageIO
import GRDB

// MARK: - DiskArbitration C bridge

/// C-compatible callback for DARegisterDiskAppearedCallback.
/// Must be nonisolated and capture nothing from the surrounding scope —
/// context carries the IngestManager reference as an opaque pointer.
private nonisolated func daOnDiskAppeared(
    _ disk: DADisk,
    _ context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    // takeUnretainedValue: IngestManager.shared holds the retain for the app lifetime
    let manager = Unmanaged<IngestManager>.fromOpaque(context).takeUnretainedValue()
    Task { await manager.handleDiskAppeared(disk) }
}

// MARK: - IngestManager

/// Manages the SD card detection and ingest pipeline (Stages 1 and 2).
///
/// - Stage 1: DiskArbitration detects mounted volumes.
/// - Stage 2: Enumerate image files, compute SHA-256, deduplicate, extract EXIF,
///            move files to Framed storage, write database records.
///
/// All pipeline work runs on this actor's executor — never the main thread.
actor IngestManager {
    static let shared = IngestManager()

    private var daSession: DASession?
    private let db = DatabaseManager.shared

    private init() {}

    // MARK: - Start monitoring

    /// Registers for DiskArbitration disk-appeared events.
    /// Must be called once on app launch from the main thread's run loop (.task modifier).
    func startMonitoring() {
        guard daSession == nil else { return }
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            print("[DA] Failed to create DiskArbitration session")
            return
        }
        // Schedule on the main run loop so callbacks fire reliably
        DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        // Pass self as context; IngestManager.shared holds a strong reference for the app lifetime
        DARegisterDiskAppearedCallback(
            session,
            nil,
            daOnDiskAppeared,
            Unmanaged.passUnretained(self).toOpaque()
        )
        daSession = session
        print("[DA] Monitoring started — waiting for SD card")
    }

    // MARK: - Disk appeared handler

    /// Called when DiskArbitration detects a new disk. Checks if it is an SD card
    /// (removable, FAT32 or exFAT, has DCIM folder) before starting ingest.
    func handleDiskAppeared(_ disk: DADisk) {
        guard let description = DADiskCopyDescription(disk) as NSDictionary? else { return }

        // Only process removable media (SD cards, USB drives)
        guard let isRemovable = description[kDADiskDescriptionMediaRemovableKey] as? Bool,
              isRemovable else { return }

        // Filter to FAT32 ("msdos") and exFAT — the file system formats used by SD cards
        guard let volumeKind = description[kDADiskDescriptionVolumeKindKey] as? String,
              volumeKind == "msdos" || volumeKind == "exfat" else { return }

        // Get the mount path
        guard let volumePathURL = (description[kDADiskDescriptionVolumePathKey] as? URL) else { return }

        let volumeName = (description[kDADiskDescriptionVolumeNameKey] as? String) ?? "Unknown"
        print("[DA] SD card detected: \(volumeName) at \(volumePathURL.path)")

        let dcimURL = volumePathURL.appendingPathComponent("DCIM")
        guard FileManager.default.fileExists(atPath: dcimURL.path) else {
            print("[Ingest] No DCIM folder found on \(volumeName) — skipping")
            return
        }

        Task.detached(priority: .utility) { [dcimURL] in
            await IngestManager.shared.ingestFromDCIM(dcimURL)
        }
    }

    // MARK: - Development testing

    /// Triggers ingest from any folder on disk, bypassing DiskArbitration SD card detection.
    /// Use via the File → "Test Ingest from Folder…" menu item during development.
    /// Covers AC-1.3 through AC-1.11 without requiring SD card hardware.
    func triggerTestIngest(from folderURL: URL) async {
        print("[Ingest] Manual trigger: \(folderURL.path)")
        await ingestFromFolder(folderURL)
    }

    // MARK: - DCIM enumeration

    /// Enumerates image files and processes them sequentially.
    /// File discovery is done synchronously via `collectImageURLs` (a free function)
    /// to avoid the async-context restriction on FileManager's DirectoryEnumerator iterator.
    private func ingestFromDCIM(_ dcimURL: URL) async {
        await ingestFromFolder(dcimURL)
    }

    private func ingestFromFolder(_ folderURL: URL) async {
        print("[Ingest] Starting enumeration of \(folderURL.path)")

        let imageURLs = collectImageURLs(in: folderURL)
        print("[Ingest] Found \(imageURLs.count) image files to process")

        var ingested = 0
        var skipped = 0
        var failed = 0

        // Sequential processing — spec requires this to avoid file system races
        for fileURL in imageURLs {
            do {
                let result = try await ingestFile(fileURL)
                switch result {
                case .ingested: ingested += 1
                case .duplicate: skipped += 1
                }
            } catch {
                print("[Ingest] ✗ \(fileURL.lastPathComponent): \(error)")
                failed += 1
            }
        }

        print("[Ingest] Complete — ingested: \(ingested), duplicates skipped: \(skipped), failed: \(failed)")
    }

    // MARK: - Single file ingest

    private enum IngestResult {
        case ingested
        case duplicate
    }

    /// Processes one image file through the full ingest pipeline:
    /// SHA-256 → deduplicate → EXIF → device → move → write DB record.
    private func ingestFile(_ sourceURL: URL) async throws -> IngestResult {
        // Stage 2.1: Compute SHA-256 content hash
        let hash = try sourceURL.sha256Hash()

        // Stage 2.2: Deduplication — if the hash exists in photos, skip silently
        let isDuplicate = try await db.dbPool.read { db in
            try Photo.fetchOne(db, key: hash) != nil
        }
        if isDuplicate {
            print("[Ingest] Duplicate: \(sourceURL.lastPathComponent) — already in library")
            return .duplicate
        }

        // Stage 2.3: Extract EXIF metadata
        let exifData = extractEXIF(from: sourceURL)

        // Stage 2.4: Get or create Device record
        let deviceId = try await resolveDevice(
            make: exifData.make,
            model: exifData.model
        )

        // Stage 2.5: Determine destination path ~/Pictures/Framed/YYYY/MM/DD/filename
        // try covers the full ?? expression — fileModificationDate() rethrows through ??
        let captureDate = try exifData.capturedAt ?? sourceURL.fileModificationDate()
        let destURL = try destinationURL(for: sourceURL, date: captureDate)

        // Stage 2.6: Move file (not copy — Rule 6)
        try FileManager.default.createDirectory(
            at: destURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: sourceURL, to: destURL)

        // Stage 2.7: Write photos record
        let photo = Photo(
            id: hash,
            filePath: destURL.path,
            sourceDeviceId: deviceId,
            capturedAt: captureDate,
            ingestedAt: Date(),
            format: sourceURL.pathExtension.uppercased(),
            width: exifData.width,
            height: exifData.height,
            fileSizeBytes: exifData.fileSizeBytes,
            stackId: nil,
            similarityScore: nil,
            vectorValid: false,
            reviewStatus: "unseen",
            exifJson: exifData.fullExifJson
        )
        try await db.dbPool.write { db in
            try photo.insert(db)
        }

        print("[Ingest] ✓ \(sourceURL.lastPathComponent) → \(destURL.path)")
        return .ingested
    }

    // MARK: - Device resolution

    /// Returns the ID of the device matching the given EXIF make/model.
    /// Creates a new device record if this is the first time we have seen this camera.
    private func resolveDevice(make: String?, model: String?) async throws -> String? {
        // Build a display name from make + model
        let parts = [make, model].compactMap { $0 }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        let displayName = parts.joined(separator: " ")

        return try await db.dbPool.write { db in
            // Look up by display_name — same camera model = same device record
            if let existing = try Device.filter(Column("display_name") == displayName).fetchOne(db) {
                return existing.id
            }
            // First time seeing this camera — create a new device record
            let device = Device(
                id: UUID().uuidString,
                displayName: displayName,
                deviceType: make != nil ? "camera" : nil,
                firstSeenAt: Date()
            )
            try device.insert(db)
            print("[Ingest] New device registered: \(displayName)")
            return device.id
        }
    }

    // MARK: - Destination path

    /// Computes ~/Pictures/Framed/YYYY/MM/DD/filename.EXT, handling filename collisions.
    private func destinationURL(for sourceURL: URL, date: Date) throws -> URL {
        let pictures = try FileManager.default.url(
            for: .picturesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let cal = Calendar.current
        let year = String(format: "%04d", cal.component(.year, from: date))
        let month = String(format: "%02d", cal.component(.month, from: date))
        let day = String(format: "%02d", cal.component(.day, from: date))
        let dateDir = pictures
            .appendingPathComponent("Framed")
            .appendingPathComponent(year)
            .appendingPathComponent(month)
            .appendingPathComponent(day)

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension

        // Handle filename collisions (rare — SHA-256 deduplication prevents re-ingest of identical files)
        var candidate = dateDir.appendingPathComponent(sourceURL.lastPathComponent)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dateDir.appendingPathComponent("\(baseName)_\(suffix).\(ext)")
            suffix += 1
        }
        return candidate
    }
}

// MARK: - File enumeration (synchronous, free function)

/// Supported image file extensions (lowercase). Video and sidecar files are excluded.
private let supportedImageExtensions: Set<String> = ["raf", "dng", "heic", "heif", "jpeg", "jpg"]

/// Synchronously collects all image file URLs under `dcimURL`.
/// Implemented as a free function (not an async method) to avoid the @available(*, noasync)
/// restriction on FileManager.DirectoryEnumerator's makeIterator.
private func collectImageURLs(in dcimURL: URL) -> [URL] {
    let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
    guard let enumerator = FileManager.default.enumerator(
        at: dcimURL,
        includingPropertiesForKeys: resourceKeys,
        options: [.skipsHiddenFiles]
    ) else { return [] }

    var result: [URL] = []
    for case let fileURL as URL in enumerator {
        guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
        guard supportedImageExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
        result.append(fileURL)
    }
    return result
}

// MARK: - EXIF extraction (synchronous, free function)

private struct EXIFData {
    var capturedAt: Date?
    var make: String?
    var model: String?
    var width: Int?
    var height: Int?
    var fileSizeBytes: Int?
    var fullExifJson: String?
}

/// Extracts EXIF metadata from an image file using ImageIO.
/// All fields are optional — callers handle nil gracefully.
private func extractEXIF(from url: URL) -> EXIFData {
    var result = EXIFData()

    // File size from file system attributes (does not require reading image data)
    result.fileSizeBytes = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int

    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary? else {
        return result
    }

    // Pixel dimensions
    result.width = props[kCGImagePropertyPixelWidth] as? Int
    result.height = props[kCGImagePropertyPixelHeight] as? Int

    // TIFF sub-dictionary: camera make and model
    if let tiff = props[kCGImagePropertyTIFFDictionary] as? NSDictionary {
        result.make = tiff[kCGImagePropertyTIFFMake] as? String
        result.model = tiff[kCGImagePropertyTIFFModel] as? String
    }

    // EXIF sub-dictionary: capture timestamp
    if let exif = props[kCGImagePropertyExifDictionary] as? NSDictionary {
        let rawDate = exif[kCGImagePropertyExifDateTimeOriginal] as? String
                   ?? exif[kCGImagePropertyExifDateTimeDigitized] as? String
        result.capturedAt = rawDate.flatMap { parseEXIFDate($0) }
    }

    // Serialize full metadata for exif_json column
    if let json = try? JSONSerialization.data(withJSONObject: props, options: []),
       let jsonString = String(data: json, encoding: .utf8) {
        result.fullExifJson = jsonString
    }

    return result
}

/// Parses the EXIF date string format "YYYY:MM:DD HH:MM:SS" into a Date.
private func parseEXIFDate(_ raw: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    return formatter.date(from: raw)
}

// MARK: - URL helpers

extension URL {
    /// Returns the file modification date from file system attributes.
    /// Used as fallback when EXIF DateTimeOriginal is absent.
    fileprivate func fileModificationDate() throws -> Date {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        // .modificationDate is always present for accessible files
        return attrs[.modificationDate] as? Date ?? Date()
    }
}
