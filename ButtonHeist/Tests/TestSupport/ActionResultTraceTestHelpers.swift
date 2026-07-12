import Foundation
import AccessibilitySnapshotModel
import ThePlans
@testable import TheScore

package func makeTestScreenPayload(
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

package func makeTestHeistElement(
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

package func makeTestActionResult(
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
    let settlement = settled.map {
        let durationMs = settleTimeMs ?? timing?.settleMs ?? 0
        return $0
            ? ActionSettlementEvidence.settled(durationMs: durationMs)
            : ActionSettlementEvidence.timedOut(durationMs: durationMs)
    }
    let evidence = ActionResultEvidence(
        accessibilityTrace: accessibilityTrace,
        settlement: settlement,
        subjectEvidence: subjectEvidence,
        activationTrace: activationTrace,
        timing: timing
    )
    if succeeded {
        if let payload {
            return ActionResult.success(
                payload: payload,
                message: message,
                evidence: evidence
            )
        }
        return ActionResult.success(
            method: method,
            message: message,
            evidence: evidence
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
            evidence: evidence
        )
    }
    return ActionResult.failure(
        method: method,
        errorKind: errorKind,
        message: message,
        evidence: evidence
    )
}

package func makeTestHeistActionStep(
    path: String = "$.body[0]",
    command: HeistActionCommand? = nil,
    result: ActionResult = makeTestActionResult(),
    durationMs: Int = 1
) -> HeistExecutionStepResult {
    let actionEvidence = command.map {
        HeistActionEvidence.dispatch(command: $0, dispatchResult: result, warning: nil)
    } ?? HeistActionEvidence.commandlessDispatch(dispatchResult: result)
    guard !result.outcome.isSuccess else {
        return .passed(
            path: path,
            receiptKind: .action,
            durationMs: durationMs,
            evidence: actionEvidence
        )
    }
    return .failed(
        path: path,
        receiptKind: .action,
        durationMs: durationMs,
        evidence: actionEvidence,
        failure: HeistFailureDetail(
            category: result.outcome.errorKind == .elementNotFound ? .targetResolution : .action,
            contract: "action dispatch succeeds",
            observed: result.message ?? "action failed"
        )
    )
}

package func makeTestHeistExecutionResult(
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

package extension AccessibilityTrace {
    static func noChangeForTests(elementCount: Int) -> AccessibilityTrace {
        TestActionResultTrace.noChange(elementCount: elementCount)
    }

    static func elementsChangedForTests(
        elementCount: Int,
        edits: ElementEdits
    ) -> AccessibilityTrace {
        TestActionResultTrace.elementsChanged(elementCount: elementCount, edits: edits)
    }

    static func screenChangedForTests(replacementInterface: Interface) -> AccessibilityTrace {
        TestActionResultTrace.screenChanged(replacementInterface: replacementInterface)
    }
}

private enum TestActionResultTrace {
    static func noChange(elementCount: Int) -> AccessibilityTrace {
        let interface = interface(elements: placeholders(count: elementCount))
        return AccessibilityTrace(captures: [
            capture(sequence: 1, interface: interface),
            capture(sequence: 2, interface: interface),
        ])
    }

    static func elementsChanged(elementCount: Int, edits: ElementEdits) -> AccessibilityTrace {
        let before = interface(elements: beforeElements(for: edits, elementCount: elementCount))
        let after = interface(elements: afterElements(for: edits, elementCount: elementCount))
        if edits.isEmpty {
            return AccessibilityTrace(captures: [
                capture(sequence: 1, interface: before, context: .empty),
                capture(sequence: 2, interface: before, context: AccessibilityTrace.Context(keyboardVisible: true)),
            ])
        }
        return AccessibilityTrace(captures: [
            capture(sequence: 1, interface: before),
            capture(sequence: 2, interface: after),
        ])
    }

    static func screenChanged(replacementInterface: Interface) -> AccessibilityTrace {
        AccessibilityTrace(captures: [
            capture(
                sequence: 1,
                interface: interface(elements: []),
                context: AccessibilityTrace.Context(screenId: "before")
            ),
            capture(
                sequence: 2,
                interface: replacementInterface,
                context: AccessibilityTrace.Context(screenId: "after")
            ),
        ])
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
