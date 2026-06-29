import Foundation

enum StorageEnvironmentKey: String, Sendable {
    case buttonheistStorageDirectory = "BUTTONHEIST_STORAGE_DIR"
    case xdgDataHome = "XDG_DATA_HOME"
}

private extension Dictionary where Key == String, Value == String {
    subscript(_ key: StorageEnvironmentKey) -> String? {
        self[key.rawValue]
    }
}

enum PrivateStorage {

    // MARK: - Paths

    static func resolveBaseDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment[.buttonheistStorageDirectory] {
            return URL(fileURLWithPath: override)
        }
        if let xdgDataHome = environment[.xdgDataHome] {
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
        let attributes = PrivateFileAttributes.privateDirectory
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: attributes.foundationAttributes
            )
            try fileManager.setAttributes(attributes.foundationAttributes, ofItemAtPath: directory.path)
        } catch {
            throw StorageError.storage(.directoryCreationFailed(
                path: directory.path,
                reason: String(describing: error)
            ))
        }
    }

    static func createPrivateFile(at url: URL, contents: Data? = nil) throws {
        let fileManager = FileManager.default
        let attributes = PrivateFileAttributes.privateFile
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.setAttributes(attributes.foundationAttributes, ofItemAtPath: url.path)
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
            attributes: attributes.foundationAttributes
        ) else {
            throw StorageError.storage(.privateFileCreationFailed(
                path: url.path,
                reason: "FileManager.createFile returned false"
            ))
        }

        do {
            try fileManager.setAttributes(attributes.foundationAttributes, ofItemAtPath: url.path)
        } catch {
            throw StorageError.storage(.privateFileCreationFailed(
                path: url.path,
                reason: String(describing: error)
            ))
        }
    }

    static func writePrivateData(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        let attributes = PrivateFileAttributes.privateFile
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
            try fileManager.setAttributes(attributes.foundationAttributes, ofItemAtPath: url.path)
        } catch {
            StorageCleanup.removeTemporaryItem(at: temporaryURL, operation: .removeTemporaryFile)
            throw error
        }
    }

}

private struct PrivateFileAttributes {
    let permissions: PrivateFilePermissions

    static let privateDirectory = PrivateFileAttributes(permissions: .ownerOnlyDirectory)
    static let privateFile = PrivateFileAttributes(permissions: .ownerOnlyFile)

    var foundationAttributes: [FileAttributeKey: Any] {
        [.posixPermissions: permissions.rawValue]
    }
}

private enum PrivateFilePermissions: Int {
    case ownerOnlyDirectory = 0o700
    case ownerOnlyFile = 0o600
}
