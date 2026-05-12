import Foundation

/// Per-test scratch directory under `FileManager.temporaryDirectory`.
///
/// Replaces the per-file `tempDirectory` setUp/tearDown that
/// `TheBookKeeperTests` and `BookKeeperHeistTests` carry. Callers should
/// store the result and remove it in `tearDown()`.
enum TempDirectoryFixture {

    /// Create a per-test scratch directory under
    /// `FileManager.temporaryDirectory`. The directory name is
    /// `\(prefix)-\(UUID)` so concurrent tests never collide.
    static func make(prefix: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Best-effort removal of the per-test scratch directory. Idempotent.
    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
