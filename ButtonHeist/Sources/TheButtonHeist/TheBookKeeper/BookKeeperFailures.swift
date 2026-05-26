import Foundation

enum BookKeeperProcessFailure: Sendable, Equatable {
    case launchFailed(context: String, reason: String)
    case exited(context: String, status: Int32, detail: String?)

    var message: String {
        switch self {
        case .launchFailed(let context, let reason):
            return "\(context) failed to launch: \(reason)"
        case .exited(let context, let status, let detail):
            return "\(context) exited with status \(status): \(detail ?? "unknown error")"
        }
    }
}

enum BookKeeperSessionFailure: Sendable, Equatable {
    case directoryCreationFailed(path: String, reason: String)
    case logFileCreationFailed(path: String, reason: String)
    case logFileOpenFailed(path: String, reason: String)
    case headerWriteFailed(path: String, reason: String)
    case sourceDeletionFailed(path: String, reason: String)

    var message: String {
        switch self {
        case .directoryCreationFailed(let path, let reason):
            return "Failed to create session directory at \(path): \(reason)"
        case .logFileCreationFailed(let path, let reason):
            return "Failed to create session log at \(path): \(reason)"
        case .logFileOpenFailed(let path, let reason):
            return "Failed to open session log at \(path): \(reason)"
        case .headerWriteFailed(let path, let reason):
            return "Failed to write session header at \(path): \(reason)"
        case .sourceDeletionFailed(let path, let reason):
            return "Failed to delete session source at \(path): \(reason)"
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

enum BookKeeperCompressionFailure: Sendable, Equatable {
    case process(BookKeeperProcessFailure)
    case outputMissing(path: String)
    case permissionUpdateFailed(path: String, reason: String)

    var message: String {
        switch self {
        case .process(let failure):
            return failure.message
        case .outputMissing(let path):
            return "Expected compressed file not found at \(path)"
        case .permissionUpdateFailed(let path, let reason):
            return "Failed to restrict permissions at \(path): \(reason)"
        }
    }
}

enum BookKeeperArchiveFailure: Sendable, Equatable {
    case process(BookKeeperProcessFailure)
    case outputMissing(path: String)
    case sessionLogMissing(path: String)
    case permissionUpdateFailed(path: String, reason: String)

    var message: String {
        switch self {
        case .process(let failure):
            return failure.message
        case .outputMissing(let path):
            return "Expected archive not found at \(path)"
        case .sessionLogMissing(let path):
            return "Expected session log not found in archive \(path)"
        case .permissionUpdateFailed(let path, let reason):
            return "Failed to restrict permissions at \(path): \(reason)"
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
    case compressionFailed(BookKeeperCompressionFailure)
    case archiveFailed(BookKeeperArchiveFailure)
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
        case .compressionFailed(let failure):
            return "Compression failed: \(failure.message)"
        case .archiveFailed(let failure):
            return "Archive failed: \(failure.message)"
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
