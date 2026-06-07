import Foundation

enum StorageFailure: Sendable, Equatable {
    case directoryCreationFailed(path: String, reason: String)
    case privateFileCreationFailed(path: String, reason: String)

    var message: String {
        switch self {
        case .directoryCreationFailed(let path, let reason):
            return "Failed to create storage directory at \(path): \(reason)"
        case .privateFileCreationFailed(let path, let reason):
            return "Failed to create private file at \(path): \(reason)"
        }
    }
}

/// Errors thrown while writing heists and screenshot artifacts.
enum StorageError: Error, LocalizedError {
    case unsafePath(String)
    case base64DecodingFailed
    case storage(StorageFailure)

    var errorDescription: String? {
        switch self {
        case .unsafePath(let path):
            return "Unsafe output path: \(path)"
        case .base64DecodingFailed:
            return "Failed to decode base64 data"
        case .storage(let failure):
            return "Storage operation failed: \(failure.message)"
        }
    }
}
