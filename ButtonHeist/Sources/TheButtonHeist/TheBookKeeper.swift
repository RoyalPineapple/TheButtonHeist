import Foundation
import os.log
import TheScore

private let logger = Logger(subsystem: "com.buttonheist.bookkeeper", category: "heist")

// MARK: - Session Phase State Machine

@ButtonHeistActor
public enum SessionPhase: Sendable {
    case idle
    case active(ActiveSession)
    case closing(ClosingSession)
    case closed(ClosedSession)
    case archived(ArchivedSession)
}

@ButtonHeistActor
public struct ActiveSession: Sendable {
    public let sessionId: String
    public let directory: URL
    public let logHandle: FileHandle
    public var manifest: SessionManifest
    public let startTime: Date
    public var nextSequenceNumber: Int

    // Heist recording state (nil when not recording a heist)
    public var heistRecording: HeistRecording?
}

@ButtonHeistActor
public struct HeistRecording: @unchecked Sendable {
    public let app: String
    public let startTime: Date
    public var evidenceCount: Int
    /// Append-only file handle for durable evidence storage.
    /// Each HeistEvidence is written as a JSON line as it's recorded.
    /// FileHandle is not Sendable, but access is isolated to @ButtonHeistActor.
    public let fileHandle: FileHandle
    public let filePath: URL
    /// Cached interface snapshot from the most recent get_interface response.
    /// Used to look up heistId → element properties for matcher construction.
    public var interfaceCache: [String: HeistElement]
}

@ButtonHeistActor
public struct ClosingSession: Sendable {
    public let sessionId: String
    public let directory: URL
    public var manifest: SessionManifest
    public let startTime: Date
    public let endTime: Date
}

@ButtonHeistActor
public struct ClosedSession: Sendable {
    public let sessionId: String
    public let directory: URL
    public let compressedLogPath: URL
    public let manifest: SessionManifest
    public let startTime: Date
    public let endTime: Date
}

@ButtonHeistActor
public struct ArchivedSession: Sendable {
    public let archivePath: URL
    public let manifest: SessionManifest
    public let startTime: Date
    public let endTime: Date
}

// MARK: - BookKeeper Errors

public enum BookKeeperError: Error, LocalizedError {
    case invalidPhase(expected: String, actual: String)
    case unsafePath(String)
    case base64DecodingFailed
    case compressionFailed(String)
    case archiveFailed(String)
    case noStepsRecorded
    case notRecordingHeist

    public var errorDescription: String? {
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

@ButtonHeistActor
public final class TheBookKeeper {

    public private(set) var phase: SessionPhase = .idle
    private let baseDirectory: URL

    public init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory ?? Self.resolveBaseDirectory()
    }

    public var manifest: SessionManifest? {
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

    // MARK: - Recovery

    /// A session that was recovered from an abandoned state.
    public struct RecoveredSession: Sendable {
        public let sessionId: String
        public let directory: URL
        /// Number of heist evidence entries found, or nil if no heist was in progress.
        public let heistEvidenceCount: Int?
        /// Path to the heist evidence file, if one exists.
        public let heistFilePath: URL?
    }

    /// Scan for abandoned sessions and recover them.
    /// An abandoned session has `session.jsonl` (uncompressed) — meaning it was
    /// never properly closed. Recovery: write a recovery manifest, compress the log.
    /// Abandoned heist evidence (heist.jsonl) is preserved and surfaced in the result.
    @discardableResult
    public func recoverAbandonedSessions() -> [RecoveredSession] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: baseDirectory.path) else { return [] }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var recovered: [RecoveredSession] = []
        for directoryURL in contents {
            guard (try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                continue
            }
            let rawLog = directoryURL.appendingPathComponent("session.jsonl")
            let compressedLog = directoryURL.appendingPathComponent("session.jsonl.gz")

            // Abandoned = has raw log but no compressed log
            let hasRawLog = fileManager.fileExists(atPath: rawLog.path)
            let hasCompressedLog = fileManager.fileExists(atPath: compressedLog.path)
            guard hasRawLog, !hasCompressedLog else { continue }

            let sessionId = directoryURL.lastPathComponent
            let heistInfo = recoverSession(directory: directoryURL, sessionId: sessionId)
            recovered.append(RecoveredSession(
                sessionId: sessionId,
                directory: directoryURL,
                heistEvidenceCount: heistInfo.evidenceCount,
                heistFilePath: heistInfo.filePath
            ))
        }
        return recovered
    }

    private func recoverSession(
        directory: URL,
        sessionId: String
    ) -> (evidenceCount: Int?, filePath: URL?) {
        let fileManager = FileManager.default
        let manifestPath = directory.appendingPathComponent("manifest.json")

        // Read existing manifest or create a minimal one
        var manifest: SessionManifest
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        if let manifestData = try? Data(contentsOf: manifestPath),
           let decoded = try? jsonDecoder.decode(SessionManifest.self, from: manifestData) {
            manifest = decoded
        } else {
            manifest = SessionManifest(sessionId: sessionId, startTime: Date())
        }

        // Mark as recovered with an endTime if missing
        if manifest.endTime == nil {
            manifest.endTime = Date()
        }

        // Write updated manifest
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let manifestData = try? encoder.encode(manifest) {
            try? manifestData.write(to: manifestPath, options: .atomic)
        }

        // Compress the raw log
        let rawLog = directory.appendingPathComponent("session.jsonl")
        let gzipProcess = Process()
        gzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        gzipProcess.arguments = [rawLog.path]
        gzipProcess.standardOutput = FileHandle.nullDevice
        gzipProcess.standardError = FileHandle.nullDevice
        try? gzipProcess.run()
        gzipProcess.waitUntilExit()

        // Check for abandoned heist evidence
        let heistLog = directory.appendingPathComponent("heist.jsonl")
        var heistEvidenceCount: Int?
        var heistFilePath: URL?
        if fileManager.fileExists(atPath: heistLog.path),
           let heistData = try? Data(contentsOf: heistLog),
           !heistData.isEmpty {
            let lineCount = heistData.reduce(0) { count, byte in byte == 0x0A ? count + 1 : count }
            heistEvidenceCount = lineCount
            heistFilePath = heistLog
            logger.warning(
                "Abandoned heist in session \(sessionId) — \(lineCount) evidence entries preserved at \(heistLog.path)"
            )
        }

        logger.info("Recovered abandoned session: \(sessionId)")
        return (heistEvidenceCount, heistFilePath)
    }

    // MARK: - Lifecycle

    public func beginSession(identifier: String) throws {
        switch phase {
        case .idle, .closing, .closed, .archived:
            break
        case .active:
            throw BookKeeperError.invalidPhase(expected: "idle, closed, or archived", actual: "active")
        }

        guard !identifier.contains("/"), !identifier.contains("..") else {
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

    public func closeSession() async throws {
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
        session.heistRecording?.fileHandle.closeFile()

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

    public func archiveSession(deleteSource: Bool = false) async throws -> (URL, SessionManifest) {
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

    public func logCommand(
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

    public func logResponse(
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

    public func writeScreenshot(
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

    public func writeRecording(
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

    public func writeToPath(_ data: Data, outputPath: String) throws -> URL {
        guard let resolvedURL = validateOutputPath(outputPath) else {
            throw BookKeeperError.unsafePath(outputPath)
        }
        try data.write(to: resolvedURL)
        return resolvedURL
    }

    // MARK: - Heist Recording

    public var isRecordingHeist: Bool {
        guard case .active(let session) = phase else { return false }
        return session.heistRecording != nil
    }

    public func startHeistRecording(app: String) throws {
        guard case .active(var session) = phase else {
            throw BookKeeperError.invalidPhase(expected: "active", actual: phaseName)
        }
        guard session.heistRecording == nil else {
            throw BookKeeperError.invalidPhase(expected: "not recording heist", actual: "recording heist")
        }

        let heistPath = session.directory.appendingPathComponent("heist.jsonl")
        FileManager.default.createFile(atPath: heistPath.path, contents: nil)
        let heistHandle = try FileHandle(forWritingTo: heistPath)

        session.heistRecording = HeistRecording(
            app: app,
            startTime: Date(),
            evidenceCount: 0,
            fileHandle: heistHandle,
            filePath: heistPath,
            interfaceCache: [:]
        )
        phase = .active(session)
    }

    public func stopHeistRecording() throws -> HeistPlayback {
        guard case .active(var session) = phase else {
            throw BookKeeperError.invalidPhase(expected: "active", actual: phaseName)
        }
        guard let recording = session.heistRecording else {
            throw BookKeeperError.notRecordingHeist
        }
        guard recording.evidenceCount > 0 else {
            recording.fileHandle.closeFile()
            session.heistRecording = nil
            phase = .active(session)
            throw BookKeeperError.noStepsRecorded
        }

        recording.fileHandle.closeFile()

        // Read evidence back from the durable file
        let steps = try readEvidenceFromFile(recording.filePath)

        let heist = HeistPlayback(
            recorded: recording.startTime,
            app: recording.app,
            steps: steps
        )
        session.heistRecording = nil
        phase = .active(session)
        return heist
    }

    /// Read HeistEvidence entries from a JSONL file.
    private func readEvidenceFromFile(_ path: URL) throws -> [HeistEvidence] {
        let data = try Data(contentsOf: path)
        let lines = data.split(separator: 0x0A)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try lines.map { lineData in
            try decoder.decode(HeistEvidence.self, from: Data(lineData))
        }
    }

    /// Update the cached interface snapshot for heist recording.
    public func updateInterfaceCache(_ elements: [HeistElement]) {
        guard case .active(var session) = phase,
              var recording = session.heistRecording else { return }
        // Merge rather than replace — after a screen change, the activated element
        // from the old screen must remain in the cache for the recording step that
        // triggered the transition. New elements take priority on heistId collision.
        for element in elements {
            recording.interfaceCache[element.heistId] = element
        }
        session.heistRecording = recording
        phase = .active(session)
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
    public func recordHeistEvidence(
        command: TheFence.Command,
        args: [String: Any],
        response: FenceResponse? = nil,
        interfaceElements: [HeistElement]? = nil
    ) {
        guard case .active(var session) = phase,
              var recording = session.heistRecording else { return }
        guard !Self.excludedHeistCommands.contains(command) else { return }

        // Skip failed actions — only record successful outcomes
        if let response {
            if case .error = response { return }
            if let actionResult = response.actionResult, !actionResult.success { return }
        }

        let allElements = interfaceElements ?? Array(recording.interfaceCache.values)
        let step = buildStep(
            command: command.rawValue,
            args: args,
            cache: allElements,
            interfaceCache: recording.interfaceCache
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
        recording.evidenceCount += 1
        session.heistRecording = recording
        phase = .active(session)
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
        interfaceCache: [String: HeistElement]
    ) -> HeistEvidence {
        let heistId = args["heistId"] as? String
        let hasMatcherFields = Self.elementKeys.subtracting(["heistId"]).contains { key in
            args[key] != nil
        }

        var target: ElementMatcher?
        var ordinal: Int?
        var metadata: RecordedMetadata?

        if let heistId, let element = interfaceCache[heistId] {
            let result = buildMinimalMatcher(element: element, allElements: cache)
            target = result.matcher
            ordinal = result.ordinal
            metadata = RecordedMetadata(
                heistId: heistId,
                frame: RecordedFrame(
                    x: element.frameX, y: element.frameY,
                    width: element.frameWidth, height: element.frameHeight
                )
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
                metadata = RecordedMetadata(heistId: heistId)
            }
        } else if hasCoordinateArgs(args) {
            metadata = RecordedMetadata(coordinateOnly: true)
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
            recorded: metadata
        )
    }

    private func hasCoordinateArgs(_ args: [String: Any]) -> Bool {
        args["x"] != nil || args["startX"] != nil || args["centerX"] != nil || args["points"] != nil
    }

    // MARK: - Minimal Matcher

    /// Traits that represent mutable state, not element identity.
    static let stateTraits: Set<HeistTrait> = [
        .selected, .notEnabled, .isEditing, .inactive, .visited,
    ]

    private func identityTraits(_ traits: [HeistTrait]) -> [HeistTrait]? {
        let filtered = traits.filter { !Self.stateTraits.contains($0) }
        return filtered.isEmpty ? nil : filtered
    }

    /// Build the smallest ElementMatcher that uniquely identifies the element
    /// among all currently visible elements. Uses only identity fields —
    /// never value (mutable state) or state traits (selected, notEnabled, etc.).
    /// Skips identifiers that contain UUIDs (runtime-generated, not stable across sessions).
    ///
    /// When no combination of fields yields a unique match, returns the best
    /// matcher alongside the element's 0-based ordinal among all matches
    /// (traversal order in the allElements array).
    public func buildMinimalMatcher(
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

    public static func writeHeist(_ script: HeistPlayback, to path: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(script)
        try data.write(to: path, options: .atomic)
    }

    public static func readHeist(from path: URL) throws -> HeistPlayback {
        let data = try Data(contentsOf: path)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HeistPlayback.self, from: data)
    }

    // MARK: - Path Safety

    public func validateOutputPath(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        let components = path.split(separator: "/")
        guard !components.contains("..") else { return nil }
        return URL(fileURLWithPath: path).standardized
    }

    // MARK: - Private Helpers

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
