import ThePlans
import TheScore

struct ExpectationProjection: Sendable {
    let met: Bool
    let actual: String?
    let expected: AccessibilityPredicate<RootContext>?
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
    private let expectationHint: String?
    private let profile: ProjectionProfile
    private let includesOmissions: Bool

    init(
        actionMethod: ActionMethodProjection,
        result: ActionResult,
        expectation: ExpectationResult? = nil,
        expectationHint: String? = nil,
        profile: ProjectionProfile,
        includeOmissions: Bool = false
    ) {
        self.actionMethod = actionMethod
        self.result = result
        self.surfacedExpectation = result.outcome.isSuccess ? expectation : nil
        self.expectationHint = expectationHint
        self.profile = profile
        self.includesOmissions = includeOmissions
    }

    var status: PublicResponseStatus {
        result.publicStatus(expectation: surfacedExpectation)
    }

    var message: String? { result.message }

    var announcement: String? { result.announcement }

    var payload: ActionPayloadProjection {
        switch result.payload {
        case .value(let value):
            return .value(value)
        case .rotor(let rotor):
            return .rotor(rotor)
        case .screenshot(let screen):
            return .screenshot(width: screen.width, height: screen.height)
        case .heistExecution(let heist):
            return .heistExecutionStepCount(heist.steps.count)
        case .none:
            return .none
        }
    }

    var delta: DeltaProjection? {
        result.accessibilityTrace.flatMap {
            DeltaProjection(
                trace: $0,
                isComplete: result.settled != false,
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

    var activationTrace: ActivationTrace? { result.activationTrace }

    var timing: ActionPerformanceTiming? { result.timing }

    var omitted: ActionResultOmissionsProjection? {
        includesOmissions ? ActionResultOmissionsProjection(result: result) : nil
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
