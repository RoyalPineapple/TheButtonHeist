import Foundation

enum StorageCleanupOperation: String, Sendable {
    case closeFileHandle
    case removeTemporaryFile
}

struct StorageCleanupResult: Sendable {
    let operation: StorageCleanupOperation
    let path: String?
    let errorDescription: String?

    var succeeded: Bool {
        errorDescription == nil
    }

    static func success(_ operation: StorageCleanupOperation, path: String? = nil) -> StorageCleanupResult {
        StorageCleanupResult(operation: operation, path: path, errorDescription: nil)
    }

    static func failure(
        _ operation: StorageCleanupOperation,
        path: String? = nil,
        error: Error
    ) -> StorageCleanupResult {
        StorageCleanupResult(
            operation: operation,
            path: path,
            errorDescription: String(describing: error)
        )
    }
}

enum StorageCleanup {
    @discardableResult
    static func close(_ handle: FileHandle) -> StorageCleanupResult {
        do {
            try handle.close()
            return .success(.closeFileHandle)
        } catch {
            return .failure(.closeFileHandle, error: error)
        }
    }

    @discardableResult
    static func removeTemporaryItem(at url: URL, operation: StorageCleanupOperation) -> StorageCleanupResult {
        do {
            try FileManager.default.removeItem(at: url)
            return .success(operation, path: url.path)
        } catch {
            return .failure(operation, path: url.path, error: error)
        }
    }
}
