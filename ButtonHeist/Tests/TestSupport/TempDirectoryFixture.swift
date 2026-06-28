import Foundation

/// Runs `body` with a per-test scratch directory under `rootDirectory`.
@discardableResult
public func withTemporaryDirectory<Result>(
    prefix: String,
    rootDirectory: URL = FileManager.default.temporaryDirectory,
    _ body: (URL) throws -> Result
) throws -> Result {
    let directory = rootDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    do {
        let result = try body(directory)
        try removeTemporaryDirectory(directory)
        return result
    } catch {
        try? removeTemporaryDirectory(directory)
        throw error
    }
}

private func removeTemporaryDirectory(_ directory: URL) throws {
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    try FileManager.default.removeItem(at: directory)
}
