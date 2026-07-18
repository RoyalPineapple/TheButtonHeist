#if canImport(UIKit)
#if DEBUG
import UIKit

import AccessibilitySnapshotParser
import ThePlans
import TheScore

struct ActivationDispatchEvidence: Sendable {
    let outcome: AccessibilityActionDispatcher.ActivateOutcome
    let activationPoint: CGPoint
}

enum ActivationRefreshResult {
    case resolved(ElementInflation.InflatedElementTarget)
    case failure(TheSafecracker.ActionDispatchOutcome)
}

struct ActivationPolicy<PreparedDispatch: Sendable> {
    var accessibilityActivate: @MainActor (
        TheStash.LiveActionTarget
    ) -> Result<ActivationDispatchEvidence, TheStash.LiveTargetStaleness<HeistId>>
    var refreshAndResolve: @MainActor () async -> ActivationRefreshResult
    var prepareActivationPointDispatch: @MainActor (CGPoint) -> PreparedDispatch?
    var completeActivationPointDispatch: @MainActor (PreparedDispatch) async -> Bool
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

        let activateOutcome: AccessibilityActionDispatcher.ActivateOutcome
        let activationPoint: CGPoint
        switch accessibilityActivate(refreshedLiveTarget) {
        case .success(let dispatch):
            activateOutcome = dispatch.outcome
            activationPoint = dispatch.activationPoint
        case .failure(let staleness):
            return .failure(
                .activate,
                message: staleness.message,
                activationTrace: ActivationTrace(.refreshFailed),
                failureKind: .targetUnavailable
            )
        }
        if activateOutcome == .success {
            showFingerprint(activationPoint)
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

        guard let activationX = try? FiniteCoordinate(validating: Double(activationPoint.x)),
              let activationY = try? FiniteCoordinate(validating: Double(activationPoint.y)) else {
            return .failure(
                .activate,
                message: "activate failed: the refreshed accessibility activation point was not finite",
                subjectEvidence: subjectEvidence
            )
        }
        let admittedActivationPoint = ScreenPoint(x: activationX, y: activationY)

        let preparedDispatch = prepareActivationPointDispatch(activationPoint)
        let tapActivationSucceeded = if let preparedDispatch {
            await completeActivationPointDispatch(preparedDispatch)
        } else {
            false
        }
        let trace = ActivationTrace(.activationPointFallback(
            axActivateReturned: activateOutcome.axActivateReturned,
            tapActivationPoint: admittedActivationPoint,
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
