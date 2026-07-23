import ThePlans
import TheScore

struct PublicHeistReportEvidenceJSON: Encodable {
    let evidence: HeistReport.Evidence
    let profile: ProjectionProfile

    func encode(to encoder: Encoder) throws {
        try evidence.encode(to: encoder, profile: profile)
    }
}

private extension HeistReport.Evidence {
    private enum CodingKeys: String, CodingKey {
        case action, wait, caseSelection, forEachString, forEachElement, repeatUntil, invocation, warning
    }

    func encode(to encoder: Encoder, profile: ProjectionProfile) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .action(let command, let evidence):
            try encode(command, evidence: evidence, to: container.superEncoder(forKey: .action), profile: profile)
        case .wait(let evidence):
            try encode(evidence, to: container.superEncoder(forKey: .wait), profile: profile)
        case .caseSelection(let evidence):
            try encode(evidence, to: container.superEncoder(forKey: .caseSelection), profile: profile)
        case .forEachString(let declaration, let evidence):
            try encode(declaration, evidence: evidence, to: container.superEncoder(forKey: .forEachString))
        case .forEachElement(let declaration, let evidence):
            try encode(declaration, evidence: evidence, to: container.superEncoder(forKey: .forEachElement))
        case .repeatUntil(let declaration, let evidence):
            try encode(
                declaration,
                evidence: evidence,
                to: container.superEncoder(forKey: .repeatUntil),
                profile: profile
            )
        case .invocation(let invocation, let evidence):
            try encode(
                invocation,
                evidence: evidence,
                to: container.superEncoder(forKey: .invocation),
                profile: profile
            )
        case .warning(let warning):
            try container.encode(warning, forKey: .warning)
        }
    }

    private enum ActionCodingKeys: String, CodingKey {
        case commandName, target, result, expectationResult, expectation
    }

    private func encode(
        _ command: HeistActionCommand,
        evidence: HeistActionEvidence,
        to encoder: Encoder,
        profile: ProjectionProfile
    ) throws {
        var container = encoder.container(keyedBy: ActionCodingKeys.self)
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

    private enum WaitCodingKeys: String, CodingKey {
        case outcome, result, expectation, baselineSummary, finalSummary
    }

    private func encode(
        _ evidence: HeistSettlementEvidence,
        to encoder: Encoder,
        profile: ProjectionProfile
    ) throws {
        var container = encoder.container(keyedBy: WaitCodingKeys.self)
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

    private enum CaseSelectionCodingKeys: String, CodingKey {
        case outcome, elapsedMs, timeout, lastObservedSummary, caseCount, cases, omittedCaseCount
    }

    private func encode(
        _ evidence: HeistCaseSelectionEvidence,
        to encoder: Encoder,
        profile: ProjectionProfile
    ) throws {
        let selection = evidence.selection
        let visibleCases = Array(selection.cases.prefix(profile.limits.caseResults))
        let omittedCount = selection.cases.count - visibleCases.count

        var container = encoder.container(keyedBy: CaseSelectionCodingKeys.self)
        try container.encode(selection.outcome, forKey: .outcome)
        try container.encode(selection.elapsedMs, forKey: .elapsedMs)
        try container.encodeIfPresent(selection.timeout, forKey: .timeout)
        try container.encodeIfPresent(selection.lastObservedSummary, forKey: .lastObservedSummary)
        try container.encode(selection.cases.count, forKey: .caseCount)
        try container.encodeIfPresent(visibleCases.isEmpty ? nil : visibleCases, forKey: .cases)
        try container.encodeIfPresent(omittedCount > 0 ? omittedCount : nil, forKey: .omittedCaseCount)
    }

    private enum RepeatUntilCodingKeys: String, CodingKey {
        case outcome, predicate, timeout, iterationCount, iterationOrdinal, expectation
        case result, lastObservedSummary, failureReason
    }

    private func encode(
        _ declaration: HeistRepeatUntilDeclaration,
        evidence: HeistRepeatUntilEvidence,
        to encoder: Encoder,
        profile: ProjectionProfile
    ) throws {
        var container = encoder.container(keyedBy: RepeatUntilCodingKeys.self)
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

    private enum ForEachStringCodingKeys: String, CodingKey {
        case parameter, count, iterationCount, iterationOrdinal, value, failureReason
    }

    private func encode(
        _ declaration: HeistForEachStringDeclaration,
        evidence: HeistForEachStringEvidence,
        to encoder: Encoder
    ) throws {
        var container = encoder.container(keyedBy: ForEachStringCodingKeys.self)
        try container.encode(declaration.parameter, forKey: .parameter)
        try container.encode(declaration.count, forKey: .count)
        try container.encode(evidence.iterationCount, forKey: .iterationCount)
        try container.encodeIfPresent(evidence.iterationOrdinal, forKey: .iterationOrdinal)
        try container.encodeIfPresent(evidence.value, forKey: .value)
        try container.encodeIfPresent(evidence.failureReason, forKey: .failureReason)
    }

    private enum ForEachElementCodingKeys: String, CodingKey {
        case parameter, matching, limit, matchedCount, iterationCount, iterationOrdinal
        case targetOrdinal, targetSummary, failureReason
    }

    private func encode(
        _ declaration: HeistForEachElementDeclaration,
        evidence: HeistForEachElementEvidence,
        to encoder: Encoder
    ) throws {
        var container = encoder.container(keyedBy: ForEachElementCodingKeys.self)
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

    private enum InvocationCodingKeys: String, CodingKey {
        case capability, argument, childFailedPath, expectationResult, expectation, expectationEvidence
    }

    private func encode(
        _ invocation: HeistInvocationStep,
        evidence: HeistInvocationEvidence,
        to encoder: Encoder,
        profile: ProjectionProfile
    ) throws {
        var container = encoder.container(keyedBy: InvocationCodingKeys.self)
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
        if let waitEvidence = evidence.waitEvidence {
            try encode(
                waitEvidence,
                to: container.superEncoder(forKey: .expectationEvidence),
                profile: profile
            )
        }
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
