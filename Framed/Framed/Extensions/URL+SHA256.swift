import CryptoKit
import Foundation

extension URL {
    /// Computes SHA-256 hash of the file at this URL.
    /// Reads in 64KB chunks to avoid loading large RAW files entirely into memory.
    /// Returns a lowercase hex string suitable for use as a database primary key.
    func sha256Hash() throws -> String {
        let handle = try FileHandle(forReadingFrom: self)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 64 * 1024)
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
