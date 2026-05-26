import Foundation

extension TheBookKeeper {

    // MARK: - Session Compression

    nonisolated static func compressLog(in directory: URL) async throws -> URL {
        let logPath = directory.appendingPathComponent("session.jsonl")
        let compressedPath = directory.appendingPathComponent("session.jsonl.gz")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = [logPath.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try await Self.runProcess(process, failureContext: "gzip") { failure in
            BookKeeperError.compressionFailed(.process(failure))
        }

        guard process.terminationStatus == 0 else {
            throw BookKeeperError.compressionFailed(.process(.exited(
                context: "gzip",
                status: process.terminationStatus,
                detail: nil
            )))
        }
        guard FileManager.default.fileExists(atPath: compressedPath.path) else {
            throw BookKeeperError.compressionFailed(.outputMissing(path: compressedPath.path))
        }
        do {
            try Self.restrictPrivateFilePermissions(at: compressedPath)
        } catch {
            throw BookKeeperError.compressionFailed(.permissionUpdateFailed(
                path: compressedPath.path,
                reason: String(describing: error)
            ))
        }
        return compressedPath
    }

    nonisolated func createArchive(session: ClosedSession) async throws -> URL {
        let parentDirectory = session.directory.deletingLastPathComponent()
        let directoryName = session.directory.lastPathComponent
        let archiveName = "\(session.sessionId).tar.gz"
        let archivePath = parentDirectory.appendingPathComponent(archiveName)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["czf", archivePath.path, "-C", parentDirectory.path, "--", directoryName]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try await Self.runProcess(process, failureContext: "tar czf") { failure in
            BookKeeperError.archiveFailed(.process(failure))
        }

        guard process.terminationStatus == 0 else {
            throw BookKeeperError.archiveFailed(.process(.exited(
                context: "tar czf",
                status: process.terminationStatus,
                detail: nil
            )))
        }
        guard FileManager.default.fileExists(atPath: archivePath.path) else {
            throw BookKeeperError.archiveFailed(.outputMissing(path: archivePath.path))
        }
        do {
            try Self.restrictPrivateFilePermissions(at: archivePath)
        } catch {
            throw BookKeeperError.archiveFailed(.permissionUpdateFailed(
                path: archivePath.path,
                reason: String(describing: error)
            ))
        }
        return archivePath
    }

    nonisolated private static func restrictPrivateFilePermissions(at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private nonisolated static func runProcess(
        _ process: Process,
        failureContext: String,
        failure: @escaping @Sendable (BookKeeperProcessFailure) -> BookKeeperError
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: failure(.launchFailed(
                    context: failureContext,
                    reason: String(describing: error)
                )))
            }
        }
    }
}
