import Foundation

import TheScore

// MARK: - Typed Request Recording

private let evidenceTargetKeys: Set<String> = [
    "heistId", "label", "identifier", "value", "traits", "excludeTraits",
    "ordinal", "elementTarget",
]

private extension HeistValue {
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
}

private extension Encodable {
    func heistEvidenceArguments(renaming renamedKeys: [String: String] = [:]) -> [String: HeistValue] {
        guard case .object(let encoded) = HeistValue.encoded(self) else { return [:] }
        var arguments = encoded.reduce(into: [String: HeistValue]()) { result, pair in
            guard !evidenceTargetKeys.contains(pair.key) else { return }
            result[renamedKeys[pair.key] ?? pair.key] = pair.value
        }
        arguments.flattenRotorTextRange()
        return arguments
    }
}

private extension Dictionary where Key == String, Value == HeistValue {
    mutating func appendExpectation(_ expectation: ActionExpectation?, timeout: Double?) {
        if let expectation {
            self["expect"] = HeistValue.encoded(expectation)
        }
        if let timeout {
            self["timeout"] = HeistValue.encoded(timeout)
        }
    }

    mutating func flattenRotorTextRange() {
        guard case .object(let textRange)? = removeValue(forKey: "currentTextRange") else { return }
        if let startOffset = textRange["startOffset"] {
            self["currentTextStartOffset"] = startOffset
        }
        if let endOffset = textRange["endOffset"] {
            self["currentTextEndOffset"] = endOffset
        }
    }
}

private struct AccessibilityEvidenceArguments: Encodable {
    let action: String?
    let count: Int?
}

extension TheFence.ParsedRequest {
    var heistEvidenceArguments: [String: HeistValue] {
        var arguments = payload.heistEvidenceArguments
        if command != .waitForChange {
            let timeout = expectationPayload.expectation == nil ? nil : expectationPayload.timeout
            arguments.appendExpectation(expectationPayload.expectation, timeout: timeout)
        }
        return arguments
    }
}

extension TheFence.RequestPayload {
    var heistEvidenceArguments: [String: HeistValue] {
        switch self {
        case .gesture(let payload):
            return payload.heistEvidenceArguments
        case .scroll(let payload):
            return payload.heistEvidenceArguments
        case .accessibility(let payload):
            return payload.heistEvidenceArguments
        case .rotor(let target):
            return target.heistEvidenceArguments()
        case .typeText(let target):
            return target.heistEvidenceArguments()
        case .editAction(let target):
            return target.heistEvidenceArguments()
        case .setPasteboard(let target):
            return target.heistEvidenceArguments()
        case .waitFor(let target):
            return target.heistEvidenceArguments()
        case .waitForChange(let payload):
            return WaitForChangeTarget(expect: payload.expectation, timeout: payload.timeout)
                .heistEvidenceArguments()
        case .none, .dismissKeyboard, .getPasteboard, .getInterface, .screen,
             .artifact, .startRecording, .connect, .runBatch, .archiveSession,
             .startHeist, .stopHeist, .playHeist:
            return [:]
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
        case .none, .dismissKeyboard, .getPasteboard, .getInterface, .screen,
             .artifact, .editAction, .setPasteboard, .waitForChange,
             .startRecording, .connect, .runBatch, .archiveSession,
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

private extension TheFence.GesturePayload {
    var heistEvidenceArguments: [String: HeistValue] {
        switch self {
        case .oneFingerTap(let payload):
            return payload.target.heistEvidenceArguments(renaming: ["pointX": "x", "pointY": "y"])
        case .longPress(let payload):
            return payload.target.heistEvidenceArguments(renaming: ["pointX": "x", "pointY": "y"])
        case .swipe(let payload):
            return payload.target.heistEvidenceArguments()
        case .drag(let payload):
            return payload.target.heistEvidenceArguments()
        case .pinch(let payload):
            return payload.target.heistEvidenceArguments()
        case .rotate(let payload):
            return payload.target.heistEvidenceArguments()
        case .twoFingerTap(let payload):
            return payload.target.heistEvidenceArguments()
        case .drawPath(let payload):
            return payload.target.heistEvidenceArguments()
        case .drawBezier(let payload):
            return payload.target.heistEvidenceArguments()
        }
    }

    var bookKeeperElementTarget: ElementTarget? {
        switch self {
        case .oneFingerTap(let payload):
            return payload.selection.elementTarget
        case .longPress(let payload):
            return payload.selection.elementTarget
        case .swipe(let payload):
            return payload.target.selection.bookKeeperElementTarget
        case .drag(let payload):
            return payload.target.start.elementTarget
        case .pinch(let payload):
            return payload.center.elementTarget
        case .rotate(let payload):
            return payload.center.elementTarget
        case .twoFingerTap(let payload):
            return payload.center.elementTarget
        case .drawPath, .drawBezier:
            return nil
        }
    }

    var bookKeeperCoordinateOnly: Bool {
        switch self {
        case .oneFingerTap(let payload):
            return payload.selection.screenPoint != nil
        case .longPress(let payload):
            return payload.selection.screenPoint != nil
        case .swipe(let payload):
            return payload.target.selection.bookKeeperElementTarget == nil
        case .drag(let payload):
            return payload.target.start.elementTarget == nil
        case .pinch(let payload):
            return payload.center.elementTarget == nil
        case .rotate(let payload):
            return payload.center.elementTarget == nil
        case .twoFingerTap(let payload):
            return payload.center.elementTarget == nil
        case .drawPath, .drawBezier:
            return true
        }
    }
}

private extension SwipeGestureSelection {
    var bookKeeperElementTarget: ElementTarget? {
        switch self {
        case .unitElement(let target, _, _, _):
            return target
        case .point(let start, _):
            return start.elementTarget
        }
    }
}

private extension TheFence.ScrollPayload {
    var heistEvidenceArguments: [String: HeistValue] {
        switch self {
        case .scroll(let target):
            return target.heistEvidenceArguments()
        case .scrollToVisible:
            return [:]
        case .elementSearch(let target):
            return target.heistEvidenceArguments()
        case .scrollToEdge(let target):
            return target.heistEvidenceArguments()
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

private extension TheFence.AccessibilityPayload {
    var heistEvidenceArguments: [String: HeistValue] {
        switch self {
        case .activate(_, let actionName, let count):
            return AccessibilityEvidenceArguments(action: actionName, count: count.value)
                .heistEvidenceArguments()
        }
    }

    var bookKeeperElementTarget: ElementTarget? {
        switch self {
        case .activate(let target, _, _):
            return target
        }
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
}

struct ResponseLogEntry: Encodable {
    let t: String
    let type = "response"
    let requestId: String
    let status: ResponseStatus
    let durationMilliseconds: Int
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case t
        case type
        case requestId
        case status
        case durationMilliseconds = "duration_ms"
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

extension TheBookKeeper {

    // MARK: - Session Log Construction

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
