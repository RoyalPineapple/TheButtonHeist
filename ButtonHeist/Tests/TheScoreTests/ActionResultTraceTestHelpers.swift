import Foundation
import XCTest
import ThePlans
@testable import TheScore

struct JSONProbe {
    private let value: Any?
    private let path: String

    init(_ value: Any?, path: String = "$") {
        self.value = value
        self.path = path
    }

    init(data: Data, file: StaticString = #filePath, line: UInt = #line) {
        do {
            self.init(try JSONSerialization.jsonObject(with: data))
        } catch {
            XCTFail("Failed to decode JSON: \(error)", file: file, line: line)
            self.init(nil)
        }
    }

    func object(
        _ key: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> JSONProbe {
        let probe = key.map(child) ?? self
        guard probe.value is [String: Any] else {
            XCTFail("Expected object at \(probe.path), got \(probe.typeDescription)", file: file, line: line)
            return JSONProbe([:], path: probe.path)
        }
        return probe
    }

    func array(
        _ key: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [JSONProbe] {
        let probe = key.map(child) ?? self
        guard let array = probe.value as? [Any] else {
            XCTFail("Expected array at \(probe.path), got \(probe.typeDescription)", file: file, line: line)
            return []
        }
        return array.enumerated().map { index, value in
            JSONProbe(value, path: "\(probe.path)[\(index)]")
        }
    }

    func string(
        _ key: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String? {
        typedValue(key, as: String.self, file: file, line: line)
    }

    func bool(
        _ key: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool? {
        typedValue(key, as: Bool.self, file: file, line: line)
    }

    func int(
        _ key: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Int? {
        let probe = key.map(child) ?? self
        if let value = probe.value as? Int { return value }
        if let number = probe.value as? NSNumber { return number.intValue }
        XCTFail("Expected int at \(probe.path), got \(probe.typeDescription)", file: file, line: line)
        return nil
    }

    func assertPresent(
        _ key: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let object = value as? [String: Any] else {
            XCTFail("Expected object at \(path), got \(typeDescription)", file: file, line: line)
            return
        }
        XCTAssertNotNil(object[key], "Expected \(path).\(key) to be present", file: file, line: line)
    }

    func assertMissing(
        _ key: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let object = value as? [String: Any] else {
            XCTFail("Expected object at \(path), got \(typeDescription)", file: file, line: line)
            return
        }
        XCTAssertNil(object[key], "Expected \(path).\(key) to be absent", file: file, line: line)
    }

    func isEmptyObject(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        guard let object = value as? [String: Any] else {
            XCTFail("Expected object at \(path), got \(typeDescription)", file: file, line: line)
            return false
        }
        return object.isEmpty
    }

    private func child(_ key: String) -> JSONProbe {
        guard let object = value as? [String: Any] else {
            return JSONProbe(nil, path: "\(path).\(key)")
        }
        return JSONProbe(object[key], path: "\(path).\(key)")
    }

    private func typedValue<T>(
        _ key: String?,
        as type: T.Type,
        file: StaticString,
        line: UInt
    ) -> T? {
        let probe = key.map(child) ?? self
        guard let value = probe.value as? T else {
            XCTFail("Expected \(type) at \(probe.path), got \(probe.typeDescription)", file: file, line: line)
            return nil
        }
        return value
    }

    private var typeDescription: String {
        guard let value else { return "nil" }
        return String(describing: Swift.type(of: value))
    }
}

func assertRoundTrip<T: Codable & Equatable>(
    _ value: T,
    as type: T.Type = T.self,
    encoder: JSONEncoder = JSONEncoder(),
    decoder: JSONDecoder = JSONDecoder(),
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> T {
    let data = try encoder.encode(value)
    let decoded = try decoder.decode(type, from: data)
    XCTAssertEqual(decoded, value, file: file, line: line)
    return decoded
}

func assertDecodeFailure<T: Decodable>(
    _ type: T.Type,
    json: String,
    decoder: JSONDecoder = JSONDecoder(),
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertThrowsError(try decoder.decode(type, from: Data(json.utf8)), file: file, line: line)
}

func makeTestScreenPayload(
    pngData: String = "",
    width: Double = 393,
    height: Double = 852,
    timestamp: Date = Date(timeIntervalSince1970: 0),
    interface: Interface? = nil
) -> ScreenPayload {
    ScreenPayload(
        pngData: pngData,
        width: width,
        height: height,
        timestamp: timestamp,
        interface: interface
    )
}

func makeTestHeistElement(
    label: String = "Element",
    value: String? = nil,
    identifier: String? = nil,
    hint: String? = nil,
    traits: [HeistTrait] = [.button],
    frameX: Double = 0,
    frameY: Double = 0,
    frameWidth: Double = 100,
    frameHeight: Double = 44,
    actions: [ElementAction]? = nil
) -> HeistElement {
    HeistElement(
        description: label,
        label: label,
        value: value,
        identifier: identifier,
        hint: hint,
        traits: traits,
        frameX: frameX,
        frameY: frameY,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        actions: actions ?? (traits.contains(.button) ? [.activate] : [])
    )
}

func makeTestActionResult(
    success: Bool = true,
    method: ActionMethod = .activate,
    message: String? = nil,
    errorKind: ErrorKind? = nil,
    payload: ResultPayload? = nil,
    accessibilityTrace: AccessibilityTrace? = nil,
    settled: Bool? = nil,
    settleTimeMs: Int? = nil,
    subjectEvidence: ActionSubjectEvidence? = nil,
    activationTrace: ActivationTrace? = nil,
    timing: ActionPerformanceTiming? = nil
) -> ActionResult {
    ActionResult(
        success: success,
        method: method,
        message: message,
        errorKind: errorKind,
        payload: payload,
        accessibilityTrace: accessibilityTrace,
        settled: settled,
        settleTimeMs: settleTimeMs,
        subjectEvidence: subjectEvidence,
        activationTrace: activationTrace,
        timing: timing
    )
}

func makeTestHeistActionStep(
    path: String = "$.body[0]",
    command: HeistActionCommand? = nil,
    result: ActionResult = makeTestActionResult(),
    durationMs: Int = 1
) -> HeistExecutionStepResult {
    HeistExecutionStepResult(
        path: path,
        kind: .action,
        status: result.success ? .passed : .failed,
        durationMs: durationMs,
        evidence: .action(HeistActionEvidence(command: command, actionResult: result))
    )
}

func makeTestHeistExecutionResult(
    steps: [HeistExecutionStepResult] = [makeTestHeistActionStep()],
    durationMs: Int = 1,
    abortedAtPath: String? = nil
) -> HeistExecutionResult {
    HeistExecutionResult(
        steps: steps,
        durationMs: durationMs,
        abortedAtPath: abortedAtPath
    )
}

extension AccessibilityTrace {
    static func projectingForTests(_ delta: AccessibilityTrace.Delta) -> AccessibilityTrace {
        TestActionResultTrace.projecting(delta)
    }
}

private enum TestActionResultTrace {
    static func projecting(_ delta: AccessibilityTrace.Delta) -> AccessibilityTrace {
        switch delta {
        case .noChange(let payload):
            let interface = makeTestInterface(elements: placeholders(count: payload.elementCount))
            return AccessibilityTrace(captures: [
                capture(sequence: 1, interface: interface),
                capture(sequence: 2, interface: interface),
            ])

        case .elementsChanged(let payload):
            let before = makeTestInterface(elements: beforeElements(for: payload.edits, elementCount: payload.elementCount))
            let after = makeTestInterface(elements: afterElements(for: payload.edits, elementCount: payload.elementCount))
            if payload.edits.isEmpty {
                return AccessibilityTrace(captures: [
                    capture(sequence: 1, interface: before, context: .empty),
                    capture(sequence: 2, interface: before, context: AccessibilityTrace.Context(keyboardVisible: true)),
                ])
            }
            return AccessibilityTrace(captures: [
                capture(sequence: 1, interface: before),
                capture(sequence: 2, interface: after),
            ])

        case .screenChanged(let payload):
            let before = makeTestInterface(elements: placeholders(count: max(payload.elementCount, 1)))
            return AccessibilityTrace(captures: [
                capture(sequence: 1, interface: before, context: AccessibilityTrace.Context(screenId: "before")),
                capture(sequence: 2, interface: payload.newInterface, context: AccessibilityTrace.Context(screenId: "after")),
            ])
        }
    }

    private static func capture(
        sequence: Int,
        interface: Interface,
        context: AccessibilityTrace.Context = .empty
    ) -> AccessibilityTrace.Capture {
        AccessibilityTrace.Capture(sequence: sequence, interface: interface, context: context)
    }

    private static func beforeElements(for edits: ElementEdits, elementCount: Int) -> [HeistElement] {
        padded(edits.removed + edits.updated.map(\.before), count: elementCount)
    }

    private static func afterElements(for edits: ElementEdits, elementCount: Int) -> [HeistElement] {
        padded(edits.added + edits.updated.map(\.after), count: elementCount)
    }

    private static func padded(_ elements: [HeistElement], count: Int) -> [HeistElement] {
        let missing = max(0, count - elements.count)
        return elements + placeholders(count: missing, prefix: "__stable_")
    }

    private static func placeholders(count: Int, prefix: String = "__element_") -> [HeistElement] {
        guard count > 0 else { return [] }
        return (0..<count).map { placeholder(id: "\(prefix)\($0)", label: "Element \($0)") }
    }

    private static func placeholder(
        id: String,
        label: String,
        value: String? = nil,
        identifier: String? = nil,
        hint: String? = nil,
        traits: [HeistTrait] = [.button]
    ) -> HeistElement {
        makeTestHeistElement(
            label: label,
            value: value,
            identifier: identifier,
            hint: hint,
            traits: traits,
            actions: [.activate]
        )
    }
}
