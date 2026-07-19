import Foundation
import ThePlans

import AccessibilitySnapshotModel
import TheScore

struct PublicHeistExecutionResponse: Encodable {
    let status: PublicResponseStatus
    let report: PublicHeistReport

    init(
        report: HeistReport,
        profile: ProjectionProfile
    ) {
        status = report.failure == nil ? .ok : .partial
        self.report = PublicHeistReport(
            report: report,
            profile: profile
        )
    }
}

struct PublicHeistReport: Encodable {
    let summary: PublicHeistReportSummary
    let metrics: HeistReport.Metrics
    let nodes: [PublicHeistReportNode]
    let netDelta: PublicDelta?

    init(
        report: HeistReport,
        profile: ProjectionProfile
    ) {
        let profile = profile.heistReport
        summary = PublicHeistReportSummary(summary: report.summary)
        metrics = report.metrics
        nodes = report.nodes.map { PublicHeistReportNode(node: $0, profile: profile) }
        switch report.accessibilityChange {
        case .changed(let trace):
            netDelta = DeltaProjection(
                trace: trace,
                isComplete: true,
                profile: profile,
                includeScreenInterface: true
            ).map {
                PublicDelta(
                    projection: $0,
                    screenPolicy: .screenSummary
                )
            }
        case .notApplicable, .incomplete, .unchanged:
            netDelta = nil
        }
    }
}

struct PublicHeistReportSummary: Encodable {
    let executedTopLevelStepCount: Int
    let executedNodeCount: Int
    let outputNodeCount: Int
    let abortedAtPath: String?
    let durationMs: Int
    let expectations: PublicHeistExpectations?

    init(summary: HeistReport.Summary) {
        executedTopLevelStepCount = summary.executedTopLevelStepCount
        executedNodeCount = summary.executedNodeCount
        outputNodeCount = summary.outputNodeCount
        abortedAtPath = summary.abortedAtPath?.description
        durationMs = summary.durationMs
        expectations = summary.expectations.map(PublicHeistExpectations.init)
    }
}

struct PublicHeistReportNode: Encodable {
    let path: String
    let kind: String
    /// Product capability name for an invoke node (e.g. `LibraryScreen.addToCart`).
    /// The frame is the product: reports name which capability ran; the argument
    /// is visible in `message` as `RunHeist("Name", argument)`.
    let capability: String?
    let status: String
    let message: String?
    let durationMs: Int
    let evidence: PublicHeistReportEvidence?
    let failure: PublicHeistFailureDetail?
    let abortedAtChildPath: String?
    let expectation: PublicExpectationResult?
    let children: [PublicHeistReportNode]

    init(node: HeistReport.Node, profile: ProjectionProfile) {
        path = node.path.description
        kind = node.kind.rawValue
        capability = node.capability?.description
        status = node.status.rawValue
        message = node.message
        durationMs = node.durationMs
        evidence = node.evidence.map { PublicHeistReportEvidence(evidence: $0, profile: profile) }
        failure = node.failure.map(PublicHeistFailureDetail.init)
        abortedAtChildPath = node.abortedAtChildPath?.description
        expectation = node.expectation.map {
            PublicExpectationResult(projection: ExpectationProjection(result: $0))
        }
        children = node.children.map { PublicHeistReportNode(node: $0, profile: profile) }
    }
}

struct PublicHeistFailureDetail: Encodable {
    let category: HeistFailureCategory
    let contract: String
    let observed: String
    let expected: String?
    let code: String
    let kind: String
    let phase: String
    let retryable: Bool
    let hint: String?

    init(failure: HeistReport.Failure) {
        let diagnostic = failure.actionKind.map {
            DiagnosticFailureMapper.map(failureKind: $0, message: failure.diagnosticMessage)
        } ?? DiagnosticFailureMapper.map(
            reportFailure: failure.detail,
            message: failure.diagnosticMessage
        )
        category = failure.detail.category
        contract = failure.detail.contract
        observed = failure.detail.observed
        expected = failure.detail.expected
        code = diagnostic.code
        kind = diagnostic.kind.rawValue
        phase = diagnostic.phase.rawValue
        retryable = diagnostic.retryable
        hint = diagnostic.hint
    }
}

struct PublicHeistReportEvidence: Encodable {
    private let evidence: HeistReport.Evidence
    private let profile: ProjectionProfile

    init(evidence: HeistReport.Evidence, profile: ProjectionProfile) {
        self.evidence = evidence
        self.profile = profile
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case wait
        case caseSelection
        case forEachString
        case forEachElement
        case repeatUntil
        case invocation
        case warning
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch evidence {
        case .action(let command, let evidence):
            try container.encode(
                PublicHeistActionEvidence(command: command, evidence: evidence, profile: profile),
                forKey: .action
            )
        case .wait(let evidence):
            try container.encode(PublicHeistWaitEvidence(evidence: evidence, profile: profile), forKey: .wait)
        case .caseSelection(let evidence):
            try container.encode(
                PublicHeistCaseSelectionEvidence(evidence: evidence, profile: profile),
                forKey: .caseSelection
            )
        case .forEachString(let declaration, let evidence):
            try container.encode(
                PublicHeistForEachStringEvidence(declaration: declaration, evidence: evidence),
                forKey: .forEachString
            )
        case .forEachElement(let declaration, let evidence):
            try container.encode(
                PublicHeistForEachElementEvidence(declaration: declaration, evidence: evidence),
                forKey: .forEachElement
            )
        case .repeatUntil(let declaration, let evidence):
            try container.encode(
                PublicHeistRepeatUntilEvidence(declaration: declaration, evidence: evidence, profile: profile),
                forKey: .repeatUntil
            )
        case .invocation(let invocation, let evidence):
            try container.encode(
                PublicHeistInvocationEvidence(invocation: invocation, evidence: evidence, profile: profile),
                forKey: .invocation
            )
        case .warning(let evidence):
            try container.encode(evidence, forKey: .warning)
        }
    }
}

struct PublicHeistActionEvidence: Encodable {
    private let command: HeistActionCommand
    private let evidence: HeistActionEvidence
    private let profile: ProjectionProfile

    init(command: HeistActionCommand, evidence: HeistActionEvidence, profile: ProjectionProfile) {
        self.command = command
        self.evidence = evidence
        self.profile = profile
    }

    private enum CodingKeys: String, CodingKey {
        case commandName
        case target
        case result
        case expectationResult
        case expectation
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command.wireType.rawValue, forKey: .commandName)
        try container.encodeIfPresent(command.reportTarget, forKey: .target)
        switch evidence {
        case .commandResolutionFailure:
            break
        case .dispatch(let result):
            try container.encode(
                PublicActionResultOutput(
                    projection: actionProjection(command: command, result: result),
                    context: .heistReportEvidence
                ),
                forKey: .result
            )
        case .expectation(let dispatchResult, let expectationResult, let expectation):
            try container.encode(
                PublicActionResultOutput(
                    projection: actionProjection(command: command, result: dispatchResult),
                    context: .heistReportEvidence
                ),
                forKey: .result
            )
            try container.encode(
                PublicActionResultOutput(
                    projection: ActionProjection(
                        actionMethod: .result(expectationResult.method),
                        result: expectationResult,
                        profile: profile,
                        includeOmissions: true
                    ),
                    context: .heistReportEvidence
                ),
                forKey: .expectationResult
            )
            try container.encode(
                PublicExpectationResult(projection: ExpectationProjection(result: expectation)),
                forKey: .expectation
            )
        }
    }

    private func actionProjection(command: HeistActionCommand, result: ActionResult) -> ActionProjection {
        ActionProjection(
            actionMethod: .heist(command),
            result: result,
            profile: profile,
            includeOmissions: true
        )
    }

}

struct PublicHeistWaitEvidence: Encodable {
    let outcome: HeistPredicateEvidenceOutcome
    let result: PublicActionResultOutput
    let expectation: PublicExpectationResult
    let baselineSummary: String?
    let finalSummary: String?

    init(evidence: HeistWaitEvidence, profile: ProjectionProfile) {
        self.outcome = evidence.outcome
        self.result = PublicActionResultOutput(
            projection: ActionProjection(
                actionMethod: .result(evidence.actionResult.method),
                result: evidence.actionResult,
                profile: profile,
                includeOmissions: true
            ),
            context: .heistReportEvidence
        )
        self.expectation = PublicExpectationResult(
            projection: ExpectationProjection(result: evidence.expectation)
        )
        self.baselineSummary = evidence.baselineSummary
        self.finalSummary = evidence.finalSummary
    }
}

struct PublicHeistCaseSelectionEvidence: Encodable {
    let outcome: HeistCaseSelectionOutcome
    let elapsedMs: Int
    let timeout: Double?
    let lastObservedSummary: String?
    let caseCount: Int
    let cases: [HeistCaseMatchResult]?
    let omittedCaseCount: Int?

    init(evidence: HeistCaseSelectionEvidence, profile: ProjectionProfile) {
        let selection = evidence.selection
        let visibleCases = Array(selection.cases.prefix(profile.limits.caseResults))
        self.outcome = selection.outcome
        self.elapsedMs = selection.elapsedMs
        self.timeout = selection.timeout
        self.lastObservedSummary = selection.lastObservedSummary
        self.caseCount = selection.cases.count
        self.cases = visibleCases.isEmpty
            ? nil
            : visibleCases
        let omitted = selection.cases.count - visibleCases.count
        self.omittedCaseCount = omitted > 0 ? omitted : nil
    }
}

struct PublicHeistRepeatUntilEvidence: Encodable {
    let outcome: HeistPredicateEvidenceOutcome
    let predicate: AccessibilityPredicate
    let timeout: Double
    let iterationCount: Int
    let iterationOrdinal: Int?
    let expectation: PublicExpectationResult
    let result: PublicActionResultOutput?
    let lastObservedSummary: String?
    let failureReason: String?

    init(
        declaration: HeistRepeatUntilDeclaration,
        evidence: HeistRepeatUntilEvidence,
        profile: ProjectionProfile
    ) {
        self.outcome = evidence.outcome
        self.predicate = declaration.predicate
        self.timeout = declaration.timeout.seconds
        self.iterationCount = evidence.iterationCount
        self.iterationOrdinal = evidence.iterationOrdinal
        self.expectation = PublicExpectationResult(
            projection: ExpectationProjection(result: evidence.expectation)
        )
        self.result = evidence.actionResult.map {
            PublicActionResultOutput(
                projection: ActionProjection(
                    actionMethod: .result($0.method),
                    result: $0,
                    profile: profile,
                    includeOmissions: true
                ),
                context: .heistReportEvidence
            )
        }
        self.lastObservedSummary = evidence.lastObservedSummary
        self.failureReason = evidence.failureReason
    }
}

struct PublicHeistForEachStringEvidence: Encodable {
    let parameter: HeistReferenceName
    let count: Int
    let iterationCount: Int
    let iterationOrdinal: Int?
    let value: String?
    let failureReason: String?

    init(declaration: HeistForEachStringDeclaration, evidence: HeistForEachStringEvidence) {
        parameter = declaration.parameter
        count = declaration.count
        iterationCount = evidence.iterationCount
        iterationOrdinal = evidence.iterationOrdinal
        value = evidence.value
        failureReason = evidence.failureReason
    }
}

struct PublicHeistForEachElementEvidence: Encodable {
    let parameter: HeistReferenceName
    let matching: ElementPredicateTemplate
    let limit: Int
    let matchedCount: Int
    let iterationCount: Int
    let iterationOrdinal: Int?
    let targetOrdinal: Int?
    let targetSummary: String?
    let failureReason: String?

    init(declaration: HeistForEachElementDeclaration, evidence: HeistForEachElementEvidence) {
        parameter = declaration.parameter
        matching = declaration.matching
        limit = declaration.limit
        matchedCount = evidence.matchedCount
        iterationCount = evidence.iterationCount
        iterationOrdinal = evidence.iterationOrdinal
        targetOrdinal = evidence.targetOrdinal
        targetSummary = evidence.targetSummary
        failureReason = evidence.failureReason
    }
}

struct PublicHeistInvocationEvidence: Encodable {
    let capability: String
    let argument: String?
    let childFailedPath: String?
    let expectationResult: PublicActionResultOutput?
    let expectation: PublicExpectationResult?
    let expectationEvidence: PublicHeistWaitEvidence?

    init(
        invocation: HeistInvocationStep,
        evidence: HeistInvocationEvidence,
        profile: ProjectionProfile
    ) {
        self.capability = invocation.path.description
        self.argument = invocation.argument == .none ? nil : invocation.runHeistSummary
        self.childFailedPath = evidence.childFailedPath?.description
        self.expectationResult = evidence.expectationActionResult.map {
            PublicActionResultOutput(
                projection: ActionProjection(
                    actionMethod: .result($0.method),
                    result: $0,
                    profile: profile,
                    includeOmissions: true
                ),
                context: .heistReportEvidence
            )
        }
        self.expectation = evidence.expectation.map {
            PublicExpectationResult(projection: ExpectationProjection(result: $0))
        }
        self.expectationEvidence = evidence.waitEvidence.map {
            PublicHeistWaitEvidence(evidence: $0, profile: profile)
        }
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

struct PublicHeistExpectations: Encodable {
    let checked: Int
    let met: Int
    let allMet: Bool

    init(_ expectations: HeistReport.Expectations) {
        checked = expectations.checked
        met = expectations.met
        allMet = expectations.allMet
    }
}
