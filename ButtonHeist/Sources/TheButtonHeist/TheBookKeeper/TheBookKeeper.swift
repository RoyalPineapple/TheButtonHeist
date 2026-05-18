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

    var startTime: Date {
        manifest.startTime
    }

    var endTime: Date {
        guard let endTime = manifest.endTime else {
            preconditionFailure("Closing session manifest must have an endTime")
        }
        return endTime
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
            preconditionFailure("Closed session manifest must have an endTime")
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
            preconditionFailure("Archived session manifest must have an endTime")
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
        case .idle, .closing, .closed, .archived:
            break
        case .active:
            throw BookKeeperError.invalidPhase(expected: "idle, closed, or archived", actual: "active")
        }

        guard Self.isSafeSessionIdentifier(identifier) else {
            throw BookKeeperError.unsafePath(identifier)
        }

        let timestamp = Self.timestampString()
        let sessionId = "\(identifier)-\(timestamp)"
        let directory = baseDirectory.appendingPathComponent(sessionId)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let logPath = directory.appendingPathComponent("session.jsonl")
        FileManager.default.createFile(atPath: logPath.path, contents: nil)
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
        guard case .active(let session) = phase else {
            throw BookKeeperError.invalidPhase(expected: "active", actual: phaseName)
        }
        let closedManifest = session.manifest.closed(at: Date())
        try flushManifest(manifest: closedManifest, directory: session.directory)

        let closingSession = ClosingSession(
            sessionId: session.sessionId,
            directory: session.directory,
            manifest: closedManifest
        )
        phase = .closing(closingSession)
        session.logHandle.closeFile()

        // Close heist recording handle if still open (abandoned recording)
        if case .recording(let abandonedRecording) = session.heistRecording {
            abandonedRecording.fileHandle.closeFile()
        }

        // If compressLog throws, phase stays .closing — session data is
        // preserved and a fresh beginSession is still allowed.
        let compressedPath = try await compressLog(in: session.directory)

        phase = .closed(ClosedSession(
            sessionId: session.sessionId,
            directory: session.directory,
            compressedLogPath: compressedPath,
            manifest: closedManifest
        ))
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
        FileManager.default.createFile(atPath: heistPath.path, contents: nil)
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
        var recordedHeistId: String?
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
        heistId: String,
        targetCapture: AccessibilityTrace.Capture?
    ) -> (element: HeistElement, capture: AccessibilityTrace.Capture)? {
        guard let targetCapture else { return nil }
        let elementsByHeistId = targetCapture.interface.elements.reduce(
            into: [String: HeistElement]()
        ) { partialResult, element in
            partialResult[element.heistId] = element
        }
        guard let element = elementsByHeistId[heistId] else { return nil }
        return (element, targetCapture)
    }

    private func buildRecordedMetadata(
        heistId: String?,
        frame: RecordedFrame?,
        coordinateOnly: Bool?,
        actionResult: ActionResult?,
        expectation: ExpectationResult?
    ) -> RecordedMetadata? {
        let accessibilityTrace = actionResult?.accessibilityTrace
        let accessibilityDelta = actionResult?.effectiveAccessibilityDelta
        guard heistId != nil ||
            frame != nil ||
            coordinateOnly != nil ||
            accessibilityTrace != nil ||
            accessibilityDelta != nil ||
            expectation != nil else {
            return nil
        }
        return RecordedMetadata(
            heistId: heistId,
            frame: frame,
            coordinateOnly: coordinateOnly,
            accessibilityTrace: accessibilityTrace,
            accessibilityDelta: accessibilityDelta,
            expectation: expectation
        )
    }

    // MARK: - Heist File I/O

    static func writeHeist(_ script: HeistPlayback, to path: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(script)
        try data.write(to: path, options: .atomic)
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

    private func flushManifest(manifest: SessionManifest, directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        let manifestPath = directory.appendingPathComponent("manifest.json")
        try data.write(to: manifestPath, options: .atomic)
    }

    private func sessionLogSnapshot(manifest: SessionManifest, directory: URL) throws -> SessionLogSnapshot {
        let projection = try sessionLogProjection(in: directory)
        return SessionLogSnapshot(manifest: manifest, counts: projection.counts, artifacts: projection.artifacts)
    }

    private func sessionLogSnapshot(manifest: SessionManifest, archivePath: URL) throws -> SessionLogSnapshot {
        let projection = try sessionLogProjection(inArchive: archivePath)
        return SessionLogSnapshot(manifest: manifest, counts: projection.counts, artifacts: projection.artifacts)
    }
}
