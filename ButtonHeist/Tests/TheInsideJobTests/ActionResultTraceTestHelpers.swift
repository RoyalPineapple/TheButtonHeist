import Foundation
import XCTest
import AccessibilitySnapshotModel
import ThePlans
@testable import TheScore

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
    succeeded: Bool = true,
    method: ActionMethod = .activate,
    message: String? = nil,
    errorKind: ErrorKind? = nil,
    payload: ActionResultPayload? = nil,
    accessibilityTrace: AccessibilityTrace? = nil,
    settled: Bool? = nil,
    settleTimeMs: Int? = nil,
    subjectEvidence: ActionSubjectEvidence? = nil,
    activationTrace: ActivationTrace? = nil,
    timing: ActionPerformanceTiming? = nil
) -> ActionResult {
    if succeeded {
        if let payload {
            return ActionResult.success(
                payload: payload,
                message: message,
                accessibilityTrace: accessibilityTrace,
                settled: settled,
                settleTimeMs: settleTimeMs,
                subjectEvidence: subjectEvidence,
                activationTrace: activationTrace,
                timing: timing
            )
        }
        return ActionResult.success(
            method: method,
            message: message,
            accessibilityTrace: accessibilityTrace,
            settled: settled,
            settleTimeMs: settleTimeMs,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
    }

    guard let errorKind else {
        preconditionFailure("failed test ActionResult requires errorKind")
    }
    if let payload {
        return ActionResult.failure(
            payload: payload,
            errorKind: errorKind,
            message: message,
            accessibilityTrace: accessibilityTrace,
            settled: settled,
            settleTimeMs: settleTimeMs,
            subjectEvidence: subjectEvidence,
            activationTrace: activationTrace,
            timing: timing
        )
    }
    return ActionResult.failure(
        method: method,
        errorKind: errorKind,
        message: message,
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
    let actionEvidence = command.map {
        HeistActionEvidence.dispatch(command: $0, dispatchResult: result)
    } ?? HeistActionEvidence.dispatch(dispatchResult: result)
    let evidence = HeistStepEvidence.action(actionEvidence)
    guard !result.success else {
        return .passed(
            path: path,
            kind: .action,
            durationMs: durationMs,
            evidence: evidence
        )
    }
    return .failed(
        path: path,
        kind: .action,
        durationMs: durationMs,
        evidence: evidence,
        failure: HeistFailureDetail(
            category: result.errorKind == .elementNotFound ? .targetResolution : .action,
            contract: "action dispatch succeeds",
            observed: result.message ?? "action failed"
        )
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
            let interface = interface(elements: placeholders(count: payload.elementCount))
            return AccessibilityTrace(captures: [
                capture(sequence: 1, interface: interface),
                capture(sequence: 2, interface: interface),
            ])

        case .elementsChanged(let payload):
            let before = interface(elements: beforeElements(for: payload.edits, elementCount: payload.elementCount))
            let after = interface(elements: afterElements(for: payload.edits, elementCount: payload.elementCount))
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
            let before = interface(elements: placeholders(count: max(payload.elementCount, 1)))
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

    private static func interface(elements: [HeistElement]) -> Interface {
        let annotations = elements.enumerated().map { index, element in
            InterfaceElementAnnotation(path: TreePath([index]), actions: element.actions)
        }
        let tree = elements.enumerated().map { index, element in
            AccessibilityHierarchy.element(accessibilityElement(element), traversalIndex: index)
        }
        return Interface(
            timestamp: Date(timeIntervalSince1970: 0),
            tree: tree,
            annotations: InterfaceAnnotations(elements: annotations)
        )
    }

    private static func accessibilityElement(_ element: HeistElement) -> AccessibilityElement {
        AccessibilityElement(
            description: element.description,
            label: element.label,
            value: element.value,
            traits: AccessibilityTraits.fromNames(element.traits.map(\.rawValue)),
            identifier: element.identifier,
            hint: element.hint,
            userInputLabels: nil,
            shape: .frame(AccessibilityRect(
                x: element.frameX,
                y: element.frameY,
                width: element.frameWidth,
                height: element.frameHeight
            )),
            activationPoint: AccessibilityPoint(x: element.activationPointX, y: element.activationPointY),
            usesDefaultActivationPoint: usesDefaultActivationPoint(element),
            customActions: [],
            customContent: element.customContent?.map {
                AccessibilityElement.CustomContent(label: $0.label, value: $0.value, isImportant: $0.isImportant)
            } ?? [],
            customRotors: element.rotors?.map { AccessibilityElement.CustomRotor(name: $0.name) } ?? [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: element.respondsToUserInteraction
        )
    }

    private static func usesDefaultActivationPoint(_ element: HeistElement) -> Bool {
        element.activationPointX == element.frameX + (element.frameWidth / 2) &&
            element.activationPointY == element.frameY + (element.frameHeight / 2)
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
