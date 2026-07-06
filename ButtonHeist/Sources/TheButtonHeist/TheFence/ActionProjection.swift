import ThePlans
import TheScore

struct ExpectationProjection: Sendable {
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
    let status: PublicResponseStatus
    let actionMethod: ActionMethodProjection
    let message: String?
    let announcement: String?
    let payload: ActionPayloadProjection
    let delta: DeltaProjection?
    let screenName: String?
    let screenId: String?
    let failure: ActionFailureProjection?
    let expectation: ExpectationProjection?
    let activationTrace: ActivationTrace?
    let timing: ActionPerformanceTiming?
    let omitted: ActionResultOmissionsProjection?

    init(
        actionMethod: ActionMethodProjection,
        result: ActionResult,
        expectation: ExpectationResult? = nil,
        expectationHint: String? = nil,
        profile: ProjectionProfile,
        includeOmissions: Bool = false
    ) {
        let surfacedExpectation = result.success ? expectation : nil
        status = result.publicStatus(expectation: surfacedExpectation)
        self.actionMethod = actionMethod
        message = result.message
        announcement = result.announcement
        switch result.payload {
        case .value(let value):
            payload = .value(value)
        case .rotor(let rotor):
            payload = .rotor(rotor)
        case .screenshot(let screen):
            payload = .screenshot(width: screen.width, height: screen.height)
        case .heistExecution(let heist):
            payload = .heistExecutionStepCount(heist.steps.count)
        case .none:
            payload = .none
        }
        delta = result.accessibilityTrace?.endpointDelta.map {
            DeltaProjection(delta: $0, profile: profile, includeScreenInterface: true)
        }
        screenName = result.accessibilityTrace?.endpointScreenName
        screenId = result.accessibilityTrace?.endpointScreenId
        failure = result.diagnosticFailureProjection(fallbackMessage: actionMethod.rawValue)
        self.expectation = surfacedExpectation.map {
            ExpectationProjection(result: $0, hint: expectationHint)
        }
        activationTrace = result.activationTrace
        timing = result.timing
        omitted = includeOmissions ? ActionResultOmissionsProjection(result: result) : nil
    }
}

struct ActionResultOmissionsProjection: Sendable {
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

struct ProjectionOmission: Sendable {
    let reason: ProjectionOmissionReason
    let projectedAs: String?
    let omittedCount: Int?
}
