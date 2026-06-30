import ThePlans
import TheScore

enum HeistRepairAnalysis {
    case ineligible(HeistRepairIneligibility)
    case eligible(HeistEligibleRepairAnalysis)

    static func analyze(_ request: HeistRepairRequest) -> HeistRepairAnalysis {
        guard request.lastSuccess.stepPath == request.currentFailure.stepPath else {
            return .ineligible(.differentStepPaths)
        }
        guard repairFingerprintsAreCompatible(
            request.lastSuccess.heistFingerprint,
            request.currentFailure.heistFingerprint
        ) else {
            return .ineligible(.incompatibleHeistFingerprints)
        }

        let lastScreen = RepairScreen(interface: request.lastSuccess.beforeSnapshot)
        let currentScreen = RepairScreen(interface: request.currentFailure.beforeSnapshot)
        guard case .resolved(let oldResolved, _) = lastScreen.resolve(request.lastSuccess.target) else {
            return .ineligible(.oldTargetDidNotResolveExactlyOnce)
        }

        let actionFamily = RepairActionFamily(
            actionIdentity: request.currentFailure.actionIdentity
        )
        let currentResolution = currentScreen.resolve(request.lastSuccess.target)
        let failureKind: HeistRepairFailureKind
        let preferredCandidates: Set<PredicateSelectionElementId>

        switch currentResolution {
        case .resolved(let element, _):
            guard actionFamily.isKnown,
                  !actionFamily.isSupported(by: element.element)
            else {
                return .ineligible(.oldTargetStillResolvesAndSupportsRequestedAction)
            }
            failureKind = .wrongCapability
            preferredCandidates = []

        case .notFound:
            failureKind = .missingTarget
            preferredCandidates = []

        case .ambiguous(let matches, _):
            failureKind = .ambiguousTarget
            preferredCandidates = Set(matches.map(\.id))
        }

        let rankedCandidates = RepairCandidateGenerator.rankedSuccessorCandidates(
            oldResolved: oldResolved,
            currentScreen: currentScreen,
            preferredCandidates: preferredCandidates,
            failureKind: failureKind,
            actionFamily: actionFamily,
            lastSuccess: request.lastSuccess,
            currentFailure: request.currentFailure
        )

        return .eligible(HeistEligibleRepairAnalysis(
            lastScreen: lastScreen,
            currentScreen: currentScreen,
            oldResolved: oldResolved,
            currentResolution: currentResolution,
            actionFamily: actionFamily,
            failureKind: failureKind,
            preferredCandidates: preferredCandidates,
            rankedCandidates: rankedCandidates
        ))
    }
}

enum HeistRepairIneligibility {
    case differentStepPaths
    case incompatibleHeistFingerprints
    case oldTargetDidNotResolveExactlyOnce
    case oldTargetStillResolvesAndSupportsRequestedAction
}

struct HeistEligibleRepairAnalysis {
    let lastScreen: RepairScreen
    let currentScreen: RepairScreen
    let oldResolved: RepairScreen.Element
    let currentResolution: RepairTargetResolution
    let actionFamily: RepairActionFamily
    let failureKind: HeistRepairFailureKind
    let preferredCandidates: Set<PredicateSelectionElementId>
    let rankedCandidates: [ScoredCandidate]
}
