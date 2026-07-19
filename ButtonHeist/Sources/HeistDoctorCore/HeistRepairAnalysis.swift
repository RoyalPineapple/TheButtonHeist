import ThePlans
import TheScore

enum HeistRepairAnalysis {
    case ineligible(HeistRepairRefusalReason)
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
        let oldResolved: RepairScreen.Element
        switch lastScreen.resolve(request.lastSuccess.target) {
        case .resolved(let element, _):
            oldResolved = element
        case .unsupportedTarget(let kind):
            return .ineligible(kind.refusalReason)
        case .notFound, .ambiguous:
            return .ineligible(.oldTargetDidNotResolveExactlyOnce)
        }

        let actionRequirement = RepairActionRequirement(command: request.currentFailure.command)
        let currentResolution = currentScreen.resolve(request.lastSuccess.target)
        let failureKind: HeistRepairFailureKind
        let preferredCandidates: Set<PredicateSelectionElementId>

        switch currentResolution {
        case .resolved(let element, _):
            guard actionRequirement.isKnown,
                  !actionRequirement.isSupported(by: element.element)
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

        case .unsupportedTarget(let kind):
            return .ineligible(kind.refusalReason)
        }

        let rankedCandidates = RepairCandidateGenerator.rankedSuccessorCandidates(
            oldResolved: oldResolved,
            currentScreen: currentScreen,
            preferredCandidates: preferredCandidates,
            failureKind: failureKind,
            actionRequirement: actionRequirement,
            lastSuccess: request.lastSuccess,
            currentFailure: request.currentFailure
        )

        return .eligible(HeistEligibleRepairAnalysis(
            currentScreen: currentScreen,
            oldResolved: oldResolved,
            currentResolution: currentResolution,
            actionRequirement: actionRequirement,
            failureKind: failureKind,
            preferredCandidates: preferredCandidates,
            rankedCandidates: rankedCandidates
        ))
    }
}

private extension UnsupportedRepairTargetKind {
    var refusalReason: HeistRepairRefusalReason {
        switch self {
        case .container:
            return .containerTargetUnsupported
        case .reference:
            return .targetReferenceUnsupported
        case .unresolvedExpression:
            return .unresolvedTargetExpression
        }
    }
}

struct HeistEligibleRepairAnalysis {
    let currentScreen: RepairScreen
    let oldResolved: RepairScreen.Element
    let currentResolution: RepairTargetResolution
    let actionRequirement: RepairActionRequirement
    let failureKind: HeistRepairFailureKind
    let preferredCandidates: Set<PredicateSelectionElementId>
    let rankedCandidates: [ScoredCandidate]
}
