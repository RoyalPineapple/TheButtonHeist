import Foundation

enum PrivateStorage {

    // MARK: - Paths

    static func resolveBaseDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["BUTTONHEIST_STORAGE_DIR"] {
            return URL(fileURLWithPath: override)
        }
        if let xdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"] {
            return URL(fileURLWithPath: xdgDataHome)
                .appendingPathComponent("buttonheist")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/buttonheist")
    }

    static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

    static func isSafePathSegment(_ identifier: String) -> Bool {
        guard !identifier.isEmpty,
              !identifier.hasPrefix("-"),
              !identifier.contains("/"),
              !identifier.contains("..") else { return false }

        return !identifier.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
    }

    // MARK: - Private File I/O

    static func createPrivateDirectory(at directory: URL) throws {
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
            throw StorageError.storage(.directoryCreationFailed(
                path: directory.path,
                reason: String(describing: error)
            ))
        }
    }

    static func createPrivateFile(at url: URL, contents: Data? = nil) throws {
        let fileManager = FileManager.default
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
                if let contents {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { StorageCleanup.close(handle) }
                    try handle.truncate(atOffset: 0)
                    try handle.write(contentsOf: contents)
                }
            } catch {
                throw StorageError.storage(.privateFileCreationFailed(
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
            throw StorageError.storage(.privateFileCreationFailed(
                path: url.path,
                reason: "FileManager.createFile returned false"
            ))
        }

        do {
            try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
        } catch {
            throw StorageError.storage(.privateFileCreationFailed(
                path: url.path,
                reason: String(describing: error)
            ))
        }
    }

    static func writePrivateData(_ data: Data, to url: URL) throws {
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
            StorageCleanup.removeTemporaryItem(at: temporaryURL, operation: .removeTemporaryFile)
            throw error
        }
    }

}
