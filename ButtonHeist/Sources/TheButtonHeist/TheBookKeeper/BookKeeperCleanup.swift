import Foundation

enum BookKeeperCleanupOperation: String, Sendable {
    case closeFileHandle
    case removeTemporaryFile
    case removeTemporaryProcessStderr
}

struct BookKeeperCleanupResult: Sendable {
    let operation: BookKeeperCleanupOperation
    let path: String?
    let errorDescription: String?

    var succeeded: Bool {
        errorDescription == nil
    }

    static func success(_ operation: BookKeeperCleanupOperation, path: String? = nil) -> BookKeeperCleanupResult {
        BookKeeperCleanupResult(operation: operation, path: path, errorDescription: nil)
    }

    static func failure(
        _ operation: BookKeeperCleanupOperation,
        path: String? = nil,
        error: Error
    ) -> BookKeeperCleanupResult {
        BookKeeperCleanupResult(
            operation: operation,
            path: path,
            errorDescription: String(describing: error)
        )
    }
}

enum BookKeeperCleanup {
    @discardableResult
    static func close(_ handle: FileHandle) -> BookKeeperCleanupResult {
        do {
            try handle.close()
            return .success(.closeFileHandle)
        } catch {
            return .failure(.closeFileHandle, error: error)
        }
    }

    @discardableResult
    static func removeTemporaryItem(at url: URL, operation: BookKeeperCleanupOperation) -> BookKeeperCleanupResult {
        do {
            try FileManager.default.removeItem(at: url)
            return .success(operation, path: url.path)
        } catch {
            return .failure(operation, path: url.path, error: error)
        }
    }
}
