import Foundation

import TheScore

private let redactedTokenLogValue = "<redacted>"

// MARK: - Typed Request Recording

private extension HeistValue {
    static func fenceObject(_ values: [FenceParameterKey: HeistValue]) -> HeistValue {
        .object(
            values.reduce(into: [String: HeistValue]()) { result, pair in
                result[pair.key.rawValue] = pair.value
            }
        )
    }

    static func encoded<T: Encodable>(_ value: T) -> HeistValue {
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(HeistValue.self, from: data)
        } catch {
            return .object([
                "type": .string("encoding_failed"),
                "error": .string(String(describing: error)),
            ])
        }
    }

    func sanitizedLogValue(maxStringLength: Int) -> HeistValue {
        switch self {
        case .string(let value):
            return .string(value.sanitizedLogValue(maxStringLength: maxStringLength))
        case .int(let value):
            return .int(value)
        case .double(let value):
            return .double(value)
        case .bool(let value):
            return .bool(value)
        case .array(let values):
            return .array(values.map { $0.sanitizedLogValue(maxStringLength: maxStringLength) })
        case .object(let values):
            return .object(values.mapValues { $0.sanitizedLogValue(maxStringLength: maxStringLength) })
        }
    }
}

private extension String {
    func sanitizedLogValue(maxStringLength: Int) -> String {
        if count > maxStringLength {
            return "<\(count) chars>"
        }
        return self
    }
}

private extension Dictionary where Key == String, Value == HeistValue {
    subscript(_ key: FenceParameterKey) -> HeistValue? {
        get { self[key.rawValue] }
        set { self[key.rawValue] = newValue }
    }

    mutating func set(_ key: String, _ value: String?) {
        guard let value else { return }
        self[key] = .string(value)
    }

    mutating func set(_ key: FenceParameterKey, _ value: String?) {
        set(key.rawValue, value)
    }

    mutating func set(_ key: String, _ value: Int?) {
        guard let value else { return }
        self[key] = .int(value)
    }

    mutating func set(_ key: FenceParameterKey, _ value: Int?) {
        set(key.rawValue, value)
    }

    mutating func set(_ key: String, _ value: Double?) {
        guard let value else { return }
        self[key] = .double(value)
    }

    mutating func set(_ key: FenceParameterKey, _ value: Double?) {
        set(key.rawValue, value)
    }

    mutating func set(_ key: String, _ value: Bool?) {
        guard let value else { return }
        self[key] = .bool(value)
    }

    mutating func set(_ key: FenceParameterKey, _ value: Bool?) {
        set(key.rawValue, value)
    }

    mutating func set<E: RawRepresentable>(_ key: String, _ value: E?) where E.RawValue == String {
        guard let value else { return }
        self[key] = .string(value.rawValue)
    }

    mutating func set<E: RawRepresentable>(_ key: FenceParameterKey, _ value: E?) where E.RawValue == String {
        set(key.rawValue, value)
    }

    mutating func appendMatcher(_ matcher: ElementMatcher) {
        set(.heistId, matcher.heistId)
        set(.label, matcher.label)
        set(.identifier, matcher.identifier)
        set(.value, matcher.value)
        if let traits = matcher.traits {
            self[.traits] = .array(traits.map { .string($0.rawValue) })
        }
        if let excludeTraits = matcher.excludeTraits {
            self[.excludeTraits] = .array(excludeTraits.map { .string($0.rawValue) })
        }
    }

    mutating func appendTarget(_ target: ElementTarget?) {
        guard let target else { return }
        switch target {
        case .heistId(let heistId):
            self[.heistId] = .string(heistId)
        case .matcher(let matcher, let ordinal):
            appendMatcher(matcher)
            set(.ordinal, ordinal)
        }
    }

    mutating func appendTarget(_ target: ElementTarget?, includeTarget: Bool) {
        guard includeTarget else { return }
        appendTarget(target)
    }

    mutating func appendExpectation(_ expectation: ActionExpectation?, timeout: Double?) {
        if let expectation {
            self[.expect] = HeistValue.encoded(expectation)
        }
        set(.timeout, timeout)
    }
}

extension TheFence {
    struct CommandLogProjection {
        let requestId: String
        let command: Command
        let arguments: [String: HeistValue]
    }

    struct BatchStepLogProjection {
        let commandName: String
        let arguments: [String: HeistValue]

        var stepArguments: [String: HeistValue] {
            var values = arguments
            values[.command] = .string(commandName)
            return values
        }
    }

    struct HeistEvidenceProjection {
        let command: Command
        let arguments: [String: HeistValue]
        let elementTarget: ElementTarget?
        let coordinateOnly: Bool
    }
}

extension TheFence.ParsedRequest {
    var commandLogProjection: TheFence.CommandLogProjection {
        TheFence.CommandLogProjection(
            requestId: requestId,
            command: command,
            arguments: bookKeeperArguments(includeTarget: true)
        )
    }

    var heistEvidenceProjection: TheFence.HeistEvidenceProjection {
        TheFence.HeistEvidenceProjection(
            command: command,
            arguments: bookKeeperArguments(includeTarget: false),
            elementTarget: payload.bookKeeperElementTarget,
            coordinateOnly: payload.bookKeeperCoordinateOnly
        )
    }

    private func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments = payload.bookKeeperArguments(includeTarget: includeTarget)
        if command != .waitForChange {
            let timeout = expectationPayload.expectation == nil ? nil : expectationPayload.timeout
            arguments.appendExpectation(expectationPayload.expectation, timeout: timeout)
        }
        return arguments
    }
}

private extension TheFence.RequestPayload {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        switch self {
        case .none:
            return [:]
        case .getInterface(let request):
            return request.bookKeeperArguments
        case .screen(let request):
            var arguments: [String: HeistValue] = [:]
            arguments.set(.output, request.outputPath)
            arguments.set(.inlineData, request.inlineData ? true : nil)
            arguments.set(.includeInterface, request.includeInterface ? true : nil)
            return arguments
        case .artifact(let request):
            var arguments: [String: HeistValue] = [:]
            arguments.set(.output, request.outputPath)
            arguments.set(.inlineData, request.inlineData ? true : nil)
            arguments.set(.includeInteractionLog, request.includeInteractionLog ? true : nil)
            return arguments
        case .gesture(let payload):
            return payload.bookKeeperArguments(includeTarget: includeTarget)
        case .scroll(let payload):
            return payload.bookKeeperArguments(includeTarget: includeTarget)
        case .accessibility(let payload):
            return payload.bookKeeperArguments(includeTarget: includeTarget)
        case .rotor(let target):
            return target.bookKeeperArguments(includeTarget: includeTarget)
        case .typeText(let target):
            var arguments: [String: HeistValue] = [:]
            arguments.set(.text, target.text)
            arguments.appendTarget(target.elementTarget, includeTarget: includeTarget)
            return arguments
        case .editAction(let target):
            var arguments: [String: HeistValue] = [:]
            arguments.set(.action, target.action)
            return arguments
        case .setPasteboard(let target):
            var arguments: [String: HeistValue] = [:]
            arguments.set(.text, target.text)
            return arguments
        case .waitFor(let target):
            return target.bookKeeperArguments(includeTarget: includeTarget)
        case .waitForChange(let payload):
            var arguments: [String: HeistValue] = [:]
            arguments.appendExpectation(payload.expectation, timeout: payload.timeout)
            return arguments
        case .startRecording(let config):
            return config.bookKeeperArguments
        case .connect(let request):
            return request.bookKeeperArguments
        case .runBatch(let request):
            return request.bookKeeperArguments
        case .archiveSession(let request):
            var arguments: [String: HeistValue] = [:]
            arguments.set(.deleteSource, request.deleteSource ? true : nil)
            return arguments
        case .startHeist(let request):
            var arguments: [String: HeistValue] = [:]
            arguments.set(.app, request.app)
            arguments.set(.identifier, request.identifier)
            return arguments
        case .stopHeist(let request):
            var arguments: [String: HeistValue] = [:]
            arguments.set(.output, request.outputPath)
            return arguments
        case .playHeist(let request):
            var arguments: [String: HeistValue] = [:]
            arguments.set(.input, request.inputPath)
            return arguments
        }
    }

    var bookKeeperElementTarget: ElementTarget? {
        switch self {
        case .gesture(let payload):
            return payload.bookKeeperElementTarget
        case .scroll(let payload):
            return payload.bookKeeperElementTarget
        case .accessibility(let payload):
            return payload.bookKeeperElementTarget
        case .rotor(let target):
            return target.elementTarget
        case .typeText(let target):
            return target.elementTarget
        case .waitFor(let target):
            return target.elementTarget
        case .none, .getInterface, .screen, .artifact, .editAction, .setPasteboard,
             .waitForChange, .startRecording, .connect, .runBatch, .archiveSession,
             .startHeist, .stopHeist, .playHeist:
            return nil
        }
    }

    var bookKeeperCoordinateOnly: Bool {
        switch self {
        case .gesture(let payload):
            return payload.bookKeeperCoordinateOnly
        default:
            return false
        }
    }
}

private extension TheFence.GetInterfaceRequest {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        if detail != .summary {
            arguments.set(.detail, detail)
        }
        if let subtree = query.subtree {
            arguments[.subtree] = subtree.bookKeeperValue
        }
        if query.matcher.hasPredicates {
            arguments.appendMatcher(query.matcher)
        }
        if let elementIds = query.elementIds {
            arguments[.elements] = .array(elementIds.map { .string($0) })
        }
        return arguments
    }
}

private extension SubtreeSelector {
    var bookKeeperValue: HeistValue {
        var payload: [String: HeistValue] = [:]
        switch self {
        case .element(let matcher, let ordinal):
            var element: [String: HeistValue] = [:]
            element.appendMatcher(matcher)
            payload[.element] = .object(element)
            payload.set(.ordinal, ordinal)
        case .container(let matcher, let ordinal):
            payload[.container] = matcher.bookKeeperValue
            payload.set(.ordinal, ordinal)
        }
        return .object(payload)
    }
}

private extension ContainerMatcher {
    var bookKeeperValue: HeistValue {
        var payload: [String: HeistValue] = [:]
        payload.set(.stableId, stableId)
        payload.set(.type, type)
        payload.set(.label, label)
        payload.set(.value, value)
        payload.set(.identifier, identifier)
        payload.set(.isModalBoundary, isModalBoundary)
        return .object(payload)
    }
}

private extension TheFence.GesturePayload {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        switch self {
        case .oneFingerTap(let payload):
            return payload.target.bookKeeperArguments(includeTarget: includeTarget)
        case .longPress(let payload):
            return payload.target.bookKeeperArguments(includeTarget: includeTarget)
        case .swipe(let payload):
            return payload.target.bookKeeperArguments(includeTarget: includeTarget)
        case .drag(let payload):
            return payload.target.bookKeeperArguments(includeTarget: includeTarget)
        case .pinch(let payload):
            return payload.target.bookKeeperArguments(includeTarget: includeTarget)
        case .rotate(let payload):
            return payload.target.bookKeeperArguments(includeTarget: includeTarget)
        case .twoFingerTap(let payload):
            return payload.target.bookKeeperArguments(includeTarget: includeTarget)
        case .drawPath(let payload):
            return payload.target.bookKeeperArguments
        case .drawBezier(let payload):
            return payload.target.bookKeeperArguments
        }
    }

    var bookKeeperElementTarget: ElementTarget? {
        switch self {
        case .oneFingerTap(let payload):
            return payload.elementTarget
        case .longPress(let payload):
            return payload.elementTarget
        case .swipe(let payload):
            return payload.elementTarget
        case .drag(let payload):
            return payload.elementTarget
        case .pinch(let payload):
            return payload.elementTarget
        case .rotate(let payload):
            return payload.elementTarget
        case .twoFingerTap(let payload):
            return payload.elementTarget
        case .drawPath, .drawBezier:
            return nil
        }
    }

    var bookKeeperCoordinateOnly: Bool {
        switch self {
        case .oneFingerTap(let payload):
            return payload.elementTarget == nil && payload.target.point != nil
        case .longPress(let payload):
            return payload.elementTarget == nil && payload.target.point != nil
        case .swipe(let payload):
            return payload.elementTarget == nil
        case .drag(let payload):
            return payload.elementTarget == nil
        case .pinch(let payload):
            return payload.elementTarget == nil
        case .rotate(let payload):
            return payload.elementTarget == nil
        case .twoFingerTap(let payload):
            return payload.elementTarget == nil
        case .drawPath, .drawBezier:
            return true
        }
    }
}

private extension TouchTapTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.x, pointX)
        arguments.set(.y, pointY)
        arguments.appendTarget(elementTarget, includeTarget: includeTarget)
        return arguments
    }
}

private extension LongPressTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.x, pointX)
        arguments.set(.y, pointY)
        arguments.set(.duration, duration)
        arguments.appendTarget(elementTarget, includeTarget: includeTarget)
        return arguments
    }
}

private extension SwipeTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.direction, direction)
        arguments.set(.startX, startX)
        arguments.set(.startY, startY)
        arguments.set(.endX, endX)
        arguments.set(.endY, endY)
        arguments.set(.duration, duration)
        if let start {
            arguments[.start] = start.bookKeeperValue
        }
        if let end {
            arguments[.end] = end.bookKeeperValue
        }
        arguments.appendTarget(elementTarget, includeTarget: includeTarget)
        return arguments
    }
}

private extension DragTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.startX, startX)
        arguments.set(.startY, startY)
        arguments.set(.endX, endX)
        arguments.set(.endY, endY)
        arguments.set(.duration, duration)
        arguments.appendTarget(elementTarget, includeTarget: includeTarget)
        return arguments
    }
}

private extension PinchTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.centerX, centerX)
        arguments.set(.centerY, centerY)
        arguments.set(.scale, scale)
        arguments.set(.spread, spread)
        arguments.set(.duration, duration)
        arguments.appendTarget(elementTarget, includeTarget: includeTarget)
        return arguments
    }
}

private extension RotateTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.centerX, centerX)
        arguments.set(.centerY, centerY)
        arguments.set(.angle, angle)
        arguments.set(.radius, radius)
        arguments.set(.duration, duration)
        arguments.appendTarget(elementTarget, includeTarget: includeTarget)
        return arguments
    }
}

private extension TwoFingerTapTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.centerX, centerX)
        arguments.set(.centerY, centerY)
        arguments.set(.spread, spread)
        arguments.appendTarget(elementTarget, includeTarget: includeTarget)
        return arguments
    }
}

private extension UnitPoint {
    var bookKeeperValue: HeistValue {
        .fenceObject([
            .x: .double(x),
            .y: .double(y),
        ])
    }
}

private extension PathPoint {
    var bookKeeperValue: HeistValue {
        .fenceObject([
            .x: .double(x),
            .y: .double(y),
        ])
    }
}

private extension DrawPathTarget {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments[.points] = .array(points.map(\.bookKeeperValue))
        arguments.set(.duration, duration)
        arguments.set(.velocity, velocity)
        return arguments
    }
}

private extension BezierSegment {
    var bookKeeperValue: HeistValue {
        .fenceObject([
            .cp1X: .double(cp1X),
            .cp1Y: .double(cp1Y),
            .cp2X: .double(cp2X),
            .cp2Y: .double(cp2Y),
            .endX: .double(endX),
            .endY: .double(endY),
        ])
    }
}

private extension DrawBezierTarget {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.startX, startX)
        arguments.set(.startY, startY)
        arguments[.segments] = .array(segments.map(\.bookKeeperValue))
        arguments.set(.samplesPerSegment, samplesPerSegment)
        arguments.set(.duration, duration)
        arguments.set(.velocity, velocity)
        return arguments
    }
}

private extension TheFence.ScrollPayload {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        switch self {
        case .scroll(let target):
            return target.bookKeeperArguments(includeTarget: includeTarget)
        case .scrollToVisible(let target):
            var arguments: [String: HeistValue] = [:]
            arguments.appendTarget(target.elementTarget, includeTarget: includeTarget)
            return arguments
        case .elementSearch(let target):
            var arguments: [String: HeistValue] = [:]
            arguments.set(.direction, target.direction)
            arguments.appendTarget(target.elementTarget, includeTarget: includeTarget)
            return arguments
        case .scrollToEdge(let target):
            return target.bookKeeperArguments(includeTarget: includeTarget)
        }
    }

    var bookKeeperElementTarget: ElementTarget? {
        switch self {
        case .scroll(let target):
            return target.elementTarget
        case .scrollToVisible(let target):
            return target.elementTarget
        case .elementSearch(let target):
            return target.elementTarget
        case .scrollToEdge(let target):
            return target.elementTarget
        }
    }
}

private extension ScrollTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.direction, direction)
        arguments.appendTarget(elementTarget, includeTarget: includeTarget)
        return arguments
    }
}

private extension ScrollToEdgeTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.edge, edge)
        arguments.appendTarget(elementTarget, includeTarget: includeTarget)
        return arguments
    }
}

private extension TheFence.AccessibilityPayload {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        switch self {
        case .activate(let target, let actionName, let count):
            arguments.set(.action, actionName)
            arguments.set(.count, count.value)
            arguments.appendTarget(target, includeTarget: includeTarget)
        case .increment(let target, let count),
             .decrement(let target, let count):
            arguments.set(.count, count.value)
            arguments.appendTarget(target, includeTarget: includeTarget)
        case .performCustomAction(let target, let count):
            arguments.set(.action, target.actionName)
            arguments.set(.count, count.value)
            if includeTarget {
                if let elementTarget = target.elementTarget {
                    arguments.appendTarget(elementTarget)
                }
                if let containerTarget = target.containerTarget {
                    arguments["container"] = containerTarget.bookKeeperValue
                    arguments.set("ordinal", target.containerOrdinal)
                }
            }
        }
        return arguments
    }

    var bookKeeperElementTarget: ElementTarget? {
        switch self {
        case .activate(let target, _, _),
             .increment(let target, _),
             .decrement(let target, _):
            return target
        case .performCustomAction(let target, _):
            return target.elementTarget
        }
    }
}

private extension RotorTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.rotor, rotor)
        arguments.set(.rotorIndex, rotorIndex)
        arguments.set(.direction, direction)
        arguments.set(.currentHeistId, currentHeistId)
        arguments.set(.currentTextStartOffset, currentTextRange?.startOffset)
        arguments.set(.currentTextEndOffset, currentTextRange?.endOffset)
        arguments.appendTarget(elementTarget, includeTarget: includeTarget)
        return arguments
    }
}

private extension WaitForTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.absent, absent)
        arguments.set(.timeout, timeout)
        arguments.appendTarget(elementTarget, includeTarget: includeTarget)
        return arguments
    }
}

private extension RecordingConfig {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.fps, fps)
        arguments.set(.scale, scale)
        arguments.set(.inactivityTimeout, inactivityTimeout)
        arguments.set(.maxDuration, maxDuration)
        return arguments
    }
}

private extension TheFence.ConnectRequest {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.target, targetName)
        arguments.set(.device, device)
        if token != nil {
            arguments.set(.token, redactedTokenLogValue)
        }
        return arguments
    }
}

private extension TheFence.RunBatchRequest {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments[.steps] = .array(steps.map(\.bookKeeperValue))
        if policy != .stopOnError {
            arguments.set(.policy, policy)
        }
        return arguments
    }
}

extension TheFence.RunBatchStep {
    var batchStepLogProjection: TheFence.BatchStepLogProjection {
        switch self {
        case .planned(let step):
            return TheFence.BatchStepLogProjection(
                commandName: step.commandName,
                arguments: [
                    "index": .int(step.originalIndex),
                    "action": HeistValue.encoded(step.action),
                    "expect": HeistValue.encoded(step.expectation),
                    "deadline": HeistValue.encoded(step.deadline),
                ]
            )
        case .invalid(let commandName, let failure):
            return TheFence.BatchStepLogProjection(
                commandName: commandName,
                arguments: [
                    "decodeError": .string(failure.message),
                ]
            )
        }
    }
}

private extension TheFence.RunBatchStep {
    var bookKeeperValue: HeistValue {
        .object(batchStepLogProjection.stepArguments)
    }
}

struct HeaderLogEntry: Encodable {
    let type = "header"
    let formatVersion: String
    let sessionId: String
}

struct CommandLogEntry: Encodable {
    let t: String
    let type = "command"
    let requestId: String
    let command: String
    let args: CommandLogArguments?
}

struct CommandLogArguments: Encodable {
    let values: [String: HeistValue]

    init?(_ values: [String: HeistValue], maxStringLength: Int) {
        let sanitizedValues = values.mapValues {
            $0.sanitizedLogValue(maxStringLength: maxStringLength)
        }
        guard !sanitizedValues.isEmpty else { return nil }
        self.values = sanitizedValues
    }

    func encode(to encoder: Encoder) throws {
        try values.encode(to: encoder)
    }
}

struct ResponseLogEntry: Encodable {
    let t: String
    let type = "response"
    let requestId: String
    let status: ResponseStatus
    let durationMilliseconds: Int
    let artifact: String?
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case t
        case type
        case requestId
        case status
        case durationMilliseconds = "duration_ms"
        case artifact
        case error
    }
}

struct ArtifactLogEntry: Encodable {
    let t: String
    let type = "artifact"
    let artifactType: ArtifactType
    let path: String
    let size: Int
    let requestId: String
    let command: String
    let metadata: [String: Double]?
}

private struct SessionLogProjectionLine: Decodable {
    let type: String?
    let t: String?
    let status: String?
    let artifactType: String?
    let path: String?
    let size: Int?
    let requestId: String?
    let command: String?
    let metadata: [String: Double]?

    var artifact: ArtifactEntry? {
        guard type == "artifact",
              let artifactType,
              let type = ArtifactType(rawValue: artifactType),
              let path,
              let size,
              let t,
              let timestamp = Self.date(from: t),
              let requestId,
              let command else {
            return nil
        }

        return ArtifactEntry(
            type: type,
            path: path,
            size: size,
            timestamp: timestamp,
            requestId: requestId,
            command: command,
            metadata: metadata ?? [:]
        )
    }

    private static func date(from string: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

extension TheBookKeeper {

    // MARK: - Session Log Construction

    static let maxLoggedStringLength = 1000

    /// Serialize a log entry as JSON and append it to the session log file.
    private static let sessionLogEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func appendLogLine<Entry: Encodable>(_ entry: Entry, to handle: FileHandle) throws {
        let jsonData = try Self.sessionLogEncoder.encode(entry)
        var lineData = jsonData
        lineData.append(contentsOf: [0x0A]) // newline
        try handle.write(contentsOf: lineData)
    }

    /// Derive metadata projections from the append-only session log.
    func sessionLogProjection(
        in directory: URL
    ) throws -> (counts: SessionLogCounts, artifacts: [ArtifactEntry], status: SessionLogProjectionStatus) {
        let data = try sessionLogData(in: directory)
        return Self.sessionLogProjection(in: data)
    }

    /// Derive metadata projections from the session log stored in an archive.
    func sessionLogProjection(
        inArchive archivePath: URL
    ) throws -> (counts: SessionLogCounts, artifacts: [ArtifactEntry], status: SessionLogProjectionStatus) {
        let data = try Self.archivedSessionLogData(from: archivePath)
        return Self.sessionLogProjection(in: data)
    }

    // MARK: - Private Helpers

    private func sessionLogData(in directory: URL) throws -> Data {
        let logPath = directory.appendingPathComponent("session.jsonl")
        if FileManager.default.fileExists(atPath: logPath.path) {
            return try Data(contentsOf: logPath)
        }

        let compressedPath = directory.appendingPathComponent("session.jsonl.gz")
        if FileManager.default.fileExists(atPath: compressedPath.path) {
            return try Self.gunzippedData(at: compressedPath)
        }

        throw CocoaError(.fileReadNoSuchFile, userInfo: [
            NSFilePathErrorKey: logPath.path,
        ])
    }

    private static func sessionLogProjection(
        in data: Data
    ) -> (counts: SessionLogCounts, artifacts: [ArtifactEntry], status: SessionLogProjectionStatus) {
        var commandCount = 0
        var errorCount = 0
        var artifacts: [ArtifactEntry] = []
        var malformedLineCount = 0
        var firstMalformedLineNumber: Int?
        var firstMalformedLineCause: String?
        var malformedArtifactCount = 0

        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        for (lineOffset, line) in lines.enumerated() {
            let lineNumber = lineOffset + 1
            if line.isEmpty {
                if lineOffset == lines.count - 1 && data.last == 0x0A {
                    continue
                }
                recordMalformedLine(
                    lineNumber: lineNumber,
                    cause: "empty line",
                    malformedLineCount: &malformedLineCount,
                    firstMalformedLineNumber: &firstMalformedLineNumber,
                    firstMalformedLineCause: &firstMalformedLineCause
                )
                continue
            }

            let entry: SessionLogProjectionLine
            do {
                entry = try JSONDecoder().decode(SessionLogProjectionLine.self, from: Data(line))
            } catch {
                recordMalformedLine(
                    lineNumber: lineNumber,
                    cause: "invalid JSON: \(error.localizedDescription)",
                    malformedLineCount: &malformedLineCount,
                    firstMalformedLineNumber: &firstMalformedLineNumber,
                    firstMalformedLineCause: &firstMalformedLineCause
                )
                continue
            }

            guard let type = entry.type else {
                recordMalformedLine(
                    lineNumber: lineNumber,
                    cause: "missing type",
                    malformedLineCount: &malformedLineCount,
                    firstMalformedLineNumber: &firstMalformedLineNumber,
                    firstMalformedLineCause: &firstMalformedLineCause
                )
                continue
            }

            switch type {
            case "command":
                commandCount += 1
            case "response" where entry.status == ResponseStatus.error.rawValue:
                errorCount += 1
            case "artifact":
                if let artifact = entry.artifact {
                    artifacts.append(artifact)
                } else {
                    malformedArtifactCount += 1
                }
            default:
                continue
            }
        }

        let counts = SessionLogCounts(commandCount: commandCount, errorCount: errorCount)
        let status = SessionLogProjectionStatus(
            malformedLineCount: malformedLineCount,
            firstMalformedLineNumber: firstMalformedLineNumber,
            firstMalformedLineCause: firstMalformedLineCause,
            malformedArtifactCount: malformedArtifactCount
        )
        return (counts: counts, artifacts: artifacts, status: status)
    }

    private static func recordMalformedLine(
        lineNumber: Int,
        cause: String,
        malformedLineCount: inout Int,
        firstMalformedLineNumber: inout Int?,
        firstMalformedLineCause: inout String?
    ) {
        malformedLineCount += 1
        guard firstMalformedLineNumber == nil else { return }
        firstMalformedLineNumber = lineNumber
        firstMalformedLineCause = cause
    }

    private static func gunzippedData(at path: URL) throws -> Data {
        try processOutput(
            executablePath: "/usr/bin/gzip",
            arguments: ["-dc", path.path],
            failureContext: "gzip -dc",
            failure: BookKeeperError.compressionFailed
        )
    }

    private static func gunzippedData(_ data: Data) throws -> Data {
        let temporaryPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).session.jsonl.gz")
        try data.write(to: temporaryPath, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: temporaryPath)
        }
        return try gunzippedData(at: temporaryPath)
    }

    private static func archivedSessionLogData(from archivePath: URL) throws -> Data {
        let listingData = try processOutput(
            executablePath: "/usr/bin/tar",
            arguments: ["-tzf", archivePath.path],
            failureContext: "tar -tzf",
            failure: BookKeeperError.archiveFailed
        )
        let listing = String(data: listingData, encoding: .utf8) ?? ""
        let entries = listing.split(separator: "\n").map(String.init)

        if let logEntry = entries.first(where: { $0.hasSuffix("/session.jsonl") || $0 == "session.jsonl" }) {
            return try archivedEntryData(logEntry, from: archivePath)
        }

        if let compressedEntry = entries.first(where: { $0.hasSuffix("/session.jsonl.gz") || $0 == "session.jsonl.gz" }) {
            let compressedData = try archivedEntryData(compressedEntry, from: archivePath)
            return try gunzippedData(compressedData)
        }

        throw BookKeeperError.archiveFailed("Expected session log not found in archive \(archivePath.path)")
    }

    private static func archivedEntryData(_ entry: String, from archivePath: URL) throws -> Data {
        try processOutput(
            executablePath: "/usr/bin/tar",
            arguments: ["-xOzf", archivePath.path, entry],
            failureContext: "tar -xOzf",
            failure: BookKeeperError.archiveFailed
        )
    }

    private static func processOutput(
        executablePath: String,
        arguments: [String],
        failureContext: String,
        failure: (String) -> BookKeeperError
    ) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).process.stderr")
        FileManager.default.createFile(atPath: errorPath.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorPath)
        defer {
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: errorPath)
        }
        process.standardOutput = outputPipe
        process.standardError = errorHandle
        process.standardInput = FileHandle.nullDevice

        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            try? errorHandle.close()
            let errorOutput = try Data(contentsOf: errorPath)
            let detail = String(data: errorOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw failure(
                "\(failureContext) exited with status \(process.terminationStatus): \(detail ?? "unknown error")"
            )
        }

        return output
    }

    func iso8601Now() -> String {
        iso8601String(from: Date())
    }

    func iso8601String(from date: Date) -> String {
        Self.iso8601Formatter().string(from: date)
    }

    private static func iso8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
