import Foundation
import ThePlans

import AccessibilitySnapshotModel
import TheScore

private enum PublicHeistExecutionKey: String, CodingKey {
    case status, report, summary, metrics, nodes, netDelta
    case executedTopLevelStepCount, executedNodeCount, outputNodeCount, abortedAtPath, durationMs, expectations
    case checked, met, allMet
    case path, kind, capability, message, evidence, failure, abortedAtChildPath, expectation, children
    case category, contract, observed, expected, code, phase, retryable, hint
    case action, wait, caseSelection, forEachString, forEachElement, repeatUntil, invocation, warning
    case commandName, target, result, expectationResult
    case outcome, baselineSummary, finalSummary
    case elapsedMs, timeout, lastObservedSummary, caseCount, cases, omittedCaseCount
    case predicate, iterationCount, iterationOrdinal, failureReason
    case parameter, count, value
    case matching, limit, matchedCount, targetOrdinal, targetSummary
    case argument, childFailedPath, expectationEvidence
}

/// The sole public JSON projection of the canonical `HeistReport`.
struct PublicHeistExecutionResponse: Encodable {
    private let report: HeistReport
    private let profile: ProjectionProfile

    init(report: HeistReport, profile: ProjectionProfile) {
        self.report = report
        self.profile = profile.heistReport
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PublicHeistExecutionKey.self)
        try container.encode(report.failure == nil ? PublicResponseStatus.ok : .partial, forKey: .status)
        try encodeReport(to: container.superEncoder(forKey: .report))
    }

    private func encodeReport(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PublicHeistExecutionKey.self)
        try encodeSummary(to: container.superEncoder(forKey: .summary))
        try container.encode(report.metrics, forKey: .metrics)
        var nodes = container.nestedUnkeyedContainer(forKey: .nodes)
        for node in report.nodes {
            try encode(node, to: nodes.superEncoder())
        }
        guard case .changed(let trace) = report.accessibilityChange,
              let delta = DeltaProjection(
                  trace: trace,
                  isComplete: true,
                  profile: profile,
                  includeScreenInterface: true
              ) else { return }
        try container.encode(
            PublicDelta(projection: delta, screenPolicy: .screenSummary),
            forKey: .netDelta
        )
    }

    private func encodeSummary(to encoder: Encoder) throws {
        let summary = report.summary
        var container = encoder.container(keyedBy: PublicHeistExecutionKey.self)
        try container.encode(summary.executedTopLevelStepCount, forKey: .executedTopLevelStepCount)
        try container.encode(summary.executedNodeCount, forKey: .executedNodeCount)
        try container.encode(summary.outputNodeCount, forKey: .outputNodeCount)
        try container.encodeIfPresent(summary.abortedAtPath?.description, forKey: .abortedAtPath)
        try container.encode(summary.durationMs, forKey: .durationMs)
        guard let expectations = summary.expectations else { return }
        var projected = container.nestedContainer(
            keyedBy: PublicHeistExecutionKey.self,
            forKey: .expectations
        )
        try projected.encode(expectations.checked, forKey: .checked)
        try projected.encode(expectations.met, forKey: .met)
        try projected.encode(expectations.allMet, forKey: .allMet)
    }

    private func encode(_ node: HeistReport.Node, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PublicHeistExecutionKey.self)
        try container.encode(node.path.description, forKey: .path)
        try container.encode(node.kind.rawValue, forKey: .kind)
        try container.encodeIfPresent(node.capability?.description, forKey: .capability)
        try container.encode(node.status.rawValue, forKey: .status)
        try container.encodeIfPresent(node.message, forKey: .message)
        try container.encode(node.durationMs, forKey: .durationMs)
        if let evidence = node.evidence {
            try encode(evidence, to: container.superEncoder(forKey: .evidence))
        }
        if let failure = node.failure {
            try encode(failure, to: container.superEncoder(forKey: .failure))
        }
        try container.encodeIfPresent(node.abortedAtChildPath?.description, forKey: .abortedAtChildPath)
        try container.encodeIfPresent(
            node.expectation.map { PublicExpectationResult(projection: ExpectationProjection(result: $0)) },
            forKey: .expectation
        )
        var children = container.nestedUnkeyedContainer(forKey: .children)
        for child in node.children {
            try encode(child, to: children.superEncoder())
        }
    }

    private func encode(_ failure: HeistReport.Failure, to encoder: Encoder) throws {
        let diagnostic = failure.actionKind.map {
            DiagnosticFailureMapper.map(failureKind: $0, message: failure.diagnosticMessage)
        } ?? DiagnosticFailureMapper.map(
            reportFailure: failure.detail,
            message: failure.diagnosticMessage
        )
        var container = encoder.container(keyedBy: PublicHeistExecutionKey.self)
        try container.encode(failure.detail.category, forKey: .category)
        try container.encode(failure.detail.contract, forKey: .contract)
        try container.encode(failure.detail.observed, forKey: .observed)
        try container.encodeIfPresent(failure.detail.expected, forKey: .expected)
        try container.encode(diagnostic.code, forKey: .code)
        try container.encode(diagnostic.kind.rawValue, forKey: .kind)
        try container.encode(diagnostic.phase.rawValue, forKey: .phase)
        try container.encode(diagnostic.retryable, forKey: .retryable)
        try container.encodeIfPresent(diagnostic.hint, forKey: .hint)
    }

    private func encode(_ evidence: HeistReport.Evidence, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PublicHeistExecutionKey.self)
        switch evidence {
        case .action(let command, let evidence):
            try encode(command: command, evidence: evidence, to: container.superEncoder(forKey: .action))
        case .wait(let evidence):
            try encode(evidence, to: container.superEncoder(forKey: .wait))
        case .caseSelection(let evidence):
            try encode(evidence, to: container.superEncoder(forKey: .caseSelection))
        case .forEachString(let declaration, let evidence):
            try encode(declaration: declaration, evidence: evidence, to: container.superEncoder(forKey: .forEachString))
        case .forEachElement(let declaration, let evidence):
            try encode(declaration: declaration, evidence: evidence, to: container.superEncoder(forKey: .forEachElement))
        case .repeatUntil(let declaration, let evidence):
            try encode(declaration: declaration, evidence: evidence, to: container.superEncoder(forKey: .repeatUntil))
        case .invocation(let invocation, let evidence):
            try encode(invocation: invocation, evidence: evidence, to: container.superEncoder(forKey: .invocation))
        case .warning(let warning):
            try container.encode(warning, forKey: .warning)
        }
    }

    private func encode(
        command: HeistActionCommand,
        evidence: HeistActionEvidence,
        to encoder: Encoder
    ) throws {
        var container = encoder.container(keyedBy: PublicHeistExecutionKey.self)
        try container.encode(command.wireType.rawValue, forKey: .commandName)
        try container.encodeIfPresent(command.reportTarget, forKey: .target)
        switch evidence {
        case .commandResolutionFailure:
            break
        case .dispatch(let result):
            try container.encode(actionOutput(result, method: .heist(command)), forKey: .result)
        case .expectation(let result, let expectationResult, let expectation):
            try container.encode(actionOutput(result, method: .heist(command)), forKey: .result)
            try container.encode(
                actionOutput(expectationResult, method: .result(expectationResult.method)),
                forKey: .expectationResult
            )
            try container.encode(expectationOutput(expectation), forKey: .expectation)
        }
    }

    private func encode(_ evidence: HeistWaitEvidence, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PublicHeistExecutionKey.self)
        try container.encode(evidence.outcome, forKey: .outcome)
        try container.encode(
            actionOutput(evidence.actionResult, method: .result(evidence.actionResult.method)),
            forKey: .result
        )
        try container.encode(expectationOutput(evidence.expectation), forKey: .expectation)
        try container.encodeIfPresent(evidence.baselineSummary, forKey: .baselineSummary)
        try container.encodeIfPresent(evidence.finalSummary, forKey: .finalSummary)
    }

    private func encode(_ evidence: HeistCaseSelectionEvidence, to encoder: Encoder) throws {
        let selection = evidence.selection
        let visibleCases = Array(selection.cases.prefix(profile.limits.caseResults))
        let omittedCount = selection.cases.count - visibleCases.count
        var container = encoder.container(keyedBy: PublicHeistExecutionKey.self)
        try container.encode(selection.outcome, forKey: .outcome)
        try container.encode(selection.elapsedMs, forKey: .elapsedMs)
        try container.encodeIfPresent(selection.timeout, forKey: .timeout)
        try container.encodeIfPresent(selection.lastObservedSummary, forKey: .lastObservedSummary)
        try container.encode(selection.cases.count, forKey: .caseCount)
        try container.encodeIfPresent(visibleCases.isEmpty ? nil : visibleCases, forKey: .cases)
        try container.encodeIfPresent(omittedCount > 0 ? omittedCount : nil, forKey: .omittedCaseCount)
    }

    private func encode(
        declaration: HeistRepeatUntilDeclaration,
        evidence: HeistRepeatUntilEvidence,
        to encoder: Encoder
    ) throws {
        var container = encoder.container(keyedBy: PublicHeistExecutionKey.self)
        try container.encode(evidence.outcome, forKey: .outcome)
        try container.encode(declaration.predicate, forKey: .predicate)
        try container.encode(declaration.timeout.seconds, forKey: .timeout)
        try container.encode(evidence.iterationCount, forKey: .iterationCount)
        try container.encodeIfPresent(evidence.iterationOrdinal, forKey: .iterationOrdinal)
        try container.encode(expectationOutput(evidence.expectation), forKey: .expectation)
        try container.encodeIfPresent(
            evidence.actionResult.map { actionOutput($0, method: .result($0.method)) },
            forKey: .result
        )
        try container.encodeIfPresent(evidence.lastObservedSummary, forKey: .lastObservedSummary)
        try container.encodeIfPresent(evidence.failureReason, forKey: .failureReason)
    }

    private func encode(
        declaration: HeistForEachStringDeclaration,
        evidence: HeistForEachStringEvidence,
        to encoder: Encoder
    ) throws {
        var container = encoder.container(keyedBy: PublicHeistExecutionKey.self)
        try container.encode(declaration.parameter, forKey: .parameter)
        try container.encode(declaration.count, forKey: .count)
        try container.encode(evidence.iterationCount, forKey: .iterationCount)
        try container.encodeIfPresent(evidence.iterationOrdinal, forKey: .iterationOrdinal)
        try container.encodeIfPresent(evidence.value, forKey: .value)
        try container.encodeIfPresent(evidence.failureReason, forKey: .failureReason)
    }

    private func encode(
        declaration: HeistForEachElementDeclaration,
        evidence: HeistForEachElementEvidence,
        to encoder: Encoder
    ) throws {
        var container = encoder.container(keyedBy: PublicHeistExecutionKey.self)
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

    private func encode(
        invocation: HeistInvocationStep,
        evidence: HeistInvocationEvidence,
        to encoder: Encoder
    ) throws {
        var container = encoder.container(keyedBy: PublicHeistExecutionKey.self)
        try container.encode(invocation.path.description, forKey: .capability)
        try container.encodeIfPresent(
            invocation.argument == .none ? nil : invocation.runHeistSummary,
            forKey: .argument
        )
        try container.encodeIfPresent(evidence.childFailedPath?.description, forKey: .childFailedPath)
        try container.encodeIfPresent(
            evidence.expectationActionResult.map { actionOutput($0, method: .result($0.method)) },
            forKey: .expectationResult
        )
        try container.encodeIfPresent(evidence.expectation.map(expectationOutput), forKey: .expectation)
        if let waitEvidence = evidence.waitEvidence {
            try encode(waitEvidence, to: container.superEncoder(forKey: .expectationEvidence))
        }
    }

    private func actionOutput(
        _ result: ActionResult,
        method: ActionMethodProjection
    ) -> PublicActionResultOutput {
        PublicActionResultOutput(
            projection: ActionProjection(
                actionMethod: method,
                result: result,
                profile: profile,
                includeOmissions: true
            ),
            context: .heistReportEvidence
        )
    }

    private func expectationOutput(_ result: ExpectationResult) -> PublicExpectationResult {
        PublicExpectationResult(projection: ExpectationProjection(result: result))
    }
}

struct PublicHeistActionResultOmissions: Encodable {
    let accessibilityTrace: PublicProjectionOmission?
    let subjectEvidence: PublicProjectionOmission?

    var isEmpty: Bool {
        accessibilityTrace == nil && subjectEvidence == nil
    }

    init(projection: ActionResultOmissionsProjection) {
        self.accessibilityTrace = projection.accessibilityTrace.map { PublicProjectionOmission(projection: $0) }
        self.subjectEvidence = projection.subjectEvidence.map { PublicProjectionOmission(projection: $0) }
    }
}

struct PublicProjectionOmission: Encodable {
    let reason: String
    let projectedAs: String?
    let omittedCount: Int?

    init(projection: ProjectionOmission) {
        self.reason = projection.reason.rawValue
        self.projectedAs = projection.projectedAs
        self.omittedCount = projection.omittedCount
    }
}

struct PublicHeistElementEditOmissions: Encodable {
    let added: Int?
    let removed: Int?
    let updated: Int?
    let addedKeys: [String]?
    let removedKeys: [String]?
    let updatedKeys: [String]?

    init(
        added: Int?,
        removed: Int?,
        updated: Int?,
        addedKeys: [String]?,
        removedKeys: [String]?,
        updatedKeys: [String]?
    ) {
        self.added = added
        self.removed = removed
        self.updated = updated
        self.addedKeys = addedKeys
        self.removedKeys = removedKeys
        self.updatedKeys = updatedKeys
    }

    init(projection: DeltaEditsProjection) {
        self.init(
            added: projection.added.omittedCount,
            removed: projection.removed.omittedCount,
            updated: projection.updated.omittedCount,
            addedKeys: projection.added.omittedKeys,
            removedKeys: projection.removed.omittedKeys,
            updatedKeys: projection.updated.omittedKeys
        )
    }

    var isEmpty: Bool {
        added == nil
            && removed == nil
            && updated == nil
            && addedKeys == nil
            && removedKeys == nil
            && updatedKeys == nil
    }
}

struct PublicHeistDeltaOmissions: Encodable {
    let transient: Int?
    let transientKeys: [String]?

    init(projection: ElementProjectionBucket) {
        self.transient = projection.omittedCount
        self.transientKeys = projection.omittedKeys
    }

    var isEmpty: Bool {
        transient == nil && transientKeys == nil
    }
}

struct PublicHeistScreenProjection: Encodable {
    let screenDescription: String
    let screenId: String?
    let elementCount: Int
    let elements: [PublicElement]?
    let omittedElementCount: Int?

    init(projection: DeltaScreenProjection) {
        self.screenDescription = projection.screenDescription
        self.screenId = projection.screenId
        self.elementCount = projection.elementCount
        self.elements = projection.elements.isEmpty
            ? nil
            : projection.elements.map { PublicElement(element: $0, detail: .summary) }
        self.omittedElementCount = projection.omittedElementCount
    }
}
