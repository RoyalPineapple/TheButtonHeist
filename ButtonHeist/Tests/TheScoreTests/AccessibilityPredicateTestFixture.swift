import ButtonHeistTestSupport
import Foundation
import ThePlans
@testable import TheScore

extension AccessibilityPredicateTests {

    func element(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        hint: String? = nil,
        traits: [HeistTrait] = [],
        frameX: Double = 0,
        frameY: Double = 0,
        frameWidth: Double = 100,
        frameHeight: Double = 44,
        activationPointEvidence: ActivationPointEvidence? = nil,
        customContent: [HeistCustomContent]? = nil,
        rotors: [HeistRotor]? = nil,
        actions: [ElementAction] = []
    ) -> HeistElement {
        makeTestHeistElement(
            description: label ?? "",
            label: label,
            value: value,
            identifier: identifier,
            hint: hint,
            traits: traits,
            frameX: frameX,
            frameY: frameY,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            activationPointEvidence: activationPointEvidence,
            customContent: customContent,
            rotors: rotors,
            actions: actions
        )
    }

    func result(
        success: Bool,
        message: String? = nil
    ) -> ActionResult {
        result(success: success, message: message, observation: .none)
    }

    func result(
        success: Bool,
        message: String? = nil,
        trace: AccessibilityTrace,
        completeness: AccessibilityTraceEvidence.Completeness
    ) -> ActionResult {
        result(
            success: success,
            message: message,
            observation: .trace(traceEvidence(trace, completeness: completeness))
        )
    }

    func result(
        success: Bool,
        message: String?,
        observation: ActionResultObservationEvidence
    ) -> ActionResult {
        if success {
            return ActionResult.success(
                method: .oneFingerTap,
                message: message,
                observation: observation
            )
        }
        return ActionResult.failure(
            method: .oneFingerTap,
            failureKind: .actionFailed,
            message: message,
            observation: observation
        )
    }

    func traceEvidence(
        _ trace: AccessibilityTrace,
        completeness: AccessibilityTraceEvidence.Completeness
    ) -> AccessibilityTraceEvidence {
        guard let evidence = AccessibilityTraceEvidence(trace: trace, completeness: completeness) else {
            preconditionFailure("test trace evidence requires a current capture")
        }
        return evidence
    }

    func screenTrace(before: Interface, after: Interface) -> AccessibilityTrace {
        AccessibilityTrace(
            capture: AccessibilityTrace.Capture(
                sequence: 1,
                interface: before,
                context: AccessibilityTrace.Context(screenId: "before")
            )
        ).appending(
            after,
            context: AccessibilityTrace.Context(screenId: "after"),
            transition: screenChangedTransition()
        )
    }

    func screenChangedTransition() -> AccessibilityTrace.Transition {
        AccessibilityTrace.Transition(accessibilityNotifications: [
            AccessibilityNotificationEvidence(
                sequence: 1,
                kind: .screenChanged,
                timestamp: Date(timeIntervalSince1970: 1),
                notificationData: .none,
                associatedElement: .none
            ),
        ])
    }

    func evidence(_ trace: AccessibilityTrace) -> AccessibilityTraceEvidence {
        guard let evidence = AccessibilityTraceEvidence(trace: trace, completeness: .complete) else {
            preconditionFailure("test trace requires at least one capture")
        }
        return evidence
    }

}
