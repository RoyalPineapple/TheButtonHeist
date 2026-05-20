import Foundation
import os.log

import TheScore

private let logger = Logger(subsystem: "com.buttonheist.bookkeeper", category: "heist")

// MARK: - Session Phase State Machine

/// Lifecycle of a BookKeeper session from idle through archive. Each non-idle
/// case carries the phase-specific data valid for that phase.
enum SessionPhase: Sendable {
    case idle
    case active(ActiveSession)
    case closing(ClosingSession)
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
    let sessionId: String
    let directory: URL
    let logHandle: FileHandle
    let manifest: SessionManifest
    var nextSequenceNumber: Int
    var heistRecording: HeistRecordingPhase = .idle

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
    let sessionId: String
    let directory: URL
    let manifest: SessionManifest
    let compressionTask: Task<URL, Error>?

    init(
        sessionId: String,
        directory: URL,
        manifest: SessionManifest,
        compressionTask: Task<URL, Error>? = nil
    ) {
        self.sessionId = sessionId
        self.directory = directory
        self.manifest = manifest
        self.compressionTask = compressionTask
    }

    var startTime: Date {
        manifest.startTime
    }

    var endTime: Date {
        guard let endTime = manifest.endTime else {
            logger.error("Closing session manifest is missing endTime; using startTime")
            return manifest.startTime
        }
        return endTime
    }

    func withCompressionTask(_ compressionTask: Task<URL, Error>?) -> ClosingSession {
        ClosingSession(
            sessionId: sessionId,
            directory: directory,
            manifest: manifest,
            compressionTask: compressionTask
        )
    }
}

struct ClosedSession: Sendable {
    let sessionId: String
    let directory: URL
    let compressedLogPath: URL
    let manifest: SessionManifest

    var startTime: Date {
        manifest.startTime
    }

    var endTime: Date {
        guard let endTime = manifest.endTime else {
            logger.error("Closed session manifest is missing endTime; using startTime")
            return manifest.startTime
        }
        return endTime
    }
}

struct ArchivedSession: Sendable {
    let archivePath: URL
    let manifest: SessionManifest

    var startTime: Date {
        manifest.startTime
    }

    var endTime: Date {
        guard let endTime = manifest.endTime else {
            logger.error("Archived session manifest is missing endTime; using startTime")
            return manifest.startTime
        }
        return endTime
    }
}

// MARK: - BookKeeper Errors

/// Errors thrown by TheBookKeeper during session and artifact operations.
enum BookKeeperError: Error, LocalizedError {
    case invalidPhase(expected: String, actual: String)
    case unsafePath(String)
    case base64DecodingFailed
    case compressionFailed(String)
    case archiveFailed(String)
    case noStepsRecorded
    case notRecordingHeist

    var errorDescription: String? {
        switch self {
        case .invalidPhase(let expected, let actual):
            return "Invalid session phase: expected \(expected), currently \(actual)"
        case .unsafePath(let path):
            return "Unsafe output path: \(path)"
        case .base64DecodingFailed:
            return "Failed to decode base64 data"
        case .compressionFailed(let reason):
            return "Compression failed: \(reason)"
        case .archiveFailed(let reason):
            return "Archive failed: \(reason)"
        case .noStepsRecorded:
            return "No steps were recorded during the heist session"
        case .notRecordingHeist:
            return "No heist recording is in progress"
        }
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
        case .active, .closing:
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
        let logHandle = try FileHandle(forWritingTo: logPath)

        try appendLogLine(buildHeaderLogEntry(sessionId: sessionId), to: logHandle)

        let startTime = Date()
        let manifest = SessionManifest(sessionId: sessionId, startTime: startTime)
        phase = .active(ActiveSession(
            sessionId: sessionId,
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
        let closingSession: ClosingSession
        switch phase {
        case .active(let session):
            closingSession = try beginClosingSession(session)
        case .closing(let session):
            closingSession = ensureCompressionTask(for: session)
        case .idle, .closed, .archived:
            throw BookKeeperError.invalidPhase(expected: "active or closing", actual: phaseName)
        }

        try await completeClosingSession(closingSession)
    }

    private func beginClosingSession(_ session: ActiveSession) throws -> ClosingSession {
        let closedManifest = session.manifest.closed(at: Date())
        try flushManifest(manifest: closedManifest, directory: session.directory)

        var closingSession = ClosingSession(
            sessionId: session.sessionId,
            directory: session.directory,
            manifest: closedManifest
        )
        session.logHandle.closeFile()

        // Close heist recording handle if still open (abandoned recording)
        if case .recording(let abandonedRecording) = session.heistRecording {
            abandonedRecording.fileHandle.closeFile()
        }

        closingSession = closingSession.withCompressionTask(makeCompressionTask(for: closingSession))
        phase = .closing(closingSession)
        return closingSession
    }

    private func ensureCompressionTask(for session: ClosingSession) -> ClosingSession {
        if session.compressionTask != nil {
            return session
        }
        let retryingSession = session.withCompressionTask(makeCompressionTask(for: session))
        phase = .closing(retryingSession)
        return retryingSession
    }

    private func makeCompressionTask(for session: ClosingSession) -> Task<URL, Error> {
        let directory = session.directory
        return Task {
            try await Self.compressLog(in: directory)
        }
    }

    private func completeClosingSession(_ session: ClosingSession) async throws {
        let closingSession = ensureCompressionTask(for: session)
        guard let compressionTask = closingSession.compressionTask else {
            throw BookKeeperError.compressionFailed(
                "Missing compression task for closing session \(closingSession.sessionId)"
            )
        }
        let compressedPath: URL
        do {
            compressedPath = try await compressionTask.value
        } catch {
            clearFailedCompressionTask(for: closingSession)
            throw error
        }

        if case .closed(let closedSession) = phase,
           closedSession.directory == closingSession.directory {
            return
        }

        guard case .closing(let currentSession) = phase,
              currentSession.directory == closingSession.directory else {
            return
        }

        phase = .closed(ClosedSession(
            sessionId: closingSession.sessionId,
            directory: closingSession.directory,
            compressedLogPath: compressedPath,
            manifest: closingSession.manifest
        ))
    }

    private func clearFailedCompressionTask(for session: ClosingSession) {
        guard case .closing(let currentSession) = phase,
              currentSession.directory == session.directory else {
            return
        }
        phase = .closing(currentSession.withCompressionTask(nil))
    }

    func archiveSession(deleteSource: Bool = false) async throws -> (URL, SessionLogSnapshot) {
        guard case .closed(let session) = phase else {
            throw BookKeeperError.invalidPhase(expected: "closed", actual: phaseName)
        }

        let archivePath = try await createArchive(session: session)
        let snapshot = try sessionLogSnapshot(manifest: session.manifest, archivePath: archivePath)

        if deleteSource {
            try FileManager.default.removeItem(at: session.directory)
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
        let entry = buildCommandLogEntry(request)
        try appendLogLine(entry, to: session.logHandle)
    }

    func logResponse(
        requestId: String,
        status: ResponseStatus,
        durationMilliseconds: Int,
        artifact: String? = nil,
        error: String? = nil
    ) throws {
        guard case .active(let session) = phase else { return }
        let entry = buildResponseLogEntry(
            requestId: requestId,
            status: status,
            durationMilliseconds: durationMilliseconds,
            artifact: artifact,
            error: error
        )
        try appendLogLine(entry, to: session.logHandle)
    }

    // MARK: - Artifact Storage

    func writeScreenshot(
        base64Data: String,
        requestId: String,
        command: TheFence.Command,
        metadata: ScreenshotMetadata
    ) throws -> URL {
        guard case .active(var session) = phase else {
            throw BookKeeperError.invalidPhase(expected: "active", actual: phaseName)
        }
        guard let data = Data(base64Encoded: base64Data) else {
            throw BookKeeperError.base64DecodingFailed
        }

        let sequenceNumber = session.nextSequenceNumber
        session.nextSequenceNumber += 1
        let filename = String(format: "%03d-%@.png", sequenceNumber, command.rawValue)
        let subdirectory = session.directory.appendingPathComponent("screenshots")
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        let fileURL = subdirectory.appendingPathComponent(filename)
        try data.write(to: fileURL)

        let entry = ArtifactEntry(
            type: .screenshot,
            path: "screenshots/\(filename)",
            size: data.count,
            timestamp: Date(),
            requestId: requestId,
            command: command.rawValue,
            metadata: ["width": metadata.width, "height": metadata.height]
        )
        try appendLogLine(buildArtifactLogEntry(entry), to: session.logHandle)
        phase = .active(session)

        return fileURL
    }

    func writeRecording(
        base64Data: String,
        requestId: String,
        command: TheFence.Command,
        metadata: RecordingMetadata
    ) throws -> URL {
        guard case .active(var session) = phase else {
            throw BookKeeperError.invalidPhase(expected: "active", actual: phaseName)
        }
        guard let data = Data(base64Encoded: base64Data) else {
            throw BookKeeperError.base64DecodingFailed
        }

        let sequenceNumber = session.nextSequenceNumber
        session.nextSequenceNumber += 1
        let filename = String(format: "%03d-%@.mp4", sequenceNumber, command.rawValue)
        let subdirectory = session.directory.appendingPathComponent("recordings")
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        let fileURL = subdirectory.appendingPathComponent(filename)
        try data.write(to: fileURL)

        let entry = ArtifactEntry(
            type: .recording,
            path: "recordings/\(filename)",
            size: data.count,
            timestamp: Date(),
            requestId: requestId,
            command: command.rawValue,
            metadata: [
                "width": Double(metadata.width),
                "height": Double(metadata.height),
                "duration": metadata.duration,
                "fps": Double(metadata.fps),
                "frameCount": Double(metadata.frameCount),
            ]
        )
        try appendLogLine(buildArtifactLogEntry(entry), to: session.logHandle)
        phase = .active(session)

        return fileURL
    }

    func writeToPath(_ data: Data, outputPath: String) throws -> URL {
        guard let resolvedURL = validateOutputPath(outputPath) else {
            throw BookKeeperError.unsafePath(outputPath)
        }
        try data.write(to: resolvedURL)
        return resolvedURL
    }

    /// Write a screenshot to whichever sink is available, or return `nil` if
    /// neither a session is active nor an explicit outputPath was supplied.
    ///
    /// Resolution rules:
    /// - `outputPath` supplied → write raw bytes to that path via
    ///   `writeToPath` (no session log artifact event).
    /// - No `outputPath`, session active → write via `writeScreenshot` into
    ///   the session's artifact directory and append an artifact event.
    /// - No `outputPath`, no session → return `nil`; caller is expected to
    ///   return the in-memory payload (e.g. `.screenshotData`).
    func writeScreenshotIfSinkAvailable(
        base64Data: String,
        outputPath: String?,
        requestId: String,
        command: TheFence.Command,
        metadata: ScreenshotMetadata
    ) throws -> URL? {
        if let outputPath {
            guard let data = Data(base64Encoded: base64Data) else {
                throw BookKeeperError.base64DecodingFailed
            }
            return try writeToPath(data, outputPath: outputPath)
        }
        guard case .active = phase else {
            return nil
        }
        return try writeScreenshot(
            base64Data: base64Data, requestId: requestId,
            command: command, metadata: metadata
        )
    }

    /// Write a screenshot to an explicit path, the active session artifact
    /// directory, or a standalone artifact directory when no session exists.
    func writeScreenshotArtifact(
        base64Data: String,
        outputPath: String?,
        requestId: String,
        command: TheFence.Command,
        metadata: ScreenshotMetadata
    ) throws -> URL {
        if let url = try writeScreenshotIfSinkAvailable(
            base64Data: base64Data,
            outputPath: outputPath,
            requestId: requestId,
            command: command,
            metadata: metadata
        ) {
            return url
        }
        guard let data = Data(base64Encoded: base64Data) else {
            throw BookKeeperError.base64DecodingFailed
        }

        let subdirectory = baseDirectory.appendingPathComponent("screenshots")
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        let filename = "\(Self.timestampString())-\(UUID().uuidString)-\(command.rawValue).png"
        let fileURL = subdirectory.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }

    /// Write a recording to whichever sink is available. Resolution rules
    /// match `writeScreenshotIfSinkAvailable` — outputPath wins, then session,
    /// then nil.
    func writeRecordingIfSinkAvailable(
        base64Data: String,
        outputPath: String?,
        requestId: String,
        command: TheFence.Command,
        metadata: RecordingMetadata
    ) throws -> URL? {
        if let outputPath {
            guard let data = Data(base64Encoded: base64Data) else {
                throw BookKeeperError.base64DecodingFailed
            }
            return try writeToPath(data, outputPath: outputPath)
        }
        guard case .active = phase else {
            return nil
        }
        return try writeRecording(
            base64Data: base64Data, requestId: requestId,
            command: command, metadata: metadata
        )
    }

    // MARK: - Heist Recording

    var isRecordingHeist: Bool {
        guard case .active(let session) = phase,
              case .recording = session.heistRecording else { return false }
        return true
    }

    func startHeistRecording(app: String) throws {
        guard case .active(var session) = phase else {
            throw BookKeeperError.invalidPhase(expected: "active", actual: phaseName)
        }
        guard case .idle = session.heistRecording else {
            throw BookKeeperError.invalidPhase(expected: "not recording heist", actual: "recording heist")
        }

        let heistPath = session.directory.appendingPathComponent("heist.jsonl")
        try Self.createPrivateFile(at: heistPath)
        let heistHandle = try FileHandle(forWritingTo: heistPath)

        session.heistRecording = .recording(HeistRecording(
            app: app,
            startTime: Date(),
            fileHandle: heistHandle,
            filePath: heistPath
        ))
        phase = .active(session)
    }

    func stopHeistRecording() throws -> HeistPlayback {
        guard case .active(var session) = phase else {
            throw BookKeeperError.invalidPhase(expected: "active", actual: phaseName)
        }
        guard case .recording(let recording) = session.heistRecording else {
            throw BookKeeperError.notRecordingHeist
        }

        recording.fileHandle.closeFile()
        defer {
            session.heistRecording = .idle
            phase = .active(session)
        }

        let steps = try readEvidenceFromFile(recording.filePath)
        guard !steps.isEmpty else {
            throw BookKeeperError.noStepsRecorded
        }

        return HeistPlayback(
            recorded: recording.startTime,
            app: recording.app,
            steps: steps
        )
    }

    /// Read HeistEvidence entries from a JSONL file.
    ///
    /// Malformed lines are logged and skipped rather than discarding the whole
    /// recording. A single corrupt entry shouldn't destroy the other N-1 steps
    /// captured during the heist.
    private func readEvidenceFromFile(_ path: URL) throws -> [HeistEvidence] {
        let data = try Data(contentsOf: path)
        let lines = data.split(separator: 0x0A)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return lines.enumerated().compactMap { index, lineData in
            do {
                return try decoder.decode(HeistEvidence.self, from: Data(lineData))
            } catch {
                logger.warning(
                    "Skipping malformed heist line \(index) in \(path.lastPathComponent): \(error.localizedDescription)"
                )
                return nil
            }
        }
    }

    /// Commands that should not appear in heist playbacks.
    private static let excludedHeistCommands: Set<TheFence.Command> = [
        .help, .status, .quit, .exit,
        .listDevices, .getInterface, .getScreen,
        .getPasteboard,
        .getSessionState, .connect, .listTargets,
        .getSessionLog, .archiveSession,
        .startRecording, .stopRecording,
        .runBatch,
        .startHeist, .stopHeist, .playHeist,
    ]

    /// Record a successfully executed command for heist playback.
    /// Only records commands that succeeded — failed actions are skipped.
    /// - Parameters:
    ///   - actionResult: The command's result envelope payload. Failed results are skipped.
    ///   - expectation: Final expectation evidence for the command. Failed expectations are skipped.
    ///   - targetCapture: Capture containing the target at command time. The
    ///     recorder resolves `heistId` arguments only against this capture so
    ///     matchers are derived from durable capture evidence, not cache state.
    func recordHeistEvidence(
        _ request: TheFence.ParsedRequest,
        actionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil,
        targetCapture: AccessibilityTrace.Capture?
    ) {
        guard case .active(let session) = phase,
              case .recording(let recording) = session.heistRecording else { return }
        guard !Self.excludedHeistCommands.contains(request.command) else { return }
        guard actionResult?.success != false else { return }
        guard expectation?.met != false else { return }

        let step = buildStep(
            request: request,
            targetCapture: targetCapture,
            actionResult: actionResult,
            expectation: expectation
        )

        // Write evidence to durable file (append-only JSONL)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        do {
            var lineData = try encoder.encode(step)
            lineData.append(contentsOf: [0x0A])
            recording.fileHandle.write(lineData)
        } catch {
            logger.error(
                "Failed to encode heist evidence for \(request.command.rawValue): \(error.localizedDescription)"
            )
            return
        }
    }

    // MARK: - Heist Step Construction

    private func buildStep(
        request: TheFence.ParsedRequest,
        targetCapture: AccessibilityTrace.Capture?,
        actionResult: ActionResult?,
        expectation: ExpectationResult?
    ) -> HeistEvidence {
        var target: ElementMatcher?
        var ordinal: Int?
        var recordedHeistId: HeistId?
        var recordedFrame: RecordedFrame?
        var coordinateOnly: Bool?

        if case .heistId(let heistId)? = request.bookKeeperElementTarget,
           let source = matcherSource(
            heistId: heistId,
            targetCapture: targetCapture
        ) {
            let minimumMatcher = MinimumMatcher.build(element: source.element, in: source.capture)
            target = minimumMatcher.matcher
            ordinal = minimumMatcher.ordinal
            recordedHeistId = heistId
            recordedFrame = RecordedFrame(
                x: source.element.frameX, y: source.element.frameY,
                width: source.element.frameWidth, height: source.element.frameHeight
            )
        } else if case .matcher(let matcher, let matchedOrdinal)? = request.bookKeeperElementTarget {
            target = matcher
            ordinal = matchedOrdinal
        } else if request.bookKeeperCoordinateOnly {
            coordinateOnly = true
        }

        return HeistEvidence(
            command: request.command.rawValue,
            target: target,
            ordinal: ordinal,
            arguments: request.bookKeeperHeistArguments,
            recorded: buildRecordedMetadata(
                heistId: recordedHeistId,
                frame: recordedFrame,
                coordinateOnly: coordinateOnly,
                actionResult: actionResult,
                expectation: expectation
            )
        )
    }

    private func matcherSource(
        heistId: HeistId,
        targetCapture: AccessibilityTrace.Capture?
    ) -> (element: HeistElement, capture: AccessibilityTrace.Capture)? {
        guard let targetCapture else { return nil }
        let elementsByHeistId = targetCapture.interface.elements.reduce(
            into: [HeistId: HeistElement]()
        ) { partialResult, element in
            partialResult[element.heistId] = element
        }
        guard let element = elementsByHeistId[heistId] else { return nil }
        return (element, targetCapture)
    }

    private func buildRecordedMetadata(
        heistId: HeistId?,
        frame: RecordedFrame?,
        coordinateOnly: Bool?,
        actionResult: ActionResult?,
        expectation: ExpectationResult?
    ) -> RecordedMetadata? {
        let accessibilityTrace = actionResult?.accessibilityTrace
        guard heistId != nil ||
            frame != nil ||
            coordinateOnly != nil ||
            accessibilityTrace != nil ||
            expectation != nil else {
            return nil
        }
        return RecordedMetadata(
            heistId: heistId,
            frame: frame,
            coordinateOnly: coordinateOnly,
            accessibilityTrace: accessibilityTrace,
            expectation: expectation
        )
    }

    // MARK: - Heist File I/O

    static func writeHeist(_ script: HeistPlayback, to path: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(script)
        try writePrivateData(data, to: path)
    }

    static func readHeist(from path: URL) throws -> HeistPlayback {
        let data = try Data(contentsOf: path)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HeistPlayback.self, from: data)
    }

    // MARK: - Path Safety

    func validateOutputPath(_ path: String) -> URL? {
        path.validatedOutputURL()
    }

    // MARK: - Phase / Directory / Manifest Helpers

    private var phaseName: String {
        switch phase {
        case .idle: return "idle"
        case .active: return "active"
        case .closing: return "closing"
        case .closed: return "closed"
        case .archived: return "archived"
        }
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

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

    nonisolated private static func createPrivateDirectory(at directory: URL) throws {
        let fileManager = FileManager.default
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: attributes
        )
        try fileManager.setAttributes(attributes, ofItemAtPath: directory.path)
    }

    nonisolated private static func createPrivateFile(at url: URL, contents: Data? = nil) throws {
        let fileManager = FileManager.default
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
            if let contents {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.truncate(atOffset: 0)
                try handle.write(contentsOf: contents)
            }
            return
        }

        guard fileManager.createFile(
            atPath: url.path,
            contents: contents,
            attributes: attributes
        ) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
    }

    nonisolated private static func writePrivateData(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try createPrivateFile(at: temporaryURL, contents: data)
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.moveItem(at: temporaryURL, to: url)
            try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func flushManifest(manifest: SessionManifest, directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        let manifestPath = directory.appendingPathComponent("manifest.json")
        try Self.writePrivateData(data, to: manifestPath)
    }

    private func sessionLogSnapshot(manifest: SessionManifest, directory: URL) throws -> SessionLogSnapshot {
        let projection = try sessionLogProjection(in: directory)
        return SessionLogSnapshot(
            manifest: manifest,
            counts: projection.counts,
            artifacts: projection.artifacts,
            projectionStatus: projection.status
        )
    }

    private func sessionLogSnapshot(manifest: SessionManifest, archivePath: URL) throws -> SessionLogSnapshot {
        let projection = try sessionLogProjection(inArchive: archivePath)
        return SessionLogSnapshot(
            manifest: manifest,
            counts: projection.counts,
            artifacts: projection.artifacts,
            projectionStatus: projection.status
        )
    }
}
