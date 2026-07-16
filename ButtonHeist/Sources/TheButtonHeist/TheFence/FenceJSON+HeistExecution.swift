import Foundation
import ThePlans

import AccessibilitySnapshotModel
import TheScore

struct PublicHeistExecutionResponse: FencePublicJSONResponse {
    let status: PublicStatus
    let report: PublicHeistReport

    init(projection: HeistReportProjection) {
        self.status = PublicStatus(projection.status)
        self.report = PublicHeistReport(projection: projection)
    }
}
struct PublicHeistReport: Encodable {
    let summary: PublicHeistReportSummary
    let metrics: HeistExecutionMetricProjection
    let nodes: [PublicHeistReportNode]
    let netDelta: PublicDelta?

    init(projection: HeistReportProjection) {
        self.summary = PublicHeistReportSummary(projection: projection.summary)
        self.metrics = projection.metrics
        self.nodes = projection.nodes.map { PublicHeistReportNode(projection: $0) }
        self.netDelta = projection.netDelta.map { PublicDelta(projection: $0, screenPolicy: .screenSummary) }
    }
}

struct PublicHeistReportSummary: Encodable {
    let executedTopLevelStepCount: Int
    let executedNodeCount: Int
    let outputReceiptNodeCount: Int
    let abortedAtPath: String?
    let durationMs: Int
    let expectations: PublicHeistExpectations?

    init(projection: HeistReportSummaryProjection) {
        self.executedTopLevelStepCount = projection.executedTopLevelStepCount
        self.executedNodeCount = projection.executedNodeCount
        self.outputReceiptNodeCount = projection.outputReceiptNodeCount
        self.abortedAtPath = projection.abortedAtPath
        self.durationMs = projection.durationMs
        self.expectations = projection.expectations.map { PublicHeistExpectations(projection: $0) }
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

    init(projection: HeistReportNodeProjection) {
        self.path = projection.path
        self.kind = projection.kind.rawValue
        self.capability = projection.capability
        self.status = projection.status.rawValue
        self.message = projection.message
        self.durationMs = projection.durationMs
        self.evidence = projection.evidence.map { PublicHeistReportEvidence(projection: $0) }
        self.failure = projection.failure.map(PublicHeistFailureDetail.init)
        self.abortedAtChildPath = projection.abortedAtChildPath
        self.expectation = projection.expectation.map { PublicExpectationResult(projection: $0) }
        self.children = projection.children.map { PublicHeistReportNode(projection: $0) }
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

    init(projection: HeistReportFailureProjection) {
        category = projection.detail.category
        contract = projection.detail.contract
        observed = projection.detail.observed
        expected = projection.detail.expected
        code = projection.diagnosticFailure.code
        kind = projection.diagnosticFailure.kind.rawValue
        phase = projection.diagnosticFailure.phase.rawValue
        retryable = projection.diagnosticFailure.retryable
        hint = projection.diagnosticFailure.hint
    }
}

struct PublicHeistReportEvidence: Encodable {
    private let projection: HeistReportEvidenceProjection

    init(projection: HeistReportEvidenceProjection) {
        self.projection = projection
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
        switch projection {
        case .action(let projection):
            try container.encode(PublicHeistActionEvidence(projection: projection), forKey: .action)
        case .wait(let projection):
            try container.encode(PublicHeistWaitEvidence(projection: projection), forKey: .wait)
        case .caseSelection(let projection):
            try container.encode(PublicHeistCaseSelectionEvidence(projection: projection), forKey: .caseSelection)
        case .forEachString(let projection):
            try container.encode(PublicHeistForEachStringEvidence(projection: projection), forKey: .forEachString)
        case .forEachElement(let projection):
            try container.encode(PublicHeistForEachElementEvidence(projection: projection), forKey: .forEachElement)
        case .repeatUntil(let projection):
            try container.encode(PublicHeistRepeatUntilEvidence(projection: projection), forKey: .repeatUntil)
        case .invocation(let projection):
            try container.encode(PublicHeistInvocationEvidence(projection: projection), forKey: .invocation)
        case .warning(let evidence):
            try container.encode(evidence, forKey: .warning)
        }
    }
}

struct PublicHeistActionEvidence: Encodable {
    private let projection: HeistActionEvidenceProjection

    init(projection: HeistActionEvidenceProjection) {
        self.projection = projection
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
        try container.encodeIfPresent(projection.command?.rawValue, forKey: .commandName)
        try container.encodeIfPresent(projection.target, forKey: .target)
        switch projection {
        case .commandResolutionFailure:
            break
        case .dispatch(_, let result):
            try container.encode(
                PublicActionResultOutput(projection: result, context: .heistReportEvidence),
                forKey: .result
            )
        case .expectation(_, let dispatchResult, let expectationResult, let expectation):
            try container.encode(
                PublicActionResultOutput(projection: dispatchResult, context: .heistReportEvidence),
                forKey: .result
            )
            try container.encode(
                PublicActionResultOutput(projection: expectationResult, context: .heistReportEvidence),
                forKey: .expectationResult
            )
            try container.encode(
                PublicExpectationResult(projection: expectation),
                forKey: .expectation
            )
        }
    }
}

struct PublicHeistWaitEvidence: Encodable {
    let outcome: HeistPredicateEvidenceOutcome
    let result: PublicActionResultOutput
    let expectation: PublicExpectationResult
    let baselineSummary: String?
    let finalSummary: String?

    init(projection: HeistWaitEvidenceProjection) {
        self.outcome = projection.evidence.outcome
        self.result = PublicActionResultOutput(projection: projection.result, context: .heistReportEvidence)
        self.expectation = PublicExpectationResult(projection: projection.expectation)
        self.baselineSummary = projection.evidence.baselineSummary
        self.finalSummary = projection.evidence.finalSummary
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

    init(projection: HeistCaseSelectionEvidenceProjection) {
        let selection = projection.evidence.selection
        self.outcome = selection.outcome
        self.elapsedMs = selection.elapsedMs
        self.timeout = selection.timeout
        self.lastObservedSummary = selection.lastObservedSummary
        self.caseCount = selection.cases.count
        self.cases = projection.visibleCases.isEmpty
            ? nil
            : projection.visibleCases
        self.omittedCaseCount = projection.omittedCaseCount
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

    init(projection: HeistRepeatUntilEvidenceProjection) {
        self.outcome = projection.evidence.outcome
        self.predicate = projection.declaration.predicate
        self.timeout = projection.declaration.timeout.seconds
        self.iterationCount = projection.evidence.iterationCount
        self.iterationOrdinal = projection.evidence.iterationOrdinal
        self.expectation = PublicExpectationResult(projection: projection.expectation)
        self.result = projection.result.map {
            PublicActionResultOutput(projection: $0, context: .heistReportEvidence)
        }
        self.lastObservedSummary = projection.evidence.lastObservedSummary
        self.failureReason = projection.evidence.failureReason
    }
}

struct PublicHeistForEachStringEvidence: Encodable {
    let parameter: HeistReferenceName
    let count: Int
    let iterationCount: Int
    let iterationOrdinal: Int?
    let value: String?
    let failureReason: String?

    init(projection: HeistForEachStringEvidenceProjection) {
        parameter = projection.declaration.parameter
        count = projection.declaration.count
        iterationCount = projection.evidence.iterationCount
        iterationOrdinal = projection.evidence.iterationOrdinal
        value = projection.evidence.value
        failureReason = projection.evidence.failureReason
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

    init(projection: HeistForEachElementEvidenceProjection) {
        parameter = projection.declaration.parameter
        matching = projection.declaration.matching
        limit = projection.declaration.limit
        matchedCount = projection.evidence.matchedCount
        iterationCount = projection.evidence.iterationCount
        iterationOrdinal = projection.evidence.iterationOrdinal
        targetOrdinal = projection.evidence.targetOrdinal
        targetSummary = projection.evidence.targetSummary
        failureReason = projection.evidence.failureReason
    }
}

struct PublicHeistInvocationEvidence: Encodable {
    let capability: String?
    let name: String?
    let argument: String?
    let childFailedPath: String?
    let expectationResult: PublicActionResultOutput?
    let expectation: PublicExpectationResult?
    let expectationEvidence: PublicHeistWaitEvidence?

    init(projection: HeistInvocationEvidenceProjection) {
        self.capability = projection.invocation.path.description
        self.name = projection.invocation.path.description
        self.argument = projection.argumentSummary
        self.childFailedPath = projection.evidence.childFailedPath?.description
        self.expectationResult = projection.expectation.map {
            PublicActionResultOutput(projection: $0.result, context: .heistReportEvidence)
        }
        self.expectation = projection.expectation.map {
            PublicExpectationResult(projection: $0.expectation)
        }
        self.expectationEvidence = projection.expectation.flatMap(\.waitEvidence).map {
            PublicHeistWaitEvidence(projection: $0)
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

    init(projection: HeistExpectationsProjection) {
        self.checked = projection.checked
        self.met = projection.met
        self.allMet = projection.allMet
    }
}
