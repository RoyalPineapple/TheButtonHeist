import Foundation

enum BookKeeperSessionFailure: Sendable, Equatable {
    case directoryCreationFailed(path: String, reason: String)
    case privateFileCreationFailed(path: String, reason: String)

    var message: String {
        switch self {
        case .directoryCreationFailed(let path, let reason):
            return "Failed to create session directory at \(path): \(reason)"
        case .privateFileCreationFailed(let path, let reason):
            return "Failed to create private file at \(path): \(reason)"
        }
    }
}

enum BookKeeperManifestFailure: Sendable, Equatable {
    case invalidData(sessionId: String, reason: String)
    case writeFailed(sessionId: String, path: String, reason: String)

    var message: String {
        switch self {
        case .invalidData(let sessionId, let reason):
            return "Invalid manifest data for \(sessionId): \(reason)"
        case .writeFailed(let sessionId, let path, let reason):
            return "Failed to write manifest for \(sessionId) at \(path): \(reason)"
        }
    }
}

enum BookKeeperHeistRecordingFailure: Sendable, Equatable {
    case alreadyRecording
    case notRecording
    case fileCreationFailed(path: String, reason: String)
    case fileOpenFailed(path: String, reason: String)
    case evidenceReadFailed(path: String, reason: String)
    case noValidSteps(path: String)
    case scriptWriteFailed(path: String, reason: String)
    case scriptReadFailed(path: String, reason: String)

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
        case .evidenceReadFailed(let path, let reason):
            return "Failed to read heist evidence at \(path): \(reason)"
        case .noValidSteps:
            return "No steps were recorded during the heist session"
        case .scriptWriteFailed(let path, let reason):
            return "Failed to write heist script at \(path): \(reason)"
        case .scriptReadFailed(let path, let reason):
            return "Failed to read heist script at \(path): \(reason)"
        }
    }
}

/// Errors thrown by TheBookKeeper during session and artifact operations.
enum BookKeeperError: Error, LocalizedError {
    case invalidPhase(expected: String, actual: String)
    case unsafePath(String)
    case base64DecodingFailed
    case session(BookKeeperSessionFailure)
    case manifest(BookKeeperManifestFailure)
    case heistRecording(BookKeeperHeistRecordingFailure)

    var errorDescription: String? {
        switch self {
        case .invalidPhase(let expected, let actual):
            return "Invalid session phase: expected \(expected), currently \(actual)"
        case .unsafePath(let path):
            return "Unsafe output path: \(path)"
        case .base64DecodingFailed:
            return "Failed to decode base64 data"
        case .session(let failure):
            return "Session operation failed: \(failure.message)"
        case .manifest(let failure):
            return "Manifest failed: \(failure.message)"
        case .heistRecording(let failure):
            return "Heist recording failed: \(failure.message)"
        }
    }
}

extension SessionManifest {
    func requireClosedEndTime() throws -> Date {
        guard let endTime else {
            throw BookKeeperError.manifest(.invalidData(
                sessionId: sessionId,
                reason: "terminal session manifest is missing endTime"
            ))
        }
        return endTime
    }
}
