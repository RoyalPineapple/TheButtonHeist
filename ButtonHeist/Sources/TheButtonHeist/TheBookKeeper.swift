import Foundation
import TheScore

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
public struct HeistRecording: Sendable {
    public let app: String
    public let startTime: Date
    public var steps: [HeistEvidence]
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
        session.heistRecording = HeistRecording(
            app: app,
            startTime: Date(),
            steps: [],
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
        guard !recording.steps.isEmpty else {
            throw BookKeeperError.noStepsRecorded
        }
        let script = HeistPlayback(
            recorded: recording.startTime,
            app: recording.app,
            steps: recording.steps
        )
        session.heistRecording = nil
        phase = .active(session)
        return script
    }

    /// Update the cached interface snapshot for heist recording.
    public func updateInterfaceCache(_ elements: [HeistElement]) {
        guard case .active(var session) = phase,
              var recording = session.heistRecording else { return }
        recording.interfaceCache = Dictionary(
            elements.map { ($0.heistId, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        session.heistRecording = recording
        phase = .active(session)
    }

    /// Commands that should not appear in heist playbacks.
    private static let excludedHeistCommands: Set<String> = [
        "help", "status", "quit", "exit",
        "list_devices", "get_interface", "get_screen",
        "get_session_state", "connect", "list_targets",
        "get_session_log", "archive_session",
        "start_recording", "stop_recording",
        "run_batch",
        "start_heist", "stop_heist", "play_heist",
    ]

    /// Record a successfully executed command for heist playback.
    /// Only records commands that succeeded — failed actions are skipped.
    public func recordHeistEvidence(
        command: String,
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
        var step = buildStep(
            command: command,
            args: args,
            cache: allElements,
            interfaceCache: recording.interfaceCache
        )

        if let response, let actionResult = response.actionResult {
            let expect = generateExpectation(
                actionResult: actionResult,
                args: args,
                interfaceCache: recording.interfaceCache,
                allElements: allElements
            )
            if let expect {
                step = HeistEvidence(
                    command: step.command,
                    target: step.target,
                    arguments: step.arguments.merging(
                        ["expect": expect],
                        uniquingKeysWith: { _, new in new }
                    ),
                    recorded: step.recorded
                )
            }
        }

        recording.steps.append(step)
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
        var metadata: RecordedMetadata?

        if let heistId, let element = interfaceCache[heistId] {
            target = buildMinimalMatcher(element: element, allElements: cache)
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

    /// UUID pattern — identifiers containing UUIDs are runtime-generated and not stable.
    private static let uuidPattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
            )
        } catch {
            fatalError("Invalid UUID regex pattern: \(error)")
        }
    }()

    /// Check whether an identifier is stable (developer-assigned) vs runtime-generated (contains UUID).
    private func isStableIdentifier(_ identifier: String) -> Bool {
        let range = NSRange(identifier.startIndex..., in: identifier)
        return Self.uuidPattern.firstMatch(in: identifier, range: range) == nil
    }

    /// Build the smallest ElementMatcher that uniquely identifies the element
    /// among all currently visible elements. Uses only identity fields —
    /// never value (mutable state) or state traits (selected, notEnabled, etc.).
    /// Skips identifiers that contain UUIDs (runtime-generated, not stable across sessions).
    public func buildMinimalMatcher(
        element: HeistElement,
        allElements: [HeistElement]
    ) -> ElementMatcher {
        let traits = identityTraits(element.traits)
        let stableIdentifier = element.identifier.flatMap { isStableIdentifier($0) ? $0 : nil }

        if let stableIdentifier {
            let candidate = ElementMatcher(identifier: stableIdentifier)
            if uniquelyMatches(candidate, element: element, in: allElements) {
                return candidate
            }
        }

        if let elementLabel = element.label {
            let candidate = ElementMatcher(label: elementLabel, traits: traits)
            if uniquelyMatches(candidate, element: element, in: allElements) {
                return candidate
            }

            if let stableIdentifier {
                let candidate = ElementMatcher(
                    label: elementLabel, identifier: stableIdentifier, traits: traits
                )
                if uniquelyMatches(candidate, element: element, in: allElements) {
                    return candidate
                }
            }
        }

        return ElementMatcher(
            label: element.label,
            identifier: stableIdentifier,
            traits: traits
        )
    }

    /// Build a matcher for expectations — starts from identity, enriches with
    /// notable state traits and value when present.
    public func buildExpectationMatcher(
        element: HeistElement,
        allElements: [HeistElement]
    ) -> ElementMatcher {
        let identity = buildMinimalMatcher(element: element, allElements: allElements)
        let elementStateTraits = element.traits.filter { Self.stateTraits.contains($0) }
        let notableStateTraits = elementStateTraits.isEmpty ? nil : elementStateTraits
        let notableValue = element.value

        if notableStateTraits == nil && notableValue == nil {
            return identity
        }

        let mergedTraits: [HeistTrait]?
        if let identityTraits = identity.traits, let notable = notableStateTraits {
            mergedTraits = identityTraits + notable
        } else {
            mergedTraits = identity.traits ?? notableStateTraits
        }

        return ElementMatcher(
            label: identity.label,
            identifier: identity.identifier,
            value: notableValue,
            traits: mergedTraits
        )
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

    // MARK: - Expectation Generation

    private static let insertionRemovalCap = 5

    private static let propertyPriority: [ElementProperty] = [
        .value, .label, .traits, .hint, .actions,
    ]

    func generateExpectation(
        actionResult: ActionResult,
        args: [String: Any],
        interfaceCache: [String: HeistElement],
        allElements: [HeistElement]
    ) -> HeistValue? {
        guard let delta = actionResult.interfaceDelta else { return nil }

        var expectations: [HeistValue] = []

        switch delta.kind {
        case .screenChanged:
            expectations.append(.string("screen_changed"))

        case .elementsChanged:
            if let propertyExpect = buildPropertyExpectation(
                delta: delta, args: args, interfaceCache: interfaceCache
            ) {
                expectations.append(propertyExpect)
            }

            if let added = delta.added {
                let postActionElements = allElements + added
                for element in added.prefix(Self.insertionRemovalCap) {
                    let matcher = buildExpectationMatcher(
                        element: element, allElements: postActionElements
                    )
                    expectations.append(matcherExpectation(key: "elementAppeared", matcher: matcher))
                }
            }

            if let removed = delta.removed {
                let preActionElements = Array(interfaceCache.values)
                for heistId in removed.prefix(Self.insertionRemovalCap) {
                    guard let element = interfaceCache[heistId] else { continue }
                    let matcher = buildExpectationMatcher(
                        element: element, allElements: preActionElements
                    )
                    expectations.append(matcherExpectation(key: "elementDisappeared", matcher: matcher))
                }
            }

            if expectations.isEmpty {
                expectations.append(.string("elements_changed"))
            }

        case .noChange:
            return nil
        }

        guard !expectations.isEmpty else { return nil }
        return expectations.count == 1 ? expectations[0] : .array(expectations)
    }

    private func buildPropertyExpectation(
        delta: InterfaceDelta,
        args: [String: Any],
        interfaceCache: [String: HeistElement]
    ) -> HeistValue? {
        guard let updates = delta.updated, !updates.isEmpty else { return nil }

        let targetHeistId = args["heistId"] as? String
        let targetUpdate: ElementUpdate?
        if let targetHeistId {
            targetUpdate = updates.first { $0.heistId == targetHeistId }
        } else {
            targetUpdate = updates.first { update in
                update.changes.contains { !$0.property.isGeometry }
            }
        }

        guard let update = targetUpdate else { return nil }

        let semanticChanges = update.changes.filter { !$0.property.isGeometry }
        for priority in Self.propertyPriority {
            if let change = semanticChanges.first(where: { $0.property == priority }) {
                var expectDict: [String: HeistValue] = [
                    "property": .string(change.property.rawValue),
                ]
                if let newValue = change.new {
                    expectDict["newValue"] = .string(newValue)
                }
                return .object(["elementUpdated": .object(expectDict)])
            }
        }

        return nil
    }

    private func matcherExpectation(key: String, matcher: ElementMatcher) -> HeistValue {
        var matcherDict: [String: HeistValue] = [:]
        if let label = matcher.label { matcherDict["label"] = .string(label) }
        if let matcherIdentifier = matcher.identifier { matcherDict["identifier"] = .string(matcherIdentifier) }
        if let matcherValue = matcher.value { matcherDict["value"] = .string(matcherValue) }
        if let traits = matcher.traits {
            matcherDict["traits"] = .array(traits.map { .string($0.rawValue) })
        }
        return .object([key: .object(matcherDict)])
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
