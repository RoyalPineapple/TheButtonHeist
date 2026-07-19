import ButtonHeistTestSupport
import Testing
import ThePlans
import TheScore
@testable import HeistDoctorCore

func request(
    _ last: HeistRepairEvidence,
    _ current: HeistRepairEvidence
) -> HeistRepairRequest {
    guard let request = try? HeistRepairRequest(lastSuccess: last, currentFailure: current) else {
        preconditionFailure("repair request fixture requires passed then failed evidence")
    }
    return request
}

func passedEvidence(
    heistFingerprint: String? = nil,
    stepPath: HeistExecutionPath = "$.body[0]",
    command: HeistActionCommand? = nil,
    target: AccessibilityTarget,
    before: Interface,
    changeFacts: [AccessibilityTrace.ChangeFact] = [],
    expectation: ExpectationResult? = nil
) -> HeistRepairEvidence {
    let command = command ?? .activate(target)
    return HeistRepairEvidence(
        heistFingerprint: heistFingerprint,
        stepPath: stepPath,
        command: command,
        target: target,
        beforeSnapshot: before,
        changeFacts: changeFacts,
        method: method(for: command),
        expectation: expectation,
        outcome: .passed
    )
}

func failedEvidence(
    heistFingerprint: String? = nil,
    stepPath: HeistExecutionPath = "$.body[0]",
    command: HeistActionCommand? = nil,
    target: AccessibilityTarget,
    before: Interface,
    changeFacts: [AccessibilityTrace.ChangeFact] = [],
    expectation: ExpectationResult? = nil
) -> HeistRepairEvidence {
    let command = command ?? .activate(target)
    return HeistRepairEvidence(
        heistFingerprint: heistFingerprint,
        stepPath: stepPath,
        command: command,
        target: target,
        beforeSnapshot: before,
        changeFacts: changeFacts,
        method: method(for: command),
        expectation: expectation,
        outcome: .failed(errorKind: .elementNotFound, message: nil)
    )
}

func method(for command: HeistActionCommand) -> ActionMethod? {
    switch command.wireType {
    case .activate:
        return .activate
    case .increment:
        return .increment
    default:
        return nil
    }
}

func listInterface(rows: [(String, String)]) -> Interface {
    makeTestInterface(nodes: rows.map { title, action in
        testContainer(makeTestAccessibilityContainer(), children: [
            testElement(element(label: title, traits: [.staticText])),
            testElement(element(label: action, traits: [.button], actions: [.activate])),
        ])
    })
}

func element(
    label: String? = nil,
    identifier: String? = nil,
    value: String? = nil,
    traits: [HeistTrait] = [],
    actions: [ElementAction] = [],
    frameX: Double = 0,
    frameY: Double = 0
) -> HeistElement {
    HeistElement(
        description: label ?? "element",
        label: label,
        value: value,
        identifier: identifier,
        traits: traits,
        frameX: frameX,
        frameY: frameY,
        frameWidth: 100,
        frameHeight: 44,
        actions: actions
    )
}
