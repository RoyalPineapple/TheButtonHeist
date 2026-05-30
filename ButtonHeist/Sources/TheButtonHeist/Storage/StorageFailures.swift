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

enum HeistRecordingFailure: Sendable, Equatable {
    case alreadyRecording
    case notRecording
    case fileCreationFailed(path: String, reason: String)
    case fileOpenFailed(path: String, reason: String)
    case stepReadFailed(path: String, reason: String)
    case noValidSteps(path: String)
    case heistWriteFailed(path: String, reason: String)
    case heistReadFailed(path: String, reason: String)

    var message: String {
        switch self {
        case .alreadyRecording:
            return "A heist recording is already in progress"
        case .notRecording:
            return "No heist recording is in progress"
        case .fileCreationFailed(let path, let reason):
            return "Failed to create heist recording at \(path): \(reason)"
        case .fileOpenFailed(let path, let reason):
            return "Failed to open heist recording at \(path): \(reason)"
        case .stepReadFailed(let path, let reason):
            return "Failed to read heist step at \(path): \(reason)"
        case .noValidSteps:
            return "No steps were recorded during the heist"
        case .heistWriteFailed(let path, let reason):
            return "Failed to write heist at \(path): \(reason)"
        case .heistReadFailed(let path, let reason):
            return "Failed to read heist at \(path): \(reason)"
        }
    }
}

/// Errors thrown while writing heists and screenshot artifacts.
enum StorageError: Error, LocalizedError {
    case unsafePath(String)
    case base64DecodingFailed
    case storage(StorageFailure)
    case heistRecording(HeistRecordingFailure)

    var errorDescription: String? {
        switch self {
        case .unsafePath(let path):
            return "Unsafe output path: \(path)"
        case .base64DecodingFailed:
            return "Failed to decode base64 data"
        case .storage(let failure):
            return "Storage operation failed: \(failure.message)"
        case .heistRecording(let failure):
            return "Heist recording failed: \(failure.message)"
        }
    }
}
