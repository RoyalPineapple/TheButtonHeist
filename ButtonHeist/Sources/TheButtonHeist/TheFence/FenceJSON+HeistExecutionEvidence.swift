import ThePlans
import TheScore

struct PublicHeistReportEvidenceJSON: Encodable {
    private enum CodingKeys: String, CodingKey {
        case action, wait, caseSelection, forEachString, forEachElement, repeatUntil, invocation, warning
    }

    let evidence: HeistReport.Evidence
    let profile: ProjectionProfile

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch evidence {
        case .action(let command, let evidence):
            try container.encode(
                PublicHeistActionEvidenceJSON(command: command, evidence: evidence, profile: profile),
                forKey: .action
            )
        case .wait(let evidence):
            try container.encode(PublicHeistWaitEvidenceJSON(evidence: evidence, profile: profile), forKey: .wait)
        case .caseSelection(let evidence):
            try container.encode(
                PublicHeistCaseSelectionEvidenceJSON(evidence: evidence, profile: profile),
                forKey: .caseSelection
            )
        case .forEachString(let declaration, let evidence):
            try container.encode(
                PublicHeistForEachStringEvidenceJSON(declaration: declaration, evidence: evidence),
                forKey: .forEachString
            )
        case .forEachElement(let declaration, let evidence):
            try container.encode(
                PublicHeistForEachElementEvidenceJSON(declaration: declaration, evidence: evidence),
                forKey: .forEachElement
            )
        case .repeatUntil(let declaration, let evidence):
            try container.encode(
                PublicHeistRepeatUntilEvidenceJSON(declaration: declaration, evidence: evidence, profile: profile),
                forKey: .repeatUntil
            )
        case .invocation(let invocation, let evidence):
            try container.encode(
                PublicHeistInvocationEvidenceJSON(invocation: invocation, evidence: evidence, profile: profile),
                forKey: .invocation
            )
        case .warning(let warning):
            try container.encode(warning, forKey: .warning)
        }
    }
}

private struct PublicHeistActionEvidenceJSON: Encodable {
    private enum CodingKeys: String, CodingKey {
        case commandName, target, result, expectationResult, expectation
    }

    let command: HeistActionCommand
    let evidence: HeistActionEvidence
    let profile: ProjectionProfile

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command.wireType.rawValue, forKey: .commandName)
        try container.encodeIfPresent(command.reportTarget, forKey: .target)
        switch evidence {
        case .commandResolutionFailure:
            break
        case .dispatch(let result):
            try container.encode(PublicHeistOutput.action(result, method: .heist(command), profile: profile), forKey: .result)
        case .expectation(let result, let expectationResult, let expectation):
            try container.encode(PublicHeistOutput.action(result, method: .heist(command), profile: profile), forKey: .result)
            try container.encode(
                PublicHeistOutput.actionResult(
                    expectationResult,
                    expectation: expectation,
                    profile: profile
                ),
                forKey: .expectationResult
            )
            try container.encode(PublicHeistOutput.expectation(expectation), forKey: .expectation)
        }
    }
}

private struct PublicHeistWaitEvidenceJSON: Encodable {
    private enum CodingKeys: String, CodingKey {
        case outcome, result, expectation, baselineSummary, finalSummary
    }

    let evidence: HeistWaitEvidence
    let profile: ProjectionProfile

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(evidence.outcome, forKey: .outcome)
        try container.encode(
            PublicHeistOutput.actionResult(
                evidence.actionResult,
                expectation: evidence.expectation,
                profile: profile
            ),
            forKey: .result
        )
        try container.encode(PublicHeistOutput.expectation(evidence.expectation), forKey: .expectation)
        try container.encodeIfPresent(evidence.baselineSummary, forKey: .baselineSummary)
        try container.encodeIfPresent(evidence.finalSummary, forKey: .finalSummary)
    }
}

private struct PublicHeistCaseSelectionEvidenceJSON: Encodable {
    private enum CodingKeys: String, CodingKey {
        case outcome, elapsedMs, timeout, lastObservedSummary, caseCount, cases, omittedCaseCount
    }

    let evidence: HeistCaseSelectionEvidence
    let profile: ProjectionProfile

    func encode(to encoder: Encoder) throws {
        let selection = evidence.selection
        let visibleCases = Array(selection.cases.prefix(profile.limits.caseResults))
        let omittedCount = selection.cases.count - visibleCases.count

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selection.outcome, forKey: .outcome)
        try container.encode(selection.elapsedMs, forKey: .elapsedMs)
        try container.encodeIfPresent(selection.timeout, forKey: .timeout)
        try container.encodeIfPresent(selection.lastObservedSummary, forKey: .lastObservedSummary)
        try container.encode(selection.cases.count, forKey: .caseCount)
        try container.encodeIfPresent(visibleCases.isEmpty ? nil : visibleCases, forKey: .cases)
        try container.encodeIfPresent(omittedCount > 0 ? omittedCount : nil, forKey: .omittedCaseCount)
    }
}

private struct PublicHeistRepeatUntilEvidenceJSON: Encodable {
    private enum CodingKeys: String, CodingKey {
        case outcome, predicate, timeout, iterationCount, iterationOrdinal, expectation
        case result, lastObservedSummary, failureReason
    }

    let declaration: HeistRepeatUntilDeclaration
    let evidence: HeistRepeatUntilEvidence
    let profile: ProjectionProfile

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(evidence.outcome, forKey: .outcome)
        try container.encode(declaration.predicate, forKey: .predicate)
        try container.encode(declaration.timeout.seconds, forKey: .timeout)
        try container.encode(evidence.iterationCount, forKey: .iterationCount)
        try container.encodeIfPresent(evidence.iterationOrdinal, forKey: .iterationOrdinal)
        try container.encode(PublicHeistOutput.expectation(evidence.expectation), forKey: .expectation)
        try container.encodeIfPresent(
            PublicHeistOutput.actionResult(
                evidence.actionResult,
                expectation: evidence.expectation,
                profile: profile
            ),
            forKey: .result
        )
        try container.encodeIfPresent(evidence.lastObservedSummary, forKey: .lastObservedSummary)
        try container.encodeIfPresent(evidence.failureReason, forKey: .failureReason)
    }
}

private struct PublicHeistForEachStringEvidenceJSON: Encodable {
    private enum CodingKeys: String, CodingKey {
        case parameter, count, iterationCount, iterationOrdinal, value, failureReason
    }

    let declaration: HeistForEachStringDeclaration
    let evidence: HeistForEachStringEvidence

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(declaration.parameter, forKey: .parameter)
        try container.encode(declaration.count, forKey: .count)
        try container.encode(evidence.iterationCount, forKey: .iterationCount)
        try container.encodeIfPresent(evidence.iterationOrdinal, forKey: .iterationOrdinal)
        try container.encodeIfPresent(evidence.value, forKey: .value)
        try container.encodeIfPresent(evidence.failureReason, forKey: .failureReason)
    }
}

private struct PublicHeistForEachElementEvidenceJSON: Encodable {
    private enum CodingKeys: String, CodingKey {
        case parameter, matching, limit, matchedCount, iterationCount, iterationOrdinal
        case targetOrdinal, targetSummary, failureReason
    }

    let declaration: HeistForEachElementDeclaration
    let evidence: HeistForEachElementEvidence

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(declaration.parameter, forKey: .parameter)
        try container.encode(declaration.matching, forKey: .matching)
        try container.encode(declaration.limit, forKey: .limit)
        try container.encode(evidence.matchedCount, forKey: .matchedCount)
        try container.encode(evidence.iterationCount, forKey: .iterationCount)
        try container.encodeIfPresent(evidence.iterationOrdinal, forKey: .iterationOrdinal)
        try container.encodeIfPresent(evidence.targetOrdinal, forKey: .targetOrdinal)
        try container.encodeIfPresent(evidence.targetSummary, forKey: .targetSummary)
        try container.encodeIfPresent(evidence.failureReason, forKey: .failureReason)
    }
}

private struct PublicHeistInvocationEvidenceJSON: Encodable {
    private enum CodingKeys: String, CodingKey {
        case capability, argument, childFailedPath, expectationResult, expectation, expectationEvidence
    }

    let invocation: HeistInvocationStep
    let evidence: HeistInvocationEvidence
    let profile: ProjectionProfile

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(invocation.path.description, forKey: .capability)
        try container.encodeIfPresent(
            invocation.argument == .none ? nil : invocation.runHeistSummary,
            forKey: .argument
        )
        try container.encodeIfPresent(evidence.childFailedPath?.description, forKey: .childFailedPath)
        try container.encodeIfPresent(
            PublicHeistOutput.actionResult(
                evidence.expectationActionResult,
                expectation: evidence.expectation,
                profile: profile
            ),
            forKey: .expectationResult
        )
        try container.encodeIfPresent(
            PublicHeistOutput.expectation(evidence.expectation),
            forKey: .expectation
        )
        try container.encodeIfPresent(
            evidence.waitEvidence.map { PublicHeistWaitEvidenceJSON(evidence: $0, profile: profile) },
            forKey: .expectationEvidence
        )
    }
}

private enum PublicHeistOutput {
    static func actionResult(
        _ result: ActionResult,
        expectation: ExpectationResult? = nil,
        profile: ProjectionProfile
    ) -> ActionProjection {
        action(
            result,
            method: .result(result.method),
            expectation: expectation,
            profile: profile
        )
    }

    static func actionResult(
        _ result: ActionResult?,
        expectation: ExpectationResult? = nil,
        profile: ProjectionProfile
    ) -> ActionProjection? {
        result.map { actionResult($0, expectation: expectation, profile: profile) }
    }

    static func action(
        _ result: ActionResult,
        method: ActionMethodProjection,
        expectation: ExpectationResult? = nil,
        profile: ProjectionProfile
    ) -> ActionProjection {
        ActionProjection(
            actionMethod: method,
            result: result,
            announcementOverride: expectation?.matchedAnnouncement,
            profile: profile,
            publicContext: .heistReportEvidence
        )
    }

    static func expectation(_ result: ExpectationResult) -> ExpectationProjection {
        ExpectationProjection(result: result)
    }

    static func expectation(_ result: ExpectationResult?) -> ExpectationProjection? {
        result.map(expectation)
    }
}
