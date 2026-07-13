#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import ThePlans
import TheScore

/// Ordered activation delivery pipeline for `activate`.
///
/// ButtonHeist treats accessibility as the interaction contract. `activate`
/// refreshes semantic resolution and live geometry before asking UIKit to
/// perform the element's primary accessibility activation with
/// `accessibilityActivate()`. When UIKit declines/defaults, ButtonHeist still
/// delivers the same `activate` command by dispatching at the fresh accessibility
/// activation point.
struct ActivationPolicy {

    enum RefreshResult {
        case resolved(ElementInflation.InflatedElementTarget)
        case failure(TheSafecracker.ActionDispatchOutcome)
    }

    var accessibilityActivate: @MainActor (TheStash.LiveActionTarget) -> AccessibilityActionDispatcher.ActivateOutcome
    var refreshAndResolve: @MainActor () async -> RefreshResult
    var activationPointDispatch: @MainActor (CGPoint) async -> Bool
    var showFingerprint: @MainActor (CGPoint) -> Void
    var textEntryActivationFailure: @MainActor (InterfaceTree.Element, ActivationTrace) async -> TheSafecracker.ActionDispatchOutcome?

    @MainActor
    func apply(to _: TheStash.LiveActionTarget) async -> TheSafecracker.ActionDispatchOutcome {
        let refreshedTarget: ElementInflation.InflatedElementTarget
        switch await refreshAndResolve() {
        case .resolved(let target):
            refreshedTarget = target
        case .failure(let result):
            return result.withActivationTrace(ActivationTrace(.refreshFailed))
        }
        let treeElement = refreshedTarget.treeElement
        let refreshedLiveTarget = refreshedTarget.liveTarget
        let subjectEvidence = refreshedTarget.subjectEvidence(source: .resolvedSemanticTarget)

        let activateOutcome = accessibilityActivate(refreshedLiveTarget)
        if activateOutcome == .success {
            showFingerprint(refreshedLiveTarget.activationPoint)
            let trace = ActivationTrace(.accessibilityActivate)
            if let failure = await textEntryActivationFailure(treeElement, trace) {
                return failure.withSubjectEvidence(subjectEvidence)
            }
            return .success(
                method: .activate,
                subjectEvidence: subjectEvidence,
                activationTrace: trace
            )
        }

        let activationPoint = refreshedLiveTarget.activationPoint
        let tapActivationSucceeded = await activationPointDispatch(activationPoint)
        let trace = ActivationTrace(.activationPointFallback(
            axActivateReturned: activateOutcome.axActivateReturned,
            tapActivationPoint: ScreenPoint(x: Double(activationPoint.x), y: Double(activationPoint.y)),
            tapActivationSucceeded: tapActivationSucceeded
        ))
        if tapActivationSucceeded {
            if let failure = await textEntryActivationFailure(treeElement, trace) {
                return failure.withSubjectEvidence(subjectEvidence)
            }
            return .success(
                method: .activate,
                subjectEvidence: subjectEvidence,
                activationTrace: trace
            )
        }

        return .failure(
            .activate,
            message: activationFailureMessage(treeElement: treeElement, activateOutcome: activateOutcome),
            subjectEvidence: subjectEvidence,
            activationTrace: trace
        )
    }

    @MainActor
    private func activationFailureMessage(
        treeElement: InterfaceTree.Element,
        activateOutcome: AccessibilityActionDispatcher.ActivateOutcome
    ) -> String {
        let observed: String
        switch activateOutcome {
        case .success:
            observed = "unexpected success state"
        case .objectDeallocated:
            observed = "live target deallocated after semantic refresh"
        case .refused:
            observed = "accessibilityActivate() declined after semantic refresh"
        }
        return "activate failed: \(observed); activation-point dispatch was attempted at the fresh " +
            "accessibility activation point and did not complete for " +
            "\(ActionCapabilityDiagnostic.elementObservation(treeElement)); correction: target an element " +
            "with primary accessibility activation, or use an explicit mechanical gesture when the " +
            "test intent is viewport coordinate delivery"
    }
}

private extension AccessibilityActionDispatcher.ActivateOutcome {
    var axActivateReturned: Bool? {
        switch self {
        case .success: return true
        case .refused: return false
        case .objectDeallocated: return nil
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
