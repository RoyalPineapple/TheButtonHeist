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
/// recording is in progress, or one is and carries its file handle / counters.
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
    var manifest: SessionManifest
    let startTime: Date
    var nextSequenceNumber: Int
    var heistRecording: HeistRecordingPhase = .idle
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
    var manifest: SessionManifest
    let startTime: Date
    let endTime: Date
}

struct ClosedSession: Sendable {
    let sessionId: String
    let directory: URL
    let compressedLogPath: URL
    let manifest: SessionManifest
    let startTime: Date
    let endTime: Date
}

struct ArchivedSession: Sendable {
    let archivePath: URL
    let manifest: SessionManifest
    let startTime: Date
    let endTime: Date
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

        let headerEntry: [String: Any] = [
            "type": "header",
            "formatVersion": SessionFormatVersion.current,
            "sessionId": sessionId,
        ]
        try appendLogLine(headerEntry, to: logHandle)

        let startTime = Date()
        let manifest = SessionManifest(sessionId: sessionId, startTime: startTime)
        phase = .active(ActiveSession(
            sessionId: sessionId,
            directory: directory,
            logHandle: logHandle,
            manifest: manifest,
            startTime: startTime,
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
        guard case .active(var session) = phase else {
            throw BookKeeperError.invalidPhase(expected: "active", actual: phaseName)
        }
        let endTime = Date()
        session.manifest.endTime = endTime
        try flushManifest(session: session)

        let closingSession = ClosingSession(
            sessionId: session.sessionId,
            directory: session.directory,
            manifest: session.manifest,
            startTime: session.startTime,
            endTime: endTime
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
            manifest: session.manifest,
            startTime: session.startTime,
            endTime: endTime
        ))
    }

    func archiveSession(deleteSource: Bool = false) async throws -> (URL, SessionManifest) {
        guard case .closed(let session) = phase else {
            throw BookKeeperError.invalidPhase(expected: "closed", actual: phaseName)
        }

        let archivePath = try await createArchive(session: session)
        let manifest = session.manifest

        if deleteSource {
            try FileManager.default.removeItem(at: session.directory)
        }

        phase = .archived(ArchivedSession(
            archivePath: archivePath,
            manifest: manifest,
            startTime: session.startTime,
            endTime: session.endTime
        ))

        return (archivePath, manifest)
    }

    // MARK: - Logging

    func logCommand(
        requestId: String,
        command: TheFence.Command,
        arguments: [String: Any]
    ) throws {
        guard case .active(var session) = phase else { return }
        let entry = buildCommandLogEntry(
            requestId: requestId,
            command: command,
            arguments: arguments
        )
        try appendLogLine(entry, to: session.logHandle)
        session.manifest.commandCount += 1
        phase = .active(session)
    }

    func logResponse(
        requestId: String,
        status: ResponseStatus,
        durationMilliseconds: Int,
        artifact: String? = nil,
        error: String? = nil
    ) throws {
        guard case .active(var session) = phase else { return }
        let entry = buildResponseLogEntry(
            requestId: requestId,
            status: status,
            durationMilliseconds: durationMilliseconds,
            artifact: artifact,
            error: error
        )
        try appendLogLine(entry, to: session.logHandle)
        if status == .error {
            session.manifest.errorCount += 1
        }
        phase = .active(session)
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
        session.manifest.artifacts.append(entry)
        try flushManifest(session: session)
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
        session.manifest.artifacts.append(entry)
        try flushManifest(session: session)
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
    ///   `writeToPath` (no manifest update).
    /// - No `outputPath`, session active → write via `writeScreenshot` into
    ///   the session's artifact directory and append to the session manifest.
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
    ///   - interfaceCache: Snapshot of currently visible elements keyed by
    ///     heistId. The recorder uses this to resolve `heistId` arguments to
    ///     stable matchers. Caller is responsible for supplying the cache —
    ///     TheBookKeeper does not maintain its own copy.
    func recordHeistEvidence(
        command: TheFence.Command,
        args: [String: Any],
        actionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil,
        interfaceCache: [String: HeistElement]
    ) {
        guard case .active(let session) = phase,
              case .recording(let recording) = session.heistRecording else { return }
        guard !Self.excludedHeistCommands.contains(command) else { return }
        guard actionResult?.success != false else { return }
        guard expectation?.met != false else { return }

        let step = buildStep(
            command: command.rawValue,
            args: args,
            cache: Array(interfaceCache.values),
            interfaceCache: interfaceCache,
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
            logger.error("Failed to encode heist evidence for \(command.rawValue): \(error.localizedDescription)")
            return
        }
    }

    // MARK: - Heist Step Construction

    private static let elementKeys: Set<String> = [
        "heistId", "label", "identifier", "value", "traits", "excludeTraits",
    ]

    private static let stripKeys: Set<String> = [
        "command", "heistId", "label", "identifier", "value", "traits", "excludeTraits",
        "pngData", "videoData",
    ]

    private func buildStep(
        command: String,
        args: [String: Any],
        cache: [HeistElement],
        interfaceCache: [String: HeistElement],
        actionResult: ActionResult?,
        expectation: ExpectationResult?
    ) -> HeistEvidence {
        let heistId = args["heistId"] as? String
        let hasMatcherFields = Self.elementKeys.subtracting(["heistId"]).contains { key in
            args[key] != nil
        }

        var target: ElementMatcher?
        var ordinal: Int?
        var recordedHeistId: String?
        var recordedFrame: RecordedFrame?
        var coordinateOnly: Bool?

        if let heistId, let source = matcherSource(
            heistId: heistId,
            trace: actionResult?.accessibilityTrace,
            fallbackCache: interfaceCache,
            fallbackElements: cache
        ) {
            let result = buildMinimalMatcher(element: source.element, allElements: source.elements)
            target = result.matcher
            ordinal = result.ordinal
            recordedHeistId = heistId
            recordedFrame = RecordedFrame(
                x: source.element.frameX, y: source.element.frameY,
                width: source.element.frameWidth, height: source.element.frameHeight
            )
        } else if hasMatcherFields {
            target = ElementMatcher(
                label: args["label"] as? String,
                identifier: args["identifier"] as? String,
                value: args["value"] as? String,
                traits: (args["traits"] as? [String])?.compactMap { HeistTrait(rawValue: $0) },
                excludeTraits: (args["excludeTraits"] as? [String])?.compactMap { HeistTrait(rawValue: $0) }
            ).nonEmpty
            if let heistId {
                recordedHeistId = heistId
            }
        } else if hasCoordinateArgs(args) {
            coordinateOnly = true
        }

        var arguments: [String: HeistValue] = [:]
        for (key, argValue) in args where !Self.stripKeys.contains(key) {
            if let playbackValue = HeistValue.from(argValue) {
                arguments[key] = playbackValue
            }
        }

        return HeistEvidence(
            command: command,
            target: target,
            ordinal: ordinal,
            arguments: arguments,
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
        trace: AccessibilityTrace?,
        fallbackCache: [String: HeistElement],
        fallbackElements: [HeistElement]
    ) -> (element: HeistElement, elements: [HeistElement])? {
        if let trace {
            for capture in trace.captures {
                let elements = capture.interface.elements
                if let element = elements.first(where: { $0.heistId == heistId }) {
                    return (element, elements)
                }
            }
        }
        guard let element = fallbackCache[heistId] else { return nil }
        return (element, fallbackElements)
    }

    private func buildRecordedMetadata(
        heistId: String?,
        frame: RecordedFrame?,
        coordinateOnly: Bool?,
        actionResult: ActionResult?,
        expectation: ExpectationResult?
    ) -> RecordedMetadata? {
        let accessibilityTrace = actionResult?.accessibilityTrace
        let accessibilityDelta = actionResult?.accessibilityDelta
        guard heistId != nil || frame != nil || coordinateOnly != nil || accessibilityTrace != nil || accessibilityDelta != nil || expectation != nil else {
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

    private func hasCoordinateArgs(_ args: [String: Any]) -> Bool {
        args["x"] != nil || args["startX"] != nil || args["centerX"] != nil || args["points"] != nil
    }

    // MARK: - Minimal Matcher

    private func identityTraits(_ traits: [HeistTrait]) -> [HeistTrait]? {
        let filtered = traits.filter { !AccessibilityPolicy.transientTraits.contains($0) }
        return filtered.isEmpty ? nil : filtered
    }

    /// Smallest unique matcher among `allElements`, falling back to a non-unique
    /// matcher + ordinal when no field combination distinguishes the element.
    func buildMinimalMatcher(
        element: HeistElement,
        allElements: [HeistElement]
    ) -> (matcher: ElementMatcher, ordinal: Int?) {
        let traits = identityTraits(element.traits)
        let stableIdentifier = element.identifier.flatMap { isStableIdentifier($0) ? $0 : nil }

        if let stableIdentifier {
            let candidate = ElementMatcher(identifier: stableIdentifier)
            if uniquelyMatches(candidate, element: element, in: allElements) {
                return (candidate, nil)
            }
        }

        if let elementLabel = element.label {
            let candidate = ElementMatcher(label: elementLabel, traits: traits)
            if uniquelyMatches(candidate, element: element, in: allElements) {
                return (candidate, nil)
            }

            if let stableIdentifier {
                let candidate = ElementMatcher(
                    label: elementLabel, identifier: stableIdentifier, traits: traits
                )
                if uniquelyMatches(candidate, element: element, in: allElements) {
                    return (candidate, nil)
                }
            }
        }

        // No unique matcher found — fall back to best-effort matcher with ordinal
        let bestMatcher = ElementMatcher(
            label: element.label,
            identifier: stableIdentifier,
            traits: traits
        )
        let ordinal = ordinalOf(element, matching: bestMatcher, in: allElements)
        return (bestMatcher, ordinal)
    }

    private func uniquelyMatches(
        _ matcher: ElementMatcher,
        element: HeistElement,
        in allElements: [HeistElement]
    ) -> Bool {
        var matchCount = 0
        for candidate in allElements where candidate.matches(matcher) {
            matchCount += 1
            if matchCount > 1 { return false }
        }
        return matchCount == 1
    }

    /// Find the 0-based index of `element` among all elements matching `matcher`.
    /// Returns nil if the element is the only match (ordinal would be redundant).
    private func ordinalOf(
        _ element: HeistElement,
        matching matcher: ElementMatcher,
        in allElements: [HeistElement]
    ) -> Int? {
        var index = 0
        var found: Int?
        var totalMatches = 0
        for candidate in allElements where candidate.matches(matcher) {
            if candidate.heistId == element.heistId {
                found = index
            }
            index += 1
            totalMatches += 1
        }
        guard totalMatches > 1 else { return nil }
        return found
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

    private func flushManifest(session: ActiveSession) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session.manifest)
        let manifestPath = session.directory.appendingPathComponent("manifest.json")
        try data.write(to: manifestPath, options: .atomic)
    }
}
