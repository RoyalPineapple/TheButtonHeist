import Foundation

import TheScore

// MARK: - Session Phase State Machine

/// Lifecycle of a BookKeeper session from idle through closed. Each non-idle
/// case carries the phase-specific data valid for that phase.
enum SessionPhase: Sendable {
    case idle
    case active(ActiveSession)
    case closed(ClosedSession)
}

/// Two-phase heist-recording lifecycle inside an active session: either no
/// recording is in progress, or one is and carries its file handle and path.
/// Replaces the `HeistRecording?` optional so the "not recording" phase is
/// structurally distinct from any in-flight recording.
enum HeistRecordingPhase: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    case idle
    case recording(HeistRecording)
}

struct ActiveSession: Sendable {
    let directory: URL
    let manifest: SessionManifest
    var nextSequenceNumber: Int
    var heistRecording: HeistRecordingPhase = .idle

    var sessionId: String {
        manifest.sessionId
    }

    var startTime: Date {
        manifest.startTime
    }
}

/// Heist recording handle. Marked `@unchecked Sendable` because `fileHandle`
/// is a `FileHandle`; access is confined to the `@ButtonHeistActor`-isolated
/// `TheBookKeeper`.
struct HeistRecording: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    let app: String
    let fileHandle: FileHandle
    let filePath: URL
}

struct ClosedSession: Sendable {
    let directory: URL
    let manifest: SessionManifest

    var sessionId: String {
        manifest.sessionId
    }

    var startTime: Date {
        manifest.startTime
    }

    var endTime: Date? {
        manifest.endTime
    }
}

// MARK: - TheBookKeeper

/// Manages session lifecycle, artifact storage, and heist recording.
@ButtonHeistActor
final class TheBookKeeper {

    private(set) var phase: SessionPhase = .idle
    private let baseDirectory: URL

    init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory ?? Self.resolveBaseDirectory()
    }

    var manifest: SessionManifest? {
        switch phase {
        case .idle:
            return nil
        case .active(let session):
            return session.manifest
        case .closed(let session):
            return session.manifest
        }
    }

    // MARK: - Lifecycle

    func beginSession(identifier: String) throws {
        switch phase {
        case .idle, .closed:
            break
        case .active:
            throw BookKeeperError.invalidPhase(expected: "idle or closed", actual: phaseName)
        }

        guard Self.isSafeSessionIdentifier(identifier) else {
            throw BookKeeperError.unsafePath(identifier)
        }

        let timestamp = Self.timestampString()
        let sessionId = "\(identifier)-\(timestamp)"
        let directory = baseDirectory.appendingPathComponent(sessionId)
        try Self.createPrivateDirectory(at: directory)

        let startTime = Date()
        let manifest = SessionManifest(sessionId: sessionId, startTime: startTime)
        phase = .active(ActiveSession(
            directory: directory,
            manifest: manifest,
            nextSequenceNumber: 1
        ))
    }

    private static func isSafeSessionIdentifier(_ identifier: String) -> Bool {
        guard !identifier.isEmpty,
              !identifier.hasPrefix("-"),
              !identifier.contains("/"),
              !identifier.contains("..") else { return false }

        return !identifier.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
    }

    func closeSession() async throws {
        switch phase {
        case .active(let session):
            try closeActiveSession(session)
        case .idle, .closed:
            throw BookKeeperError.invalidPhase(expected: "active", actual: phaseName)
        }
    }

    private func closeActiveSession(_ session: ActiveSession) throws {
        let closedManifest = session.manifest.closed(at: Date())
        try flushManifest(manifest: closedManifest, directory: session.directory)

        // Close heist recording handle if still open (abandoned recording)
        if case .recording(let abandonedRecording) = session.heistRecording {
            abandonedRecording.fileHandle.closeFile()
        }

        phase = .closed(ClosedSession(
            directory: session.directory,
            manifest: closedManifest
        ))
    }

    // MARK: - Phase / Directory / Manifest Helpers

    var phaseName: String {
        switch phase {
        case .idle: return "idle"
        case .active: return "active"
        case .closed: return "closed"
        }
    }

    var artifactBaseDirectory: URL {
        baseDirectory
    }

    var hasActiveSession: Bool {
        guard case .active = phase else { return false }
        return true
    }

    func mutateActiveSession<T>(_ body: (inout ActiveSession) throws -> T) throws -> T {
        guard case .active(var session) = phase else {
            throw BookKeeperError.invalidPhase(expected: "active", actual: phaseName)
        }
        let result = try body(&session)
        phase = .active(session)
        return result
    }

    private static func resolveBaseDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["BUTTONHEIST_SESSIONS_DIR"] {
            return URL(fileURLWithPath: override)
        }
        if let xdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"] {
            return URL(fileURLWithPath: xdgDataHome)
                .appendingPathComponent("buttonheist")
                .appendingPathComponent("sessions")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/buttonheist/sessions")
    }

    static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

}
