import ThePlans
import TheScore

enum HeistReportEvidenceProjection: Sendable {
    case action(HeistActionEvidenceProjection)
    case wait(HeistWaitEvidenceProjection)
    case caseSelection(HeistCaseSelectionEvidenceProjection)
    case forEachString(HeistForEachStringEvidence)
    case forEachElement(HeistForEachElementEvidence)
    case repeatUntil(HeistRepeatUntilEvidenceProjection)
    case invocation(HeistInvocationEvidenceProjection)
    case warning(HeistExecutionWarning)

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
            self = .forEachString(evidence)
        case .forEachElement(let evidence):
            self = .forEachElement(evidence)
        case .repeatUntil(let evidence):
            self = .repeatUntil(HeistRepeatUntilEvidenceProjection(evidence: evidence, profile: profile))
        case .invocation(let evidence):
            self = .invocation(HeistInvocationEvidenceProjection(evidence: evidence, profile: profile))
        case .warning(let warning):
            self = .warning(warning)
        }
    }

    var warning: HeistExecutionWarning? {
        guard case .warning(let warning) = self else { return nil }
        return warning
    }

    /// Delta from the result that contributes to this node's trace. Action and
    /// predicate evidence already project that result through `ActionProjection`;
    /// report rows must reuse its delta instead of rebuilding it from the raw trace.
    var traceDelta: DeltaProjection? {
        switch self {
        case .action(let projection):
            return projection.traceDelta
        case .wait(let projection):
            return projection.result.delta
        case .repeatUntil(let projection):
            return projection.result?.delta
        case .invocation(let projection):
            return projection.expectation?.result.delta
        case .caseSelection, .forEachString, .forEachElement, .warning:
            return nil
        }
    }
}

enum HeistActionEvidenceProjection: Sendable {
    case commandResolutionFailure(command: HeistActionCommand)
    case dispatch(command: HeistActionCommand, result: ActionProjection)
    case commandlessDispatch(result: ActionProjection)
    case expectation(
        command: HeistActionCommand,
        dispatchResult: ActionProjection,
        expectationResult: ActionProjection,
        expectation: ExpectationProjection
    )

    init(evidence: HeistActionEvidence, profile: ProjectionProfile) {
        switch evidence {
        case .commandResolutionFailure(let command):
            self = .commandResolutionFailure(command: command)
        case .dispatch(let command, let dispatchResult):
            self = .dispatch(
                command: command,
                result: ActionProjection(
                    actionMethod: .heist(command),
                    result: dispatchResult,
                    profile: profile,
                    includeOmissions: true
                )
            )
        case .commandlessDispatch(let dispatchResult):
            self = .commandlessDispatch(
                result: ActionProjection(
                    actionMethod: .result(dispatchResult.method),
                    result: dispatchResult,
                    profile: profile,
                    includeOmissions: true
                )
            )
        case .expectation(let command, let dispatchResult, let expectationResult, let expectation):
            self = .expectation(
                command: command,
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
                expectation: ExpectationProjection(result: expectation)
            )
        }
    }

    var command: HeistActionCommandType? {
        switch self {
        case .commandResolutionFailure(let command),
             .dispatch(let command, _),
             .expectation(let command, _, _, _):
            return command.wireType
        case .commandlessDispatch:
            return nil
        }
    }

    var target: AccessibilityTarget? {
        switch self {
        case .commandResolutionFailure(let command),
             .dispatch(let command, _),
             .expectation(let command, _, _, _):
            return command.reportTarget
        case .commandlessDispatch:
            return nil
        }
    }

    var traceDelta: DeltaProjection? {
        switch self {
        case .commandResolutionFailure:
            return nil
        case .dispatch(_, let result), .commandlessDispatch(let result):
            return result.delta
        case .expectation(_, _, let expectationResult, _):
            return expectationResult.delta
        }
    }
}

struct HeistWaitEvidenceProjection: Sendable {
    let evidence: HeistWaitEvidence
    let result: ActionProjection
    let expectation: ExpectationProjection

    init(evidence: HeistWaitEvidence, profile: ProjectionProfile) {
        self.evidence = evidence
        result = ActionProjection(
            actionMethod: .result(evidence.actionResult.method),
            result: evidence.actionResult,
            profile: profile,
            includeOmissions: true
        )
        expectation = ExpectationProjection(result: evidence.expectation)
    }
}

struct HeistCaseSelectionEvidenceProjection: Sendable {
    let evidence: HeistCaseSelectionEvidence
    let visibleCases: [HeistCaseMatchResult]
    let omittedCaseCount: Int?

    init(evidence: HeistCaseSelectionEvidence, profile: ProjectionProfile) {
        self.evidence = evidence
        let selection = evidence.selection
        visibleCases = Array(selection.cases.prefix(profile.limits.caseResults))
        let omitted = selection.cases.count - visibleCases.count
        omittedCaseCount = omitted > 0 ? omitted : nil
    }
}

struct HeistRepeatUntilEvidenceProjection: Sendable {
    let evidence: HeistRepeatUntilEvidence
    let expectation: ExpectationProjection
    let result: ActionProjection?

    init(evidence: HeistRepeatUntilEvidence, profile: ProjectionProfile) {
        self.evidence = evidence
        expectation = ExpectationProjection(result: evidence.expectation)
        result = evidence.actionResult.map {
            ActionProjection(actionMethod: .result($0.method), result: $0, profile: profile, includeOmissions: true)
        }
    }
}

struct HeistInvocationEvidenceProjection: Sendable {
    let evidence: HeistInvocationEvidence
    let expectation: HeistInvocationExpectationProjection?

    init(evidence: HeistInvocationEvidence, profile: ProjectionProfile) {
        self.evidence = evidence
        switch evidence {
        case .heist, .invocation(_, _, _, .childFailed):
            expectation = nil
        case .invocation(_, _, _, .completed(let evidence)):
            expectation = evidence.map {
                HeistInvocationExpectationProjection(evidence: $0, profile: profile)
            }
        }
    }
}

enum HeistInvocationExpectationProjection: Sendable {
    case result(ActionProjection, ExpectationProjection)
    case wait(HeistWaitEvidenceProjection)

    init(
        evidence: HeistInvocationEvidence.InvocationExpectationEvidence,
        profile: ProjectionProfile
    ) {
        switch evidence {
        case .result(let actionResult, let expectation):
            self = .result(
                ActionProjection(
                    actionMethod: .result(actionResult.method),
                    result: actionResult,
                    profile: profile,
                    includeOmissions: true
                ),
                ExpectationProjection(result: expectation)
            )
        case .wait(let evidence):
            self = .wait(HeistWaitEvidenceProjection(evidence: evidence, profile: profile))
        }
    }

    var result: ActionProjection {
        switch self {
        case .result(let result, _):
            return result
        case .wait(let evidence):
            return evidence.result
        }
    }

    var expectation: ExpectationProjection {
        switch self {
        case .result(_, let expectation):
            return expectation
        case .wait(let evidence):
            return evidence.expectation
        }
    }

    var waitEvidence: HeistWaitEvidenceProjection? {
        guard case .wait(let evidence) = self else {
            return nil
        }
        return evidence
    }
}
