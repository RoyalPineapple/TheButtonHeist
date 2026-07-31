import ThePlans
import TheScore

struct ExpectationProjection: Encodable, Sendable {
    let met: Bool
    let actual: String?
    let expected: AccessibilityPredicate?
    let hint: String?

    init(result: ExpectationResult, hint: String? = nil) {
        met = result.met
        actual = result.actual
        expected = result.predicate
        self.hint = hint
    }
}

enum ActionPayloadProjection: Sendable {
    case value(String)
    case rotor(RotorResult)
    case screenshot(width: Double, height: Double)
    case none
}

struct ActionProjection: Sendable {
    let method: String
    let result: ActionResult
    private let surfacedExpectation: ExpectationResult?
    private let announcementOverride: String?
    private let expectationHint: String?
    private let profile: ProjectionProfile
    let publicContext: PublicActionResultContext

    init(
        method: String,
        result: ActionResult,
        expectation: ExpectationResult? = nil,
        announcementOverride: String? = nil,
        expectationHint: String? = nil,
        profile: ProjectionProfile,
        publicContext: PublicActionResultContext = .standaloneAction
    ) {
        self.method = method
        self.result = result
        self.surfacedExpectation = result.outcome.isSuccess ? expectation : nil
        self.announcementOverride = announcementOverride
        self.expectationHint = expectationHint
        self.profile = profile
        self.publicContext = publicContext
    }

    var status: PublicResponseStatus {
        result.publicStatus(expectation: surfacedExpectation)
    }

    var message: String? { result.message }

    var warning: HeistActionWarning? { result.warning }

    var announcement: String? {
        announcementOverride ?? surfacedExpectation?.matchedAnnouncement ?? result.announcement
    }

    var screenActionHandler: ScreenActionHandlerName? { result.screenActionHandler }

    var payload: ActionPayloadProjection {
        switch result.payload {
        case .typeText(let value), .setPasteboard(let value), .getPasteboard(let value):
            return value.map(ActionPayloadProjection.value) ?? .none
        case .rotor(let rotor):
            return rotor.map(ActionPayloadProjection.rotor) ?? .none
        case .screenshot(let screen):
            guard let screen else { return .none }
            return .screenshot(width: screen.width, height: screen.height)
        case .activate,
             .increment,
             .decrement,
             .dismiss,
             .magicTap,
             .oneFingerTap,
             .longPress,
             .swipe,
             .drag,
             .customAction,
             .editAction,
             .dismissKeyboard,
             .scroll,
             .scrollToVisible,
             .scrollToEdge:
            return .none
        }
    }

    var delta: DeltaProjection? {
        result.observationEvidence.flatMap {
            DeltaProjection(
                evidence: $0,
                profile: profile,
                includeScreenInterface: true
            )
        }
    }

    var screenName: String? {
        result.observationEvidence?.current.map {
            InterfaceSummary.screenDescription(for: $0.interface)
        }
    }

    var screenId: String? {
        result.observationEvidence?.current.flatMap {
            $0.context.screenId ?? InterfaceSummary.screenId(for: $0.interface)
        }
    }

    var failure: ActionFailureProjection? {
        result.diagnosticFailureProjection(fallbackMessage: method)
    }

    var expectation: ExpectationProjection? {
        surfacedExpectation.map {
            ExpectationProjection(result: $0, hint: expectationHint)
        }
    }

    var activationTrace: ActivationTrace? { result.activationTrace }

    var timing: ActionPerformanceTiming? { result.timing }

}
