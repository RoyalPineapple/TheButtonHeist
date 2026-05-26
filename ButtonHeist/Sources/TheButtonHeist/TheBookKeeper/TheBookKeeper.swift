import Foundation

import TheScore

// MARK: - Session Phase State Machine

/// Lifecycle of a BookKeeper session from idle through archive. Each non-idle
/// case carries the phase-specific data valid for that phase.
enum SessionPhase: Sendable {
    case idle
    case active(ActiveSession)
    case closing(ClosingSession)
    case compressing(CompressingSession)
    case closed(ClosedSession)
    case archived(ArchivedSession)
}

/// Two-phase heist-recording lifecycle inside an active session: either no
/// recording is in progress, or one is and carries its file handle and path.
/// Replaces the `HeistRecording?` optional so the "not recording" phase is
/// structurally distinct from any in-flight recording.
enum HeistRecordingPhase: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    case idle
    case recording(HeistRecording)
}

/// Active session payload. Marked `@unchecked Sendable` because `logHandle`
/// is a `FileHandle` (not Sendable on Swift 6); access is in practice
/// confined to the `@ButtonHeistActor`-isolated `TheBookKeeper` that owns
/// the value.
struct ActiveSession: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    let directory: URL
    let logHandle: FileHandle
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
    let startTime: Date
    let fileHandle: FileHandle
    let filePath: URL
}

struct ClosingSession: Sendable {
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

struct CompressingSession: Sendable {
    let directory: URL
    let manifest: SessionManifest
    let compressionTask: Task<URL, Error>

    init(closingSession: ClosingSession, compressionTask: Task<URL, Error>) {
        self.directory = closingSession.directory
        self.manifest = closingSession.manifest
        self.compressionTask = compressionTask
    }

    var sessionId: String {
        manifest.sessionId
    }

    var retryableSession: ClosingSession {
        ClosingSession(
            directory: directory,
            manifest: manifest
        )
    }

    var startTime: Date {
        manifest.startTime
    }

    var endTime: Date? {
        manifest.endTime
    }
}

struct ClosedSession: Sendable {
    let directory: URL
    let compressedLogPath: URL
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

struct ArchivedSession: Sendable {
    let archivePath: URL
    let manifest: SessionManifest

    var startTime: Date {
        manifest.startTime
    }

    var endTime: Date? {
        manifest.endTime
    }
}

// MARK: - TheBookKeeper

/// Manages session lifecycle, command logging, artifact storage, and heist recording.
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
        case .closing(let session):
            return session.manifest
        case .compressing(let session):
            return session.manifest
        case .closed(let session):
            return session.manifest
        case .archived(let session):
            return session.manifest
        }
    }

    func sessionLogSnapshot() throws -> SessionLogSnapshot? {
        switch phase {
        case .idle:
            return nil
        case .active(let session):
            return try sessionLogSnapshot(manifest: session.manifest, directory: session.directory)
        case .closing(let session):
            return try sessionLogSnapshot(manifest: session.manifest, directory: session.directory)
        case .compressing(let session):
            return try sessionLogSnapshot(manifest: session.manifest, directory: session.directory)
        case .closed(let session):
            return try sessionLogSnapshot(manifest: session.manifest, directory: session.directory)
        case .archived(let session):
            return try sessionLogSnapshot(manifest: session.manifest, archivePath: session.archivePath)
        }
    }

    // MARK: - Lifecycle

    func beginSession(identifier: String) throws {
        switch phase {
        case .idle, .closed, .archived:
            break
        case .active, .closing, .compressing:
            throw BookKeeperError.invalidPhase(expected: "idle, closed, or archived", actual: phaseName)
        }

        guard Self.isSafeSessionIdentifier(identifier) else {
            throw BookKeeperError.unsafePath(identifier)
        }

        let timestamp = Self.timestampString()
        let sessionId = "\(identifier)-\(timestamp)"
        let directory = baseDirectory.appendingPathComponent(sessionId)
        try Self.createPrivateDirectory(at: directory)

        let logPath = directory.appendingPathComponent("session.jsonl")
        try Self.createPrivateFile(at: logPath)
        let logHandle = try openSessionLog(at: logPath)
        try writeSessionHeader(sessionId: sessionId, to: logHandle, logPath: logPath)

        let startTime = Date()
        let manifest = SessionManifest(sessionId: sessionId, startTime: startTime)
        phase = .active(ActiveSession(
            directory: directory,
            logHandle: logHandle,
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
        let compressingSession: CompressingSession
        switch phase {
        case .active(let session):
            let closingSession = try beginClosingSession(session)
            compressingSession = beginCompression(for: closingSession)
        case .closing(let session):
            compressingSession = beginCompression(for: session)
        case .compressing(let session):
            compressingSession = session
        case .idle, .closed, .archived:
            throw BookKeeperError.invalidPhase(expected: "active or closing", actual: phaseName)
        }

        try await completeClosingSession(compressingSession)
    }

    private func beginClosingSession(_ session: ActiveSession) throws -> ClosingSession {
        let closedManifest = session.manifest.closed(at: Date())
        try flushManifest(manifest: closedManifest, directory: session.directory)

        let closingSession = ClosingSession(
            directory: session.directory,
            manifest: closedManifest
        )
        session.logHandle.closeFile()

        // Close heist recording handle if still open (abandoned recording)
        if case .recording(let abandonedRecording) = session.heistRecording {
            abandonedRecording.fileHandle.closeFile()
        }

        phase = .closing(closingSession)
        return closingSession
    }

    private func beginCompression(for session: ClosingSession) -> CompressingSession {
        let compressingSession = CompressingSession(
            closingSession: session,
            compressionTask: makeCompressionTask(for: session)
        )
        phase = .compressing(compressingSession)
        return compressingSession
    }

    private func makeCompressionTask(for session: ClosingSession) -> Task<URL, Error> {
        let directory = session.directory
        return Task {
            try await Self.compressLog(in: directory)
        }
    }

    private func completeClosingSession(_ closingSession: CompressingSession) async throws {
        let compressedPath: URL
        do {
            compressedPath = try await closingSession.compressionTask.value
        } catch {
            markCompressionFailed(for: closingSession)
            throw error
        }

        if case .closed(let closedSession) = phase,
           closedSession.directory == closingSession.directory {
            return
        }

        guard case .compressing(let currentSession) = phase,
              currentSession.directory == closingSession.directory else {
            return
        }

        phase = .closed(ClosedSession(
            directory: closingSession.directory,
            compressedLogPath: compressedPath,
            manifest: closingSession.manifest
        ))
    }

    private func markCompressionFailed(for session: CompressingSession) {
        guard case .compressing(let currentSession) = phase,
              currentSession.directory == session.directory else {
            return
        }
        phase = .closing(currentSession.retryableSession)
    }

    func archiveSession(deleteSource: Bool = false) async throws -> (URL, SessionLogSnapshot) {
        guard case .closed(let session) = phase else {
            throw BookKeeperError.invalidPhase(expected: "closed", actual: phaseName)
        }

        let archivePath = try await createArchive(session: session)
        let snapshot = try sessionLogSnapshot(manifest: session.manifest, archivePath: archivePath)

        if deleteSource {
            try deleteSessionSourceDirectory(session.directory)
        }

        phase = .archived(ArchivedSession(
            archivePath: archivePath,
            manifest: snapshot.manifest
        ))

        return (archivePath, snapshot)
    }

    // MARK: - Logging

    func logCommand(_ request: TheFence.ParsedRequest) throws {
        guard case .active(let session) = phase else { return }
        try appendLogLine(CommandLogEntry(
            t: iso8601Now(),
            requestId: request.requestId,
            command: request.command.rawValue
        ), to: session.logHandle)
    }

    func logResponse(
        requestId: String,
        status: ResponseStatus,
        durationMilliseconds: Int,
        error: String? = nil
    ) throws {
        guard case .active(let session) = phase else { return }
        try appendLogLine(ResponseLogEntry(
            t: iso8601Now(),
            requestId: requestId,
            status: status,
            durationMilliseconds: durationMilliseconds,
            error: error
        ), to: session.logHandle)
    }

    // MARK: - Path Safety

    func validateOutputPath(_ path: String) -> URL? {
        path.validatedOutputURL()
    }

    // MARK: - Phase / Directory / Manifest Helpers

    var phaseName: String {
        switch phase {
        case .idle: return "idle"
        case .active: return "active"
        case .closing, .compressing: return "closing"
        case .closed: return "closed"
        case .archived: return "archived"
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
