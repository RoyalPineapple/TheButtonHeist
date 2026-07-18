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
    case warning(HeistExecutionWarning)

    init?(step: HeistExecutionStepResult, profile: ProjectionProfile) {
        switch step.kind {
        case .action:
            guard let command = step.actionCommand,
                  let evidence = step.actionEvidence else { return nil }
            self = .action(HeistActionEvidenceProjection(
                command: command,
                evidence: evidence,
                profile: profile
            ))
        case .wait:
            guard let evidence = step.waitEvidence else { return nil }
            self = .wait(HeistWaitEvidenceProjection(evidence: evidence, profile: profile))
        case .conditional:
            guard let evidence = step.caseSelectionEvidence else { return nil }
            self = .caseSelection(HeistCaseSelectionEvidenceProjection(evidence: evidence, profile: profile))
        case .forEachString:
            guard let declaration = step.forEachStringDeclaration,
                  let evidence = step.forEachStringEvidence else { return nil }
            self = .forEachString(.init(declaration: declaration, evidence: evidence))
        case .forEachElement:
            guard let declaration = step.forEachElementDeclaration,
                  let evidence = step.forEachElementEvidence else { return nil }
            self = .forEachElement(.init(declaration: declaration, evidence: evidence))
        case .forEachIteration:
            if let declaration = step.forEachStringDeclaration,
               let evidence = step.forEachStringEvidence {
                self = .forEachString(.init(declaration: declaration, evidence: evidence))
            } else if let declaration = step.forEachElementDeclaration,
                      let evidence = step.forEachElementEvidence {
                self = .forEachElement(.init(declaration: declaration, evidence: evidence))
            } else {
                return nil
            }
        case .repeatUntil, .repeatUntilIteration:
            guard let declaration = step.repeatUntilDeclaration,
                  let evidence = step.repeatUntilEvidence else { return nil }
            self = .repeatUntil(HeistRepeatUntilEvidenceProjection(
                declaration: declaration,
                evidence: evidence,
                profile: profile
            ))
        case .invoke:
            guard let invocation = step.invocation,
                  let evidence = step.invocationEvidence else { return nil }
            self = .invocation(HeistInvocationEvidenceProjection(
                invocation: invocation,
                evidence: evidence,
                profile: profile
            ))
        case .warn:
            guard let warning = step.warningEvidence else { return nil }
            self = .warning(warning)
        case .fail, .heist:
            return nil
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
    case expectation(
        command: HeistActionCommand,
        dispatchResult: ActionProjection,
        expectationResult: ActionProjection,
        expectation: ExpectationProjection
    )

    init(
        command: HeistActionCommand,
        evidence: HeistActionEvidence,
        profile: ProjectionProfile
    ) {
        switch evidence {
        case .commandResolutionFailure:
            self = .commandResolutionFailure(command: command)
        case .dispatch(let dispatchResult):
            self = .dispatch(
                command: command,
                result: ActionProjection(
                    actionMethod: .heist(command),
                    result: dispatchResult,
                    profile: profile,
                    includeOmissions: true
                )
            )
        case .expectation(let dispatchResult, let expectationResult, let expectation):
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
        }
    }

    var target: AccessibilityTarget? {
        switch self {
        case .commandResolutionFailure(let command),
             .dispatch(let command, _),
             .expectation(let command, _, _, _):
            return command.reportTarget
        }
    }

    var traceDelta: DeltaProjection? {
        switch self {
        case .commandResolutionFailure:
            return nil
        case .dispatch(_, let result):
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
    let declaration: HeistRepeatUntilDeclaration
    let evidence: HeistRepeatUntilEvidence
    let expectation: ExpectationProjection
    let result: ActionProjection?

    init(
        declaration: HeistRepeatUntilDeclaration,
        evidence: HeistRepeatUntilEvidence,
        profile: ProjectionProfile
    ) {
        self.declaration = declaration
        self.evidence = evidence
        expectation = ExpectationProjection(result: evidence.expectation)
        result = evidence.actionResult.map {
            ActionProjection(actionMethod: .result($0.method), result: $0, profile: profile, includeOmissions: true)
        }
    }
}

struct HeistForEachStringEvidenceProjection: Sendable {
    let declaration: HeistForEachStringDeclaration
    let evidence: HeistForEachStringEvidence
}

struct HeistForEachElementEvidenceProjection: Sendable {
    let declaration: HeistForEachElementDeclaration
    let evidence: HeistForEachElementEvidence
}

struct HeistInvocationEvidenceProjection: Sendable {
    let invocation: HeistInvocationStep
    let evidence: HeistInvocationEvidence
    let expectation: HeistInvocationExpectationProjection?

    init(
        invocation: HeistInvocationStep,
        evidence: HeistInvocationEvidence,
        profile: ProjectionProfile
    ) {
        self.invocation = invocation
        self.evidence = evidence
        switch evidence {
        case .childFailed:
            expectation = nil
        case .completed(let evidence):
            expectation = evidence.map {
                HeistInvocationExpectationProjection(evidence: $0, profile: profile)
            }
        }
    }

    var argumentSummary: String? {
        invocation.argument == .none ? nil : invocation.runHeistSummary
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
