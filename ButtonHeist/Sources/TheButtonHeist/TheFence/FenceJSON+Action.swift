import Foundation
import ThePlans

import AccessibilitySnapshotModel
import TheScore

private enum PublicActionResultCodingKey: String, CodingKey {
    case status
    case method
    case message
    case warning
    case announcement
    case value
    case rotor
    case screenshot
    case heistExecution
    case delta
    case screenName
    case screenId
    case errorClass
    case code
    case kind
    case phase
    case retryable
    case hint
    case expectation
    case activationTrace
    case timing
    case omitted
}

struct PublicActionResponse: FencePublicJSONResponse {
    private let projection: ActionProjection

    init(command: TheFence.Command, result: ActionResult, expectation: ExpectationResult?) {
        self.init(projection: ActionProjection(
            actionMethod: .fence(command),
            result: result,
            expectation: expectation,
            expectationHint: expectation.flatMap {
                FenceResponse.expectationFailureHint($0, command: command, result: result)
            },
            profile: .summary
        ))
    }

    init(projection: ActionProjection) {
        self.projection = projection
    }

    func encode(to encoder: Encoder) throws {
        try PublicActionResultOutput(projection: projection, context: .standaloneAction).encode(to: encoder)
    }

}

enum PublicActionResultContext: Sendable, Equatable {
    case standaloneAction
    case heistReportEvidence

    var includesExpectation: Bool {
        self == .standaloneAction
    }

    var includesOmissions: Bool {
        self == .heistReportEvidence
    }

    var deltaScreenPolicy: PublicDeltaScreenPolicy {
        switch self {
        case .standaloneAction:
            return .newInterface
        case .heistReportEvidence:
            return .screenSummary
        }
    }
}

struct PublicActionResultOutput: Encodable {
    let projection: ActionProjection
    let context: PublicActionResultContext

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PublicActionResultCodingKey.self)
        try container.encode(PublicStatus(projection.status), forKey: .status)
        try container.encode(projection.actionMethod.rawValue, forKey: .method)
        try container.encodeIfPresent(projection.message, forKey: .message)
        try container.encodeIfPresent(projection.warning, forKey: .warning)
        try container.encodeIfPresent(projection.announcement, forKey: .announcement)
        try encodePayload(to: &container)
        try container.encodeIfPresent(
            projection.delta.map { PublicDelta(projection: $0, screenPolicy: context.deltaScreenPolicy) },
            forKey: .delta
        )
        try container.encodeIfPresent(projection.screenName, forKey: .screenName)
        try container.encodeIfPresent(projection.screenId, forKey: .screenId)
        try encodeFailure(to: &container)
        if context.includesExpectation {
            try container.encodeIfPresent(
                projection.expectation.map { PublicExpectationResult(projection: $0) },
                forKey: .expectation
            )
        }
        try container.encodeIfPresent(projection.activationTrace, forKey: .activationTrace)
        try container.encodeIfPresent(projection.timing, forKey: .timing)
        if context.includesOmissions {
            let omitted = projection.omitted.flatMap {
                let omissions = PublicHeistActionResultOmissions(projection: $0)
                return omissions.isEmpty ? nil : omissions
            }
            try container.encodeIfPresent(omitted, forKey: .omitted)
        }
    }

    private func encodePayload(to container: inout KeyedEncodingContainer<PublicActionResultCodingKey>) throws {
        switch projection.payload {
        case .value(let value):
            try container.encode(value, forKey: .value)
        case .rotor(let rotor):
            try container.encode(PublicRotorResult(result: rotor), forKey: .rotor)
        case .screenshot(let width, let height):
            try container.encode(PublicScreenshotResult(width: width, height: height), forKey: .screenshot)
        case .heistExecutionStepCount(let stepCount):
            try container.encode(PublicHeistExecutionActionResult(stepCount: stepCount), forKey: .heistExecution)
        case .none:
            break
        }
    }

    private func encodeFailure(to container: inout KeyedEncodingContainer<PublicActionResultCodingKey>) throws {
        guard let failure = projection.failure else { return }
        try container.encode(failure.errorClass, forKey: .errorClass)
        try container.encode(failure.code, forKey: .code)
        try container.encode(failure.kind, forKey: .kind)
        try container.encode(failure.phase, forKey: .phase)
        try container.encode(failure.retryable, forKey: .retryable)
        try container.encodeIfPresent(failure.hint, forKey: .hint)
    }
}

struct PublicScreenshotResult: Encodable {
    let width: Double
    let height: Double
}

struct PublicHeistExecutionActionResult: Encodable {
    let stepCount: Int
}

/// Status vocabulary for public command responses.
enum PublicResponseStatus: String, Sendable, Equatable {
    case ok
    case error
    case expectationFailed = "expectation_failed"
    case partial
}

extension ActionResult {
    /// Status for this action result and its optional expectation. The
    /// expectation only influences status on an otherwise successful action.
    func publicStatus(expectation: ExpectationResult?) -> PublicResponseStatus {
        if !outcome.isSuccess { return .error }
        if let expectation, !expectation.met { return .expectationFailed }
        return .ok
    }

    /// Canonical public failure projection shared by JSON and compact renderers.
    func diagnosticFailureProjection(fallbackMessage: String) -> ActionFailureProjection? {
        guard !outcome.isSuccess else { return nil }
        let resolvedErrorKind = outcome.errorKind ?? .actionFailed
        return ActionFailureProjection(
            message: message ?? fallbackMessage,
            errorClass: resolvedErrorKind.rawValue,
            diagnosticFailure: DiagnosticFailureMapper.map(
                errorKind: resolvedErrorKind,
                message: message ?? fallbackMessage
            )
        )
    }
}

struct ActionFailureProjection {
    let message: String
    let errorClass: String
    let diagnosticFailure: DiagnosticFailure

    var code: String { diagnosticFailure.code }
    var kind: String { diagnosticFailure.kind.rawValue }
    var phase: String { diagnosticFailure.phase.rawValue }
    var retryable: Bool { diagnosticFailure.retryable }
    var hint: String? { diagnosticFailure.hint }
    var compactCode: String { code }
}

struct PublicRotorResult: Encodable {
    let name: String
    let direction: String
    let found: HeistElement?
    let textRange: PublicRotorTextRange?

    init(result: RotorResult) {
        self.name = result.rotor
        self.direction = result.direction.rawValue
        self.found = result.foundElement
        self.textRange = result.textRange.map { PublicRotorTextRange(range: $0) }
    }
}

struct PublicRotorTextRange: Encodable {
    let rangeDescription: String
    let text: String?
    let startOffset: Int?
    let endOffset: Int?

    init(range: RotorTextRange) {
        self.rangeDescription = range.rangeDescription
        self.text = range.text
        self.startOffset = range.startOffset
        self.endOffset = range.endOffset
    }
}

struct PublicExpectationResult: Encodable {
    let met: Bool
    let actual: String?
    let expected: AccessibilityPredicate<RootContext>?
    let hint: String?

    init(projection: ExpectationProjection) {
        self.met = projection.met
        self.actual = projection.actual
        self.expected = projection.expected
        self.hint = projection.hint
    }
}

enum PublicDeltaScreenPolicy: Sendable {
    case newInterface
    case screenSummary
}

struct PublicDelta: Encodable {
    let projection: DeltaProjection
    let screenPolicy: PublicDeltaScreenPolicy

    private enum CodingKeys: String, CodingKey {
        case kind
        case elementCount
        case captureEdge
        case interactionDigest
        case accessibilityNotifications
        case transient
        case edits
        case newInterface
        case screen
        case omitted
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch projection {
        case .noChange(let metadata):
            try encodeMetadata(metadata, kind: .noChange, to: &container)
            try encodeTransientOmissions(metadata.transient, to: &container)

        case .elementsChanged(let delta):
            try encodeMetadata(delta.metadata, kind: .elementsChanged, to: &container)
            let edits = PublicElementEdits(projection: delta.edits)
            try container.encodeIfPresent(edits.isEmpty ? nil : edits, forKey: .edits)
            try encodeTransientOmissions(delta.metadata.transient, to: &container)

        case .screenChanged(let delta):
            try encodeMetadata(delta.metadata, kind: .screenChanged, to: &container)
            switch screenPolicy {
            case .newInterface:
                try container.encodeIfPresent(
                    delta.screen.interface.map(PublicInterface.init(projection:)),
                    forKey: .newInterface
                )
            case .screenSummary:
                try container.encode(PublicHeistScreenProjection(projection: delta.screen), forKey: .screen)
            }
            try encodeTransientOmissions(delta.metadata.transient, to: &container)
        }
    }

    private func encodeMetadata(
        _ metadata: DeltaProjectionMetadata,
        kind: DeltaProjectionKind,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encode(metadata.elementCount, forKey: .elementCount)
        try container.encodeIfPresent(metadata.captureEdge, forKey: .captureEdge)
        try container.encodeIfPresent(metadata.interactionDigest, forKey: .interactionDigest)
        if !metadata.accessibilityNotifications.isEmpty {
            try container.encode(metadata.accessibilityNotifications, forKey: .accessibilityNotifications)
        }
        try container.encodeIfPresent(Self.elements(metadata.transient.elements), forKey: .transient)
    }

    private func encodeTransientOmissions(
        _ transient: ElementProjectionBucket,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        let transientOmissions = PublicHeistDeltaOmissions(projection: transient)
        try container.encodeIfPresent(transientOmissions.isEmpty ? nil : transientOmissions, forKey: .omitted)
    }

    private static func elements(_ elements: [HeistElement]) -> [PublicElement]? {
        guard !elements.isEmpty else { return nil }
        return elements.map { PublicElement(element: $0, detail: .summary) }
    }
}

struct PublicElementEdits: Encodable {
    let added: [PublicElement]?
    let removed: [PublicElement]?
    let updated: [PublicElementUpdate]?
    let omitted: PublicHeistElementEditOmissions?

    var isEmpty: Bool {
        added == nil && removed == nil && updated == nil && omitted == nil
    }

    init(projection: DeltaEditsProjection) {
        self.added = projection.added.elements.isEmpty
            ? nil
            : projection.added.elements.map { PublicElement(element: $0, detail: .summary) }
        self.removed = projection.removed.elements.isEmpty
            ? nil
            : projection.removed.elements.map { PublicElement(element: $0, detail: .summary) }
        self.updated = projection.updated.updates.isEmpty
            ? nil
            : projection.updated.updates.compactMap(PublicElementUpdate.init(update:))
        let omitted = PublicHeistElementEditOmissions(projection: projection)
        self.omitted = omitted.isEmpty ? nil : omitted
    }
}

struct PublicElementUpdate: Encodable {
    let before: PublicElement
    let after: PublicElement
    let changes: [PublicPropertyChange]

    init?(update: ElementUpdate) {
        let meaningfulChanges = update.changes.filter { !$0.property.isGeometry }
        guard !meaningfulChanges.isEmpty else { return nil }
        self.before = PublicElement(element: update.before, detail: .summary)
        self.after = PublicElement(element: update.after, detail: .summary)
        self.changes = meaningfulChanges.map(PublicPropertyChange.init(change:))
    }
}

struct PublicPropertyChange: Encodable {
    let property: ElementProperty
    let old: String?
    let new: String?

    init(change: PropertyChange) {
        self.property = change.property
        self.old = change.oldValue?.displayText
        self.new = change.newValue?.displayText
    }
}

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
    let intent: HeistStepIntent?
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
        self.intent = projection.intent
        self.evidence = projection.evidence.map { PublicHeistReportEvidence(projection: $0) }
        self.failure = projection.failure.map { PublicHeistFailureDetail(projection: $0) }
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
    let activationTrace: ActivationTrace?
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
        activationTrace = projection.detail.activationTrace
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
        case .warning(let projection):
            try container.encode(PublicHeistWarningEvidence(projection: projection), forKey: .warning)
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
        switch projection.evidence {
        case .commandResolutionFailure:
            break
        case .dispatch(let command, let result):
            try container.encode(
                PublicActionResultOutput(
                    projection: projection.actionResultProjection(result, actionMethod: .heist(command)),
                    context: .heistReportEvidence
                ),
                forKey: .result
            )
        case .commandlessDispatch(let result):
            try container.encode(
                PublicActionResultOutput(
                    projection: projection.actionResultProjection(result, actionMethod: .result(result.method)),
                    context: .heistReportEvidence
                ),
                forKey: .result
            )
        case .expectation(let command, let dispatchResult, let expectationResult, let expectation):
            try container.encode(
                PublicActionResultOutput(
                    projection: projection.actionResultProjection(dispatchResult, actionMethod: .heist(command)),
                    context: .heistReportEvidence
                ),
                forKey: .result
            )
            try container.encode(
                PublicActionResultOutput(
                    projection: projection.actionResultProjection(
                        expectationResult,
                        actionMethod: .result(expectationResult.method)
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
}

struct PublicHeistWaitEvidence: Encodable {
    let outcome: HeistPredicateEvidenceOutcome
    let result: PublicActionResultOutput
    let expectation: PublicExpectationResult
    let baselineSummary: String?
    let finalSummary: String?

    init(projection: HeistWaitEvidenceProjection) {
        self.outcome = projection.outcome
        self.result = PublicActionResultOutput(projection: projection.result, context: .heistReportEvidence)
        self.expectation = PublicExpectationResult(projection: projection.expectation)
        self.baselineSummary = projection.baselineSummary
        self.finalSummary = projection.finalSummary
    }
}

struct PublicHeistCaseSelectionEvidence: Encodable {
    let outcome: HeistCaseSelectionOutcome
    let elapsedMs: Int
    let timeout: Double?
    let lastObservedSummary: String?
    let caseCount: Int
    let cases: [PublicHeistCaseMatchResult]?
    let omittedCaseCount: Int?

    init(projection: HeistCaseSelectionEvidenceProjection) {
        self.outcome = projection.outcome
        self.elapsedMs = projection.elapsedMs
        self.timeout = projection.timeout
        self.lastObservedSummary = projection.lastObservedSummary
        self.caseCount = projection.caseCount
        self.cases = projection.cases.isEmpty
            ? nil
            : projection.cases.map { PublicHeistCaseMatchResult(projection: $0) }
        self.omittedCaseCount = projection.omittedCaseCount
    }
}

struct PublicHeistCaseMatchResult: Encodable {
    let predicate: AccessibilityPredicate<RootContext>
    let met: Bool
    let actual: String?

    init(projection: HeistCaseMatchProjection) {
        self.predicate = projection.predicate
        self.met = projection.met
        self.actual = projection.actual
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
        self.parameter = projection.parameter
        self.count = projection.count
        self.iterationCount = projection.iterationCount
        self.iterationOrdinal = projection.iterationOrdinal
        self.value = projection.value
        self.failureReason = projection.failureReason
    }
}

struct PublicHeistForEachElementEvidence: Encodable {
    let parameter: HeistReferenceName
    let matching: ElementPredicate
    let limit: Int
    let matchedCount: Int
    let iterationCount: Int
    let iterationOrdinal: Int?
    let targetOrdinal: Int?
    let targetSummary: String?
    let failureReason: String?

    init(projection: HeistForEachElementEvidenceProjection) {
        self.parameter = projection.parameter
        self.matching = projection.matching
        self.limit = projection.limit
        self.matchedCount = projection.matchedCount
        self.iterationCount = projection.iterationCount
        self.iterationOrdinal = projection.iterationOrdinal
        self.targetOrdinal = projection.targetOrdinal
        self.targetSummary = projection.targetSummary
        self.failureReason = projection.failureReason
    }
}

struct PublicHeistRepeatUntilEvidence: Encodable {
    let outcome: HeistPredicateEvidenceOutcome
    let predicate: AccessibilityPredicate<RootContext>
    let timeout: Double
    let iterationCount: Int
    let iterationOrdinal: Int?
    let expectation: PublicExpectationResult
    let result: PublicActionResultOutput?
    let lastObservedSummary: String?
    let failureReason: String?

    init(projection: HeistRepeatUntilEvidenceProjection) {
        self.outcome = projection.outcome
        self.predicate = projection.predicate
        self.timeout = projection.timeout
        self.iterationCount = projection.iterationCount
        self.iterationOrdinal = projection.iterationOrdinal
        self.expectation = PublicExpectationResult(projection: projection.expectation)
        self.result = projection.result.map {
            PublicActionResultOutput(projection: $0, context: .heistReportEvidence)
        }
        self.lastObservedSummary = projection.lastObservedSummary
        self.failureReason = projection.failureReason
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
        self.capability = projection.capability
        self.name = projection.name
        self.argument = projection.argument
        self.childFailedPath = projection.childFailedPath
        self.expectationResult = projection.expectationResult.map {
            PublicActionResultOutput(projection: $0, context: .heistReportEvidence)
        }
        self.expectation = projection.expectation.map { PublicExpectationResult(projection: $0) }
        self.expectationEvidence = projection.expectationEvidence.map { PublicHeistWaitEvidence(projection: $0) }
    }
}

struct PublicHeistWarningEvidence: Encodable {
    let path: String
    let message: String

    init(projection: HeistWarningEvidenceProjection) {
        self.path = projection.path
        self.message = projection.message
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
