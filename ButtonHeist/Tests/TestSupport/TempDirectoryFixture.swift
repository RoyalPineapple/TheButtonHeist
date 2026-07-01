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

/// Runs async `body` with a per-test scratch directory under `rootDirectory`.
@discardableResult
public func withTemporaryDirectory<Result: Sendable>(
    prefix: String,
    rootDirectory: URL = FileManager.default.temporaryDirectory,
    isolation: isolated (any Actor)? = #isolation,
    _ body: (URL) async throws -> Result
) async throws -> Result {
    let directory = rootDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    do {
        let result = try await body(directory)
        try removeTemporaryDirectory(directory)
        return result
    } catch {
        try? removeTemporaryDirectory(directory)
        throw error
    }
}

/// Runs `body` with a per-test receipt directory.
@discardableResult
public func withReceiptDirectory<Result>(
    prefix: String = "buttonheist-receipts",
    rootDirectory: URL = FileManager.default.temporaryDirectory,
    _ body: (URL) throws -> Result
) throws -> Result {
    try withTemporaryDirectory(prefix: prefix, rootDirectory: rootDirectory, body)
}

/// Runs async `body` with a per-test receipt directory.
@discardableResult
public func withReceiptDirectory<Result: Sendable>(
    prefix: String = "buttonheist-receipts",
    rootDirectory: URL = FileManager.default.temporaryDirectory,
    isolation: isolated (any Actor)? = #isolation,
    _ body: (URL) async throws -> Result
) async throws -> Result {
    try await withTemporaryDirectory(
        prefix: prefix,
        rootDirectory: rootDirectory,
        isolation: isolation,
        body
    )
}

public func receiptArtifactURLs(
    in directory: URL,
    matchingSuffix suffix: String = ".json.gz"
) throws -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else {
        throw ReceiptDirectoryFixtureError.unreadableDirectory(directory.path)
    }

    var urls: [URL] = []
    for case let url as URL in enumerator {
        guard url.lastPathComponent.hasSuffix(suffix) else { continue }
        let isRegularFile = try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile ?? false
        guard isRegularFile else { continue }
        urls.append(url)
    }
    return urls.sorted { $0.path < $1.path }
}

public func assertSingleReceiptArtifactURL(
    in directory: URL,
    matchingSuffix suffix: String = ".json.gz"
) throws -> URL {
    let urls = try receiptArtifactURLs(in: directory, matchingSuffix: suffix)
    guard urls.count == 1 else {
        throw ReceiptDirectoryFixtureError.unexpectedReceiptCount(
            expected: 1,
            actualPaths: urls.map(\.path)
        )
    }
    return urls[0]
}

public enum ReceiptDirectoryFixtureError: Error, Equatable, CustomStringConvertible, Sendable {
    case unreadableDirectory(String)
    case unexpectedReceiptCount(expected: Int, actualPaths: [String])

    public var description: String {
        switch self {
        case .unreadableDirectory(let path):
            return "Could not enumerate receipt directory at \(path)"
        case .unexpectedReceiptCount(let expected, let actualPaths):
            return "Expected \(expected) receipt artifact(s), found \(actualPaths.count): \(actualPaths.joined(separator: ", "))"
        }
    }
}

private func removeTemporaryDirectory(_ directory: URL) throws {
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    try FileManager.default.removeItem(at: directory)
}
