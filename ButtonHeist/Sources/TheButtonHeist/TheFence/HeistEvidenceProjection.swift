import ThePlans
import TheScore

enum HeistReportEvidenceProjection: Sendable {
    case action(HeistActionEvidenceProjection)
    case wait(HeistWaitEvidenceProjection)
    case caseSelection(HeistCaseSelectionEvidenceProjection)
    case forEachString(HeistForEachStringEvidenceProjection)
    case forEachElement(HeistForEachElementEvidenceProjection)
    case repeatUntil(HeistRepeatUntilEvidenceProjection)
    case invocation(HeistInvocationEvidenceProjection)
    case warning(HeistWarningEvidenceProjection)

    init?(node: HeistExecutionEvidenceNode, profile: ProjectionProfile) {
        guard let evidence = node.step.evidence else { return nil }
        switch evidence {
        case .action(let evidence):
            self = .action(HeistActionEvidenceProjection(evidence: evidence, profile: profile))
        case .wait(let evidence):
            self = .wait(HeistWaitEvidenceProjection(evidence: evidence, profile: profile))
        case .caseSelection(let evidence):
            self = .caseSelection(HeistCaseSelectionEvidenceProjection(evidence: evidence, profile: profile))
        case .forEachString(let evidence):
            self = .forEachString(HeistForEachStringEvidenceProjection(evidence: evidence))
        case .forEachElement(let evidence):
            self = .forEachElement(HeistForEachElementEvidenceProjection(evidence: evidence))
        case .repeatUntil(let evidence):
            self = .repeatUntil(HeistRepeatUntilEvidenceProjection(evidence: evidence, profile: profile))
        case .invocation(let evidence):
            self = .invocation(HeistInvocationEvidenceProjection(evidence: evidence, profile: profile))
        case .warning(let warning):
            self = .warning(HeistWarningEvidenceProjection(warning: warning))
        }
    }

    var warning: HeistWarningEvidenceProjection? {
        guard case .warning(let warning) = self else { return nil }
        return warning
    }

    /// Delta from the result that contributes to this node's trace. Action and
    /// predicate evidence already project that result through `ActionProjection`;
    /// report rows must reuse its delta instead of rebuilding it from the raw trace.
    var traceDelta: DeltaProjection? {
        switch self {
        case .action(let projection):
            switch projection.evidence {
            case .commandResolutionFailure:
                return nil
            case .dispatch(let result, _):
                return result.delta
            case .expectation(_, let expectationResult, _, _):
                return expectationResult.delta
            }
        case .wait(let projection):
            return projection.result.delta
        case .repeatUntil(let projection):
            return projection.result?.delta
        case .invocation(let projection):
            return projection.expectationResult?.delta ?? projection.expectationEvidence?.result.delta
        case .caseSelection, .forEachString, .forEachElement, .warning:
            return nil
        }
    }
}

struct HeistActionEvidenceProjection: Sendable {
    private let actionEvidence: HeistActionEvidence
    private let profile: ProjectionProfile

    init(evidence: HeistActionEvidence, profile: ProjectionProfile) {
        actionEvidence = evidence
        self.profile = profile
    }

    var command: HeistActionCommandType? {
        actionEvidence.command?.wireType
    }

    var target: AccessibilityTarget? {
        actionEvidence.command?.reportTarget
    }

    var evidence: HeistActionResultEvidenceProjection {
        HeistActionResultEvidenceProjection(
            evidence: actionEvidence,
            profile: profile
        )
    }
}

enum HeistActionResultEvidenceProjection: Sendable {
    case commandResolutionFailure(warning: HeistActionWarning?)
    case dispatch(result: ActionProjection, warning: HeistActionWarning?)
    case expectation(
        dispatchResult: ActionProjection,
        expectationResult: ActionProjection,
        expectation: ExpectationProjection,
        warning: HeistActionWarning?
    )

    init(
        evidence: HeistActionEvidence,
        profile: ProjectionProfile
    ) {
        switch evidence {
        case .commandResolutionFailure:
            self = .commandResolutionFailure(warning: nil)
        case .dispatch(let command, let dispatchResult, let warning):
            self = .dispatch(
                result: ActionProjection(
                    actionMethod: .heist(command),
                    result: dispatchResult,
                    profile: profile,
                    includeOmissions: true
                ),
                warning: warning
            )
        case .commandlessDispatch(let dispatchResult):
            self = .dispatch(
                result: ActionProjection(
                    actionMethod: .result(dispatchResult.method),
                    result: dispatchResult,
                    profile: profile,
                    includeOmissions: true
                ),
                warning: nil
            )
        case .expectation(let command, let dispatchResult, let expectationResult, let expectation, let warning):
            self = .expectation(
                dispatchResult: ActionProjection(
                    actionMethod: .heist(command),
                    result: dispatchResult,
                    profile: profile,
                    includeOmissions: true
                ),
                expectationResult: ActionProjection(
                    actionMethod: .result(expectationResult.method),
                    result: expectationResult,
                    profile: profile,
                    includeOmissions: true
                ),
                expectation: ExpectationProjection(result: expectation),
                warning: warning
            )
        }
    }
}

struct HeistWaitEvidenceProjection: Sendable {
    let outcome: HeistPredicateEvidenceOutcome
    let result: ActionProjection
    let expectation: ExpectationProjection
    let baselineSummary: String?
    let finalSummary: String?

    init(evidence: HeistWaitEvidence, profile: ProjectionProfile) {
        outcome = evidence.outcome
        result = ActionProjection(
            actionMethod: .result(evidence.actionResult.method),
            result: evidence.actionResult,
            profile: profile,
            includeOmissions: true
        )
        expectation = ExpectationProjection(result: evidence.expectation)
        baselineSummary = evidence.baselineSummary
        finalSummary = evidence.finalSummary
    }
}

struct HeistCaseSelectionEvidenceProjection: Sendable {
    let outcome: HeistCaseSelectionOutcome
    let elapsedMs: Int
    let timeout: Double?
    let lastObservedSummary: String?
    let caseCount: Int
    let cases: [HeistCaseMatchProjection]
    let omittedCaseCount: Int?

    init(evidence: HeistCaseSelectionEvidence, profile: ProjectionProfile) {
        let selection = evidence.selection
        outcome = selection.outcome
        elapsedMs = selection.elapsedMs
        timeout = selection.timeout
        lastObservedSummary = selection.lastObservedSummary
        caseCount = selection.cases.count
        let visibleCases = Array(selection.cases.prefix(profile.limits.caseResults))
        cases = visibleCases.map(HeistCaseMatchProjection.init(match:))
        let omitted = selection.cases.count - visibleCases.count
        omittedCaseCount = omitted > 0 ? omitted : nil
    }
}

struct HeistCaseMatchProjection: Sendable {
    let predicate: AccessibilityPredicate<RootContext>
    let met: Bool
    let actual: String?

    init(match: HeistCaseMatchResult) {
        predicate = match.predicate
        met = match.result.met
        actual = match.result.actual
    }
}

struct HeistForEachStringEvidenceProjection: Sendable {
    let parameter: HeistReferenceName
    let count: Int
    let iterationCount: Int
    let iterationOrdinal: Int?
    let value: String?
    let failureReason: String?

    init(evidence: HeistForEachStringEvidence) {
        parameter = evidence.parameter
        count = evidence.count
        iterationCount = evidence.iterationCount
        iterationOrdinal = evidence.iterationOrdinal
        value = evidence.value
        failureReason = evidence.failureReason
    }
}

struct HeistForEachElementEvidenceProjection: Sendable {
    let parameter: HeistReferenceName
    let matching: ElementPredicate
    let limit: Int
    let matchedCount: Int
    let iterationCount: Int
    let iterationOrdinal: Int?
    let targetOrdinal: Int?
    let targetSummary: String?
    let failureReason: String?

    init(evidence: HeistForEachElementEvidence) {
        parameter = evidence.parameter
        matching = evidence.matching
        limit = evidence.limit
        matchedCount = evidence.matchedCount
        iterationCount = evidence.iterationCount
        iterationOrdinal = evidence.iterationOrdinal
        targetOrdinal = evidence.targetOrdinal
        targetSummary = evidence.targetSummary
        failureReason = evidence.failureReason
    }
}

struct HeistRepeatUntilEvidenceProjection: Sendable {
    let outcome: HeistPredicateEvidenceOutcome
    let predicate: AccessibilityPredicate<RootContext>
    let timeout: Double
    let iterationCount: Int
    let iterationOrdinal: Int?
    let expectation: ExpectationProjection
    let result: ActionProjection?
    let lastObservedSummary: String?
    let failureReason: String?

    init(evidence: HeistRepeatUntilEvidence, profile: ProjectionProfile) {
        outcome = evidence.outcome
        predicate = evidence.predicate
        timeout = evidence.timeout
        iterationCount = evidence.iterationCount
        iterationOrdinal = evidence.iterationOrdinal
        expectation = ExpectationProjection(result: evidence.expectation)
        result = evidence.actionResult.map {
            ActionProjection(actionMethod: .result($0.method), result: $0, profile: profile, includeOmissions: true)
        }
        lastObservedSummary = evidence.lastObservedSummary
        failureReason = evidence.failureReason
    }
}

struct HeistInvocationEvidenceProjection: Sendable {
    let capability: String?
    let name: String?
    let argument: String?
    let childFailedPath: String?
    let expectationResult: ActionProjection?
    let expectation: ExpectationProjection?
    let expectationEvidence: HeistWaitEvidenceProjection?

    init(evidence: HeistInvocationEvidence, profile: ProjectionProfile) {
        capability = evidence.invocation?.capabilityName
        name = evidence.name
        argument = evidence.argument
        childFailedPath = evidence.childFailedPath
        expectationResult = evidence.expectationActionResult.map {
            ActionProjection(actionMethod: .result($0.method), result: $0, profile: profile, includeOmissions: true)
        }
        expectation = evidence.expectation.map { ExpectationProjection(result: $0) }
        expectationEvidence = evidence.waitEvidence.map {
            HeistWaitEvidenceProjection(evidence: $0, profile: profile)
        }
    }
}

struct HeistWarningEvidenceProjection: Sendable {
    let path: String
    let message: String

    init(warning: HeistExecutionWarning) {
        path = warning.path
        message = warning.message
    }
}
