import Foundation

extension TheBookKeeper {

    // MARK: - Session File I/O

    nonisolated static func createPrivateDirectory(at directory: URL) throws {
        let fileManager = FileManager.default
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: attributes
            )
            try fileManager.setAttributes(attributes, ofItemAtPath: directory.path)
        } catch {
            throw BookKeeperError.session(.directoryCreationFailed(
                path: directory.path,
                reason: String(describing: error)
            ))
        }
    }

    nonisolated static func createPrivateFile(at url: URL, contents: Data? = nil) throws {
        let fileManager = FileManager.default
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
                if let contents {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { BookKeeperCleanup.close(handle) }
                    try handle.truncate(atOffset: 0)
                    try handle.write(contentsOf: contents)
                }
            } catch {
                throw BookKeeperError.session(.logFileCreationFailed(
                    path: url.path,
                    reason: String(describing: error)
                ))
            }
            return
        }

        guard fileManager.createFile(
            atPath: url.path,
            contents: contents,
            attributes: attributes
        ) else {
            throw BookKeeperError.session(.logFileCreationFailed(
                path: url.path,
                reason: "FileManager.createFile returned false"
            ))
        }

        do {
            try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
        } catch {
            throw BookKeeperError.session(.logFileCreationFailed(
                path: url.path,
                reason: String(describing: error)
            ))
        }
    }

    nonisolated static func writePrivateData(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try createPrivateFile(at: temporaryURL, contents: data)
        do {
            if fileManager.fileExists(atPath: url.path) {
                do {
                    try fileManager.removeItem(at: url)
                } catch {
                    if fileManager.fileExists(atPath: url.path) {
                        throw error
                    } else {
                        // Destination disappeared after the existence check; the move below
                        // still provides the one authoritative replacement write.
                    }
                }
            }
            try fileManager.moveItem(at: temporaryURL, to: url)
            try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
        } catch {
            BookKeeperCleanup.removeTemporaryItem(at: temporaryURL, operation: .removeTemporaryFile)
            throw error
        }
    }

    func openSessionLog(at logPath: URL) throws -> FileHandle {
        do {
            return try FileHandle(forWritingTo: logPath)
        } catch {
            throw BookKeeperError.session(.logFileOpenFailed(
                path: logPath.path,
                reason: String(describing: error)
            ))
        }
    }

    func writeSessionHeader(sessionId: String, to logHandle: FileHandle, logPath: URL) throws {
        do {
            try appendLogLine(HeaderLogEntry(
                formatVersion: SessionFormatVersion.current,
                sessionId: sessionId
            ), to: logHandle)
        } catch {
            throw BookKeeperError.session(.headerWriteFailed(
                path: logPath.path,
                reason: String(describing: error)
            ))
        }
    }

    func flushManifest(manifest: SessionManifest, directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestPath = directory.appendingPathComponent("manifest.json")
        do {
            let data = try encoder.encode(manifest)
            try Self.writePrivateData(data, to: manifestPath)
        } catch {
            throw BookKeeperError.manifest(.writeFailed(
                sessionId: manifest.sessionId,
                path: manifestPath.path,
                reason: String(describing: error)
            ))
        }
    }

    func deleteSessionSourceDirectory(_ directory: URL) throws {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            throw BookKeeperError.session(.sourceDeletionFailed(
                path: directory.path,
                reason: String(describing: error)
            ))
        }
    }

    func sessionLogSnapshot(manifest: SessionManifest, directory: URL) throws -> SessionLogSnapshot {
        let projection = try sessionLogProjection(in: directory)
        return SessionLogSnapshot(
            manifest: manifest,
            counts: projection.counts,
            artifacts: projection.artifacts,
            projectionStatus: projection.status
        )
    }

    func sessionLogSnapshot(manifest: SessionManifest, archivePath: URL) throws -> SessionLogSnapshot {
        let projection = try sessionLogProjection(inArchive: archivePath)
        return SessionLogSnapshot(
            manifest: manifest,
            counts: projection.counts,
            artifacts: projection.artifacts,
            projectionStatus: projection.status
        )
    }
}
