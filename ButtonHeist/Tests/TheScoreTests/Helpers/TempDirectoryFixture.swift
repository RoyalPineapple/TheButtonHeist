import Foundation
import Testing

/// Runs `body` with a per-test scratch directory under `rootDirectory`.
@discardableResult
func withTemporaryDirectory<Result>(
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

@Suite struct TempDirectoryFixtureTests {

    @Test func `removes temporary directory after body returns`() throws {
        let directory = try withTemporaryDirectory(prefix: "temp-directory-fixture") { directory in
            #expect(FileManager.default.fileExists(atPath: directory.path))
            try Data([0x00]).write(to: directory.appendingPathComponent("scratch.bin"))
            return directory
        }

        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func `creation failure is thrown before body runs`() throws {
        try withTemporaryDirectory(prefix: "temp-directory-fixture-parent") { directory in
            let fileURL = directory.appendingPathComponent("not-a-directory")
            try Data([0x00]).write(to: fileURL)

            #expect(throws: (any Error).self) {
                try withTemporaryDirectory(prefix: "child", rootDirectory: fileURL) { _ in
                    Issue.record("Expected directory creation to fail before body runs")
                }
            }
        }
    }
}
