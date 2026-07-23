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
    case heistExecutionStepCount(Int)
    case none
}

enum ActionMethodProjection: Sendable, Equatable, CustomStringConvertible {
    case fence(TheFence.Command)
    case heist(HeistActionCommand)
    case result(ActionMethod)

    var rawValue: String {
        switch self {
        case .fence(let command):
            return command.rawValue
        case .heist(let command):
            return command.wireType.rawValue
        case .result(let method):
            return method.rawValue
        }
    }

    var description: String { rawValue }
}

struct ActionProjection: Sendable {
    let actionMethod: ActionMethodProjection
    let result: ActionResult
    private let surfacedExpectation: ExpectationResult?
    private let announcementOverride: String?
    private let expectationHint: String?
    private let profile: ProjectionProfile
    let publicContext: PublicActionResultContext

    init(
        actionMethod: ActionMethodProjection,
        result: ActionResult,
        expectation: ExpectationResult? = nil,
        announcementOverride: String? = nil,
        expectationHint: String? = nil,
        profile: ProjectionProfile,
        publicContext: PublicActionResultContext = .standaloneAction
    ) {
        self.actionMethod = actionMethod
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
        case .heist(let result):
            return result.map { .heistExecutionStepCount($0.steps.count) } ?? .none
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
             .scrollToEdge,
             .wait:
            return .none
        }
    }

    var delta: DeltaProjection? {
        result.traceEvidence.flatMap {
            DeltaProjection(
                trace: $0.trace,
                isComplete: $0.isComplete,
                profile: profile,
                includeScreenInterface: true
            )
        }
    }

    var screenName: String? {
        result.accessibilityTrace?.endpointScreenName
    }

    var screenId: String? {
        result.accessibilityTrace?.endpointScreenId
    }

    var failure: ActionFailureProjection? {
        result.diagnosticFailureProjection(fallbackMessage: actionMethod.rawValue)
    }

    var expectation: ExpectationProjection? {
        surfacedExpectation.map {
            ExpectationProjection(result: $0, hint: expectationHint)
        }
    }

    var incompleteSettlement: ActionSettlementEvidence? {
        guard let settlement = result.evidence.settlement, !settlement.settled else { return nil }
        return settlement
    }

    var activationTrace: ActivationTrace? { result.activationTrace }

    var timing: ActionPerformanceTiming? { result.timing }

    var omitted: ActionResultOmissionsProjection? {
        publicContext.includesOmissions ? ActionResultOmissionsProjection(result: result) : nil
    }
}

struct ActionResultOmissionsProjection: Encodable, Sendable {
    let accessibilityTrace: ProjectionOmission?
    let subjectEvidence: ProjectionOmission?

    init(result: ActionResult) {
        accessibilityTrace = result.accessibilityTrace.map {
            ProjectionOmission(
                reason: .rawAccessibilityTrace,
                projectedAs: "delta",
                omittedCount: $0.captures.count
            )
        }
        subjectEvidence = result.subjectEvidence.map { _ in
            ProjectionOmission(
                reason: .rawSubjectEvidence,
                projectedAs: nil,
                omittedCount: nil
            )
        }
    }

    var isEmpty: Bool {
        accessibilityTrace == nil && subjectEvidence == nil
    }
}

struct ProjectionOmission: Encodable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case reason, projectedAs, omittedCount
    }

    let reason: ProjectionOmissionReason
    let projectedAs: String?
    let omittedCount: Int?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reason.rawValue, forKey: .reason)
        try container.encodeIfPresent(projectedAs, forKey: .projectedAs)
        try container.encodeIfPresent(omittedCount, forKey: .omittedCount)
    }
}
