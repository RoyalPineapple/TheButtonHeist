import Foundation

import TheScore

// MARK: - Typed Request Recording

/// Command argument keys BookKeeper treats specially while recording logs and heists.
enum BookKeeperCommandArgumentKey {
    static let heistId = "heistId"
    static let label = "label"
    static let identifier = "identifier"
    static let value = "value"
    static let traits = "traits"
    static let excludeTraits = "excludeTraits"
    static let ordinal = "ordinal"
    static let x = "x"
    static let y = "y"
    static let startX = "startX"
    static let startY = "startY"
    static let endX = "endX"
    static let endY = "endY"
    static let centerX = "centerX"
    static let centerY = "centerY"
    static let points = "points"
}

private extension HeistValue {
    static func encoded<T: Encodable>(_ value: T) -> HeistValue? {
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(HeistValue.self, from: data)
        } catch {
            return nil
        }
    }

    func logJSONValue(maxStringLength: Int) -> Any {
        switch self {
        case .string(let value):
            return value.logJSONValue(maxStringLength: maxStringLength)
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .bool(let value):
            return value
        case .array(let values):
            return values.map { $0.logJSONValue(maxStringLength: maxStringLength) }
        case .object(let values):
            return values.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = pair.value.logJSONValue(maxStringLength: maxStringLength)
            }
        }
    }
}

private extension String {
    func logJSONValue(maxStringLength: Int) -> String {
        if count > maxStringLength {
            return "<\(count) chars>"
        }
        return self
    }
}

private extension Dictionary where Key == String, Value == HeistValue {
    mutating func set(_ key: String, _ value: String?) {
        guard let value else { return }
        self[key] = .string(value)
    }

    mutating func set(_ key: String, _ value: Int?) {
        guard let value else { return }
        self[key] = .int(value)
    }

    mutating func set(_ key: String, _ value: Double?) {
        guard let value else { return }
        self[key] = .double(value)
    }

    mutating func set(_ key: String, _ value: Bool?) {
        guard let value else { return }
        self[key] = .bool(value)
    }

    mutating func set<E: RawRepresentable>(_ key: String, _ value: E?) where E.RawValue == String {
        guard let value else { return }
        self[key] = .string(value.rawValue)
    }

    mutating func appendMatcher(_ matcher: ElementMatcher) {
        set(BookKeeperCommandArgumentKey.label, matcher.label)
        set(BookKeeperCommandArgumentKey.identifier, matcher.identifier)
        set(BookKeeperCommandArgumentKey.value, matcher.value)
        if let traits = matcher.traits {
            self[BookKeeperCommandArgumentKey.traits] = .array(traits.map { .string($0.rawValue) })
        }
        if let excludeTraits = matcher.excludeTraits {
            self[BookKeeperCommandArgumentKey.excludeTraits] = .array(excludeTraits.map { .string($0.rawValue) })
        }
    }

    mutating func appendTarget(_ target: ElementTarget?) {
        guard let target else { return }
        switch target {
        case .heistId(let heistId):
            self[BookKeeperCommandArgumentKey.heistId] = .string(heistId)
        case .matcher(let matcher, let ordinal):
            appendMatcher(matcher)
            set(BookKeeperCommandArgumentKey.ordinal, ordinal)
        }
    }

    mutating func appendExpectation(_ expectation: ActionExpectation?, timeout: Double?) {
        if let expectation, let value = HeistValue.encoded(expectation) {
            self["expect"] = value
        }
        set("timeout", timeout)
    }
}

extension TheFence.ParsedRequest {
    var bookKeeperLogArguments: [String: HeistValue] {
        bookKeeperArguments(includeTarget: true)
    }

    var bookKeeperHeistArguments: [String: HeistValue] {
        bookKeeperArguments(includeTarget: false)
    }

    var bookKeeperElementTarget: ElementTarget? {
        payload.bookKeeperElementTarget
    }

    var bookKeeperCoordinateOnly: Bool {
        payload.bookKeeperCoordinateOnly
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
        case .artifact(let request):
            var arguments: [String: HeistValue] = [:]
            arguments.set("output", request.outputPath)
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
            arguments.set("text", target.text)
            if includeTarget {
                arguments.appendTarget(target.elementTarget)
            }
            return arguments
        case .editAction(let target):
            var arguments: [String: HeistValue] = [:]
            arguments.set("action", target.action)
            return arguments
        case .setPasteboard(let target):
            var arguments: [String: HeistValue] = [:]
            arguments.set("text", target.text)
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
            if request.deleteSource {
                arguments.set("delete_source", true)
            }
            return arguments
        case .startHeist(let request):
            var arguments: [String: HeistValue] = [:]
            arguments.set("app", request.app)
            arguments.set("identifier", request.identifier)
            return arguments
        case .stopHeist(let request):
            var arguments: [String: HeistValue] = [:]
            arguments.set("output", request.outputPath)
            return arguments
        case .playHeist(let request):
            var arguments: [String: HeistValue] = [:]
            arguments.set("input", request.inputPath)
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
        case .none, .getInterface, .artifact, .editAction, .setPasteboard,
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
        if scope != .full {
            arguments.set("scope", scope)
        }
        if detail != .summary {
            arguments.set("detail", detail)
        }
        if matcher.hasPredicates {
            arguments.appendMatcher(matcher)
        }
        if let elementIds {
            arguments["elements"] = .array(elementIds.map { .string($0) })
        }
        return arguments
    }
}

private extension TheFence.GesturePayload {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        switch self {
        case .oneFingerTap(let target):
            return target.bookKeeperArguments(includeTarget: includeTarget)
        case .longPress(let target):
            return target.bookKeeperArguments(includeTarget: includeTarget)
        case .swipe(let target):
            return target.bookKeeperArguments(includeTarget: includeTarget)
        case .drag(let target):
            return target.bookKeeperArguments(includeTarget: includeTarget)
        case .pinch(let target):
            return target.bookKeeperArguments(includeTarget: includeTarget)
        case .rotate(let target):
            return target.bookKeeperArguments(includeTarget: includeTarget)
        case .twoFingerTap(let target):
            return target.bookKeeperArguments(includeTarget: includeTarget)
        case .drawPath(let target):
            return target.bookKeeperArguments
        case .drawBezier(let target):
            return target.bookKeeperArguments
        }
    }

    var bookKeeperElementTarget: ElementTarget? {
        switch self {
        case .oneFingerTap(let target):
            return target.elementTarget
        case .longPress(let target):
            return target.elementTarget
        case .swipe(let target):
            return target.elementTarget
        case .drag(let target):
            return target.elementTarget
        case .pinch(let target):
            return target.elementTarget
        case .rotate(let target):
            return target.elementTarget
        case .twoFingerTap(let target):
            return target.elementTarget
        case .drawPath, .drawBezier:
            return nil
        }
    }

    var bookKeeperCoordinateOnly: Bool {
        switch self {
        case .oneFingerTap(let target):
            return target.elementTarget == nil && target.point != nil
        case .longPress(let target):
            return target.elementTarget == nil && target.point != nil
        case .swipe(let target):
            return target.elementTarget == nil
        case .drag(let target):
            return target.elementTarget == nil
        case .pinch(let target):
            return target.elementTarget == nil
        case .rotate(let target):
            return target.elementTarget == nil
        case .twoFingerTap(let target):
            return target.elementTarget == nil
        case .drawPath, .drawBezier:
            return true
        }
    }
}

private extension TouchTapTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(BookKeeperCommandArgumentKey.x, pointX)
        arguments.set(BookKeeperCommandArgumentKey.y, pointY)
        if includeTarget {
            arguments.appendTarget(elementTarget)
        }
        return arguments
    }
}

private extension LongPressTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(BookKeeperCommandArgumentKey.x, pointX)
        arguments.set(BookKeeperCommandArgumentKey.y, pointY)
        arguments.set("duration", duration)
        if includeTarget {
            arguments.appendTarget(elementTarget)
        }
        return arguments
    }
}

private extension SwipeTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set("direction", direction)
        arguments.set(BookKeeperCommandArgumentKey.startX, startX)
        arguments.set(BookKeeperCommandArgumentKey.startY, startY)
        arguments.set(BookKeeperCommandArgumentKey.endX, endX)
        arguments.set(BookKeeperCommandArgumentKey.endY, endY)
        arguments.set("duration", duration)
        if let start {
            arguments["start"] = start.bookKeeperValue
        }
        if let end {
            arguments["end"] = end.bookKeeperValue
        }
        if includeTarget {
            arguments.appendTarget(elementTarget)
        }
        return arguments
    }
}

private extension DragTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(BookKeeperCommandArgumentKey.startX, startX)
        arguments.set(BookKeeperCommandArgumentKey.startY, startY)
        arguments.set(BookKeeperCommandArgumentKey.endX, endX)
        arguments.set(BookKeeperCommandArgumentKey.endY, endY)
        arguments.set("duration", duration)
        if includeTarget {
            arguments.appendTarget(elementTarget)
        }
        return arguments
    }
}

private extension PinchTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(BookKeeperCommandArgumentKey.centerX, centerX)
        arguments.set(BookKeeperCommandArgumentKey.centerY, centerY)
        arguments.set("scale", scale)
        arguments.set("spread", spread)
        arguments.set("duration", duration)
        if includeTarget {
            arguments.appendTarget(elementTarget)
        }
        return arguments
    }
}

private extension RotateTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(BookKeeperCommandArgumentKey.centerX, centerX)
        arguments.set(BookKeeperCommandArgumentKey.centerY, centerY)
        arguments.set("angle", angle)
        arguments.set("radius", radius)
        arguments.set("duration", duration)
        if includeTarget {
            arguments.appendTarget(elementTarget)
        }
        return arguments
    }
}

private extension TwoFingerTapTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(BookKeeperCommandArgumentKey.centerX, centerX)
        arguments.set(BookKeeperCommandArgumentKey.centerY, centerY)
        arguments.set("spread", spread)
        if includeTarget {
            arguments.appendTarget(elementTarget)
        }
        return arguments
    }
}

private extension UnitPoint {
    var bookKeeperValue: HeistValue {
        .object([
            "x": .double(x),
            "y": .double(y),
        ])
    }
}

private extension PathPoint {
    var bookKeeperValue: HeistValue {
        .object([
            "x": .double(x),
            "y": .double(y),
        ])
    }
}

private extension DrawPathTarget {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments[BookKeeperCommandArgumentKey.points] = .array(points.map(\.bookKeeperValue))
        arguments.set("duration", duration)
        arguments.set("velocity", velocity)
        return arguments
    }
}

private extension BezierSegment {
    var bookKeeperValue: HeistValue {
        .object([
            "cp1X": .double(cp1X),
            "cp1Y": .double(cp1Y),
            "cp2X": .double(cp2X),
            "cp2Y": .double(cp2Y),
            "endX": .double(endX),
            "endY": .double(endY),
        ])
    }
}

private extension DrawBezierTarget {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(BookKeeperCommandArgumentKey.startX, startX)
        arguments.set(BookKeeperCommandArgumentKey.startY, startY)
        arguments["segments"] = .array(segments.map(\.bookKeeperValue))
        arguments.set("samplesPerSegment", samplesPerSegment)
        arguments.set("duration", duration)
        arguments.set("velocity", velocity)
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
            if includeTarget {
                arguments.appendTarget(target.elementTarget)
            }
            return arguments
        case .elementSearch(let target):
            var arguments: [String: HeistValue] = [:]
            arguments.set("direction", target.direction)
            if includeTarget {
                arguments.appendTarget(target.elementTarget)
            }
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
        arguments.set("direction", direction)
        if includeTarget {
            arguments.appendTarget(elementTarget)
        }
        return arguments
    }
}

private extension ScrollToEdgeTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set("edge", edge)
        if includeTarget {
            arguments.appendTarget(elementTarget)
        }
        return arguments
    }
}

private extension TheFence.AccessibilityPayload {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        switch self {
        case .activate(let target, let actionName, let count):
            arguments.set("action", actionName)
            arguments.set("count", count.value)
            if includeTarget {
                arguments.appendTarget(target)
            }
        case .increment(let target, let count),
             .decrement(let target, let count):
            arguments.set("count", count.value)
            if includeTarget {
                arguments.appendTarget(target)
            }
        case .performCustomAction(let target, let actionName, let count):
            arguments.set("action", actionName)
            arguments.set("count", count.value)
            if includeTarget {
                arguments.appendTarget(target)
            }
        }
        return arguments
    }

    var bookKeeperElementTarget: ElementTarget {
        switch self {
        case .activate(let target, _, _),
             .increment(let target, _),
             .decrement(let target, _),
             .performCustomAction(let target, _, _):
            return target
        }
    }
}

private extension RotorTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set("rotor", rotor)
        arguments.set("rotorIndex", rotorIndex)
        arguments.set("direction", direction)
        arguments.set("currentHeistId", currentHeistId)
        arguments.set("currentTextStartOffset", currentTextRange?.startOffset)
        arguments.set("currentTextEndOffset", currentTextRange?.endOffset)
        if includeTarget {
            arguments.appendTarget(elementTarget)
        }
        return arguments
    }
}

private extension WaitForTarget {
    func bookKeeperArguments(includeTarget: Bool) -> [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set("absent", absent)
        arguments.set("timeout", timeout)
        if includeTarget {
            arguments.appendTarget(elementTarget)
        }
        return arguments
    }
}

private extension RecordingConfig {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set("fps", fps)
        arguments.set("scale", scale)
        arguments.set("inactivity_timeout", inactivityTimeout)
        arguments.set("max_duration", maxDuration)
        return arguments
    }
}

private extension TheFence.ConnectRequest {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set("target", targetName)
        arguments.set("device", device)
        arguments.set("token", token)
        return arguments
    }
}

private extension TheFence.RunBatchRequest {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments["steps"] = .array(steps.map(\.bookKeeperValue))
        if policy != .stopOnError {
            arguments.set("policy", policy)
        }
        return arguments
    }
}

private extension TheFence.RunBatchStepRequest {
    var bookKeeperValue: HeistValue {
        switch self {
        case .decoded(let request):
            var values = request.bookKeeperLogArguments
            values["command"] = .string(request.command.rawValue)
            return .object(values)
        case .invalid(let commandName, let failure):
            return .object([
                "command": .string(commandName),
                "decodeError": .string(failure.message),
            ])
        }
    }
}

extension TheBookKeeper {

    // MARK: - Session Log Construction

    private static let maxLoggedStringLength = 1000

    /// Build the header entry that identifies a session log stream.
    func buildHeaderLogEntry(sessionId: String) -> [String: Any] {
        [
            "type": "header",
            "formatVersion": SessionFormatVersion.current,
            "sessionId": sessionId,
        ]
    }

    /// Build a sanitized log entry for an incoming command.
    func buildCommandLogEntry(_ request: TheFence.ParsedRequest) -> [String: Any] {
        var entry: [String: Any] = [
            "t": iso8601Now(),
            "type": "command",
            "requestId": request.requestId,
            "command": request.command.rawValue,
        ]
        let sanitizedArgs = request.bookKeeperLogArguments.reduce(into: [:]) { result, pair in
            result[pair.key] = pair.value.logJSONValue(maxStringLength: Self.maxLoggedStringLength)
        }
        if !sanitizedArgs.isEmpty {
            entry["args"] = sanitizedArgs
        }
        return entry
    }

    /// Build a sanitized log entry for a command response.
    func buildResponseLogEntry(
        requestId: String,
        status: ResponseStatus,
        durationMilliseconds: Int,
        artifact: String?,
        error: String?
    ) -> [String: Any] {
        var entry: [String: Any] = [
            "t": iso8601Now(),
            "type": "response",
            "requestId": requestId,
            "status": status.rawValue,
            "duration_ms": durationMilliseconds,
        ]
        if let artifact {
            entry["artifact"] = artifact
        }
        if let error {
            entry["error"] = error
        }
        return entry
    }

    /// Serialize a log entry as JSON and append it to the session log file.
    func appendLogLine(_ entry: [String: Any], to handle: FileHandle) throws {
        let jsonData = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
        var lineData = jsonData
        lineData.append(contentsOf: [0x0A]) // newline
        try handle.write(contentsOf: lineData)
    }

    // MARK: - Private Helpers

    private func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
