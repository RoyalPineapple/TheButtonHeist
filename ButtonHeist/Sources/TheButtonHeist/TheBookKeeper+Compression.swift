import Foundation

extension TheBookKeeper {

    func compressLog(in directory: URL) async throws -> URL {
        let logPath = directory.appendingPathComponent("session.jsonl")
        let compressedPath = directory.appendingPathComponent("session.jsonl.gz")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = [logPath.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw BookKeeperError.compressionFailed(
                "gzip exited with status \(process.terminationStatus)"
            )
        }
        guard FileManager.default.fileExists(atPath: compressedPath.path) else {
            throw BookKeeperError.compressionFailed(
                "Expected compressed file not found at \(compressedPath.path)"
            )
        }
        return compressedPath
    }

    func createArchive(session: ClosedSession) async throws -> URL {
        let parentDirectory = session.directory.deletingLastPathComponent()
        let directoryName = session.directory.lastPathComponent
        let archiveName = "\(session.sessionId).tar.gz"
        let archivePath = parentDirectory.appendingPathComponent(archiveName)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["czf", archivePath.path, "-C", parentDirectory.path, directoryName]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw BookKeeperError.archiveFailed(
                "tar exited with status \(process.terminationStatus)"
            )
        }
        guard FileManager.default.fileExists(atPath: archivePath.path) else {
            throw BookKeeperError.archiveFailed(
                "Expected archive not found at \(archivePath.path)"
            )
        }
        return archivePath
    }
}
