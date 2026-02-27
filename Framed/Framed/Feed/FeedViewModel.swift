import Foundation
import Observation
import GRDB

@Observable
final class FeedViewModel {

    // MARK: - UI state (read by SwiftUI views)

    var days: [FeedDay] = []
    var isLoading = false
    var hasMorePages = true
    var newPhotosAvailable = false
    var isEmpty = false

    // MARK: - Private state

    /// All rows loaded so far, accumulated across pages. Used to rebuild `days` after each page.
    private var loadedRows: [PhotoWithDevice] = []
    /// captured_at of the oldest loaded photo — keyset pagination cursor.
    private var cursor: Date? = nil
    /// id of the oldest loaded photo — tiebreaker for the cursor.
    private var cursorId: String? = nil
    /// Photo count at the time of the last full load — used to detect mid-session ingests.
    private var lastKnownCount = 0
    /// Cancels the ValueObservation async stream when the view disappears.
    private var observationTask: Task<Void, Never>? = nil

    private let repository: FeedRepository

    init(repository: FeedRepository = .shared) {
        self.repository = repository
    }

    // MARK: - Lifecycle

    func onAppear() async {
        await loadInitialFeed()
        startObservation()
    }

    func onDisappear() {
        observationTask?.cancel()
        observationTask = nil
    }

    // MARK: - Initial load

    /// Loads the feed from scratch, covering at least 2 calendar days (or all available data).
    func loadInitialFeed() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            var allRows = try await repository.fetchPage(cursor: nil, cursorId: nil)

            // Keep fetching until we have >= 2 distinct calendar days or no more data
            var builtDays = repository.buildFeed(from: allRows)
            while builtDays.count < 2 && allRows.count % 50 == 0 && !allRows.isEmpty {
                guard let oldest = allRows.last else { break }
                let morePage = try await repository.fetchPage(
                    cursor: oldest.photo.capturedAt,
                    cursorId: oldest.photo.id
                )
                guard !morePage.isEmpty else { break }
                allRows += morePage
                builtDays = repository.buildFeed(from: allRows)
            }

            let finalRows = allRows
            let count = finalRows.count
            let built = builtDays
            let oldest = finalRows.last

            await MainActor.run {
                self.loadedRows = finalRows
                self.days = built
                self.isEmpty = built.isEmpty
                self.lastKnownCount = count
                self.cursor = oldest?.photo.capturedAt
                self.cursorId = oldest?.photo.id
                self.hasMorePages = count % 50 == 0 && count > 0
                self.newPhotosAvailable = false
            }
        } catch {
            print("[Feed] Initial load failed: \(error)")
        }
    }

    // MARK: - Pagination

    /// Called when the user scrolls to the bottom pagination trigger.
    func loadMoreIfNeeded() async {
        guard !isLoading, hasMorePages, let cursor, let cursorId else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let newRows = try await repository.fetchPage(cursor: cursor, cursorId: cursorId)
            guard !newRows.isEmpty else {
                await MainActor.run { self.hasMorePages = false }
                return
            }

            let combined = loadedRows + newRows
            let built = repository.buildFeed(from: combined)
            let oldest = newRows.last

            await MainActor.run {
                self.loadedRows = combined
                self.days = built
                self.lastKnownCount += newRows.count
                self.cursor = oldest?.photo.capturedAt
                self.cursorId = oldest?.photo.id
                self.hasMorePages = newRows.count == 50
            }
        } catch {
            print("[Feed] Pagination failed: \(error)")
        }
    }

    // MARK: - Live update

    /// Resets all state and reloads the feed from the top. Called when the user taps the banner.
    func reloadWithNewPhotos() async {
        await MainActor.run {
            self.newPhotosAvailable = false
            self.loadedRows = []
            self.cursor = nil
            self.cursorId = nil
            self.lastKnownCount = 0
        }
        await loadInitialFeed()
    }

    // MARK: - ValueObservation

    private func startObservation() {
        observationTask = Task {
            let observation = repository.photoCountObservation()
            do {
                for try await count in observation.values(in: DatabaseManager.shared.dbPool) {
                    let known = lastKnownCount
                    if count > known && known > 0 {
                        await MainActor.run { self.newPhotosAvailable = true }
                    }
                }
            } catch {
                print("[Feed] Observation error: \(error)")
            }
        }
    }
}
