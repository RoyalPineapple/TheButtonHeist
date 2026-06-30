import Foundation

enum StorageCleanupOperation: String, Sendable {
    case closeFileHandle
    case removeTemporaryFile
}

struct StorageCleanupResult: Sendable {
    private enum Outcome: Sendable {
        case success
        case failure(String)
    }

    let operation: StorageCleanupOperation
    let path: String?
    private let outcome: Outcome

    var errorDescription: String? {
        switch outcome {
        case .success:
            nil
        case .failure(let description):
            description
        }
    }

    var succeeded: Bool {
        switch outcome {
        case .success:
            true
        case .failure:
            false
        }
    }

    static func success(_ operation: StorageCleanupOperation, path: String? = nil) -> StorageCleanupResult {
        StorageCleanupResult(operation: operation, path: path, outcome: .success)
    }

    static func failure(
        _ operation: StorageCleanupOperation,
        path: String? = nil,
        error: Error
    ) -> StorageCleanupResult {
        StorageCleanupResult(
            operation: operation,
            path: path,
            outcome: .failure(String(describing: error))
        )
    }

    private init(operation: StorageCleanupOperation, path: String?, outcome: Outcome) {
        self.operation = operation
        self.path = path
        self.outcome = outcome
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
