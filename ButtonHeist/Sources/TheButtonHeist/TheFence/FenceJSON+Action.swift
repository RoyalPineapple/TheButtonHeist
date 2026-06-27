import Foundation
import ThePlans

import AccessibilitySnapshotModel
import TheScore

struct PublicActionResponse: FencePublicJSONResponse {
    let status: PublicStatus
    let method: String
    let message: String?
    let value: String?
    let rotor: PublicRotorResult?
    let delta: PublicDelta?
    let screenName: String?
    let screenId: String?
    let errorClass: String?
    let errorCode: String?
    let phase: String?
    let retryable: Bool?
    let hint: String?
    let expectation: PublicExpectationResult?
    let activationTrace: ActivationTrace?
    let timing: ActionPerformanceTiming?

    init(command: TheFence.Command, result: ActionResult, expectation: ExpectationResult?) {
        self.init(projection: ActionProjection(
            method: command.rawValue,
            result: result,
            expectation: expectation,
            expectationHint: expectation.flatMap {
                FenceResponse.expectationFailureHint($0, command: command, result: result)
            },
            profile: .summary
        ))
    }

    init(
        method: String,
        result: ActionResult,
        expectation: ExpectationResult?,
        expectationHint: String? = nil
    ) {
        self.init(projection: ActionProjection(
            method: method,
            result: result,
            expectation: expectation,
            expectationHint: expectationHint,
            profile: .summary
        ))
    }

    init(projection: ActionProjection) {
        self.status = PublicStatus(projection.status)
        self.method = projection.method
        self.message = projection.message
        switch projection.payload {
        case .value(let value):
            self.value = value
            self.rotor = nil
        case .rotor(let rotor):
            self.value = nil
            self.rotor = PublicRotorResult(result: rotor)
        case .screenshot, .heistExecutionStepCount, .none:
            self.value = nil
            self.rotor = nil
        }
        self.delta = projection.delta.map { PublicDelta(projection: $0) }
        self.screenName = projection.screenName
        self.screenId = projection.screenId
        let failure = projection.failure
        self.errorClass = failure?.errorClass
        self.errorCode = failure?.errorCode
        self.phase = failure?.phase
        self.retryable = failure?.retryable
        self.hint = failure?.hint
        self.expectation = projection.expectation.map { PublicExpectationResult(projection: $0) }
        self.activationTrace = projection.activationTrace
        self.timing = projection.timing
    }

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
        if !success { return .error }
        if let expectation, !expectation.met { return .expectationFailed }
        return .ok
    }

    /// Error class surfaced to clients; nil on success.
    var publicErrorClass: String? {
        success ? nil : (errorKind ?? .actionFailed).rawValue
    }

    /// Canonical public failure projection shared by JSON and compact renderers.
    func publicFailureProjection(fallbackMessage: String) -> PublicActionFailureProjection? {
        guard !success else { return nil }
        return PublicActionFailureProjection(
            message: message ?? fallbackMessage,
            errorClass: publicErrorClass ?? ErrorKind.actionFailed.rawValue,
            details: publicFailureDetails
        )
    }

    /// Structured failure metadata for the diagnosable accessibility-tree case.
    var publicFailureDetails: FailureDetails? {
        guard !success else { return nil }
        guard errorKind == nil || errorKind == .actionFailed,
              message == Self.accessibilityTreeUnavailableMessage
        else { return nil }
        return FailureDetails(
            errorCode: "request.accessibility_tree_unavailable",
            phase: .request,
            retryable: true,
            hint: "Wait for a traversable app window, then refresh the interface or retry the command."
        )
    }

    // Keep in sync with `TheBrains.treeUnavailableMessage`; bridges tree-unavailable
    // `actionFailed` wire results to local diagnostics.
    static let accessibilityTreeUnavailableMessage =
        "Could not access accessibility tree: no traversable app windows"
}

struct PublicActionFailureProjection {
    let message: String
    let errorClass: String
    let details: FailureDetails?

    var errorCode: String? { details?.errorCode }
    var phase: String? { details?.phase.rawValue }
    var retryable: Bool? { details?.retryable }
    var hint: String? { details?.hint }
    var compactCode: String { errorCode ?? errorClass }
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
    let expected: AccessibilityPredicate?
    let hint: String?

    init(result: ExpectationResult, hint: String? = nil) {
        self.met = result.met
        self.actual = result.actual
        self.expected = result.predicate
        self.hint = hint
    }

    init(projection: ExpectationProjection) {
        self.met = projection.met
        self.actual = projection.actual
        self.expected = projection.expected
        self.hint = projection.hint
    }
}

struct PublicDelta: Encodable {
    let kind: String
    let elementCount: Int
    let captureEdge: AccessibilityTrace.CaptureEdge?
    let transient: [PublicElement]?
    let edits: PublicElementEdits?
    let newInterface: PublicInterface?

    init(delta: AccessibilityTrace.Delta) {
        self.init(projection: DeltaProjection(delta: delta, profile: .summary, includeScreenInterface: true))
    }

    init(projection: DeltaProjection) {
        switch projection.kind {
        case .noChange:
            self.kind = AccessibilityTrace.DeltaKind.noChange.rawValue
            self.elementCount = projection.elementCount
            self.captureEdge = projection.captureEdge
            self.transient = projection.transient.elements.isEmpty
                ? nil
                : projection.transient.elements.map { PublicElement(element: $0, detail: .summary) }
            self.edits = nil
            self.newInterface = nil
        case .elementsChanged:
            self.kind = AccessibilityTrace.DeltaKind.elementsChanged.rawValue
            self.elementCount = projection.elementCount
            self.captureEdge = projection.captureEdge
            self.transient = projection.transient.elements.isEmpty
                ? nil
                : projection.transient.elements.map { PublicElement(element: $0, detail: .summary) }
            if let edits = projection.edits.map({ PublicElementEdits(projection: $0) }) {
                self.edits = edits.isEmpty ? nil : edits
            } else {
                self.edits = nil
            }
            self.newInterface = nil
        case .screenChanged:
            self.kind = AccessibilityTrace.DeltaKind.screenChanged.rawValue
            self.elementCount = projection.elementCount
            self.captureEdge = projection.captureEdge
            self.transient = projection.transient.elements.isEmpty
                ? nil
                : projection.transient.elements.map { PublicElement(element: $0, detail: .summary) }
            self.edits = nil
            self.newInterface = projection.screen?.interface.map { PublicInterface(interface: $0, detail: .summary) }
        }
    }
}

struct PublicElementEdits: Encodable {
    let added: [PublicElement]?
    let removed: [PublicElement]?
    let updated: [PublicElementUpdate]?

    var isEmpty: Bool {
        added == nil && removed == nil && updated == nil
    }

    init(edits: ElementEdits) {
        self.added = edits.added.isEmpty ? nil : edits.added.map { PublicElement(element: $0, detail: .summary) }
        self.removed = edits.removed.isEmpty ? nil : edits.removed.map { PublicElement(element: $0, detail: .summary) }
        let filteredUpdates = edits.updated.compactMap { PublicElementUpdate(update: $0) }
        self.updated = filteredUpdates.isEmpty ? nil : filteredUpdates
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
    }
}

struct PublicElementUpdate: Encodable {
    let before: PublicElement
    let after: PublicElement
    let changes: [PropertyChange]

    init?(update: ElementUpdate) {
        let meaningfulChanges = update.changes.filter { !$0.property.isGeometry }
        guard !meaningfulChanges.isEmpty else { return nil }
        self.before = PublicElement(element: update.before, detail: .summary)
        self.after = PublicElement(element: update.after, detail: .summary)
        self.changes = meaningfulChanges
    }
}

struct PublicHeistExecutionResponse: FencePublicJSONResponse {
    let status: PublicStatus
    let report: PublicHeistReport
    let executedTopLevelStepCount: Int
    let executedNodeCount: Int
    let outputReceiptNodeCount: Int
    let durationMs: Int
    let abortedAtPath: String?
    let expectations: PublicHeistExpectations?
    let netDelta: PublicDelta?

    init(result: HeistExecutionResult, netDelta: AccessibilityTrace.Delta?) {
        self.init(projection: HeistReportProjection(result: result, netDelta: netDelta, profile: .mcp))
    }

    init(projection: HeistReportProjection) {
        self.status = PublicStatus(projection.status)
        self.report = PublicHeistReport(projection: projection)
        self.executedTopLevelStepCount = projection.summary.executedTopLevelStepCount
        self.executedNodeCount = projection.summary.executedNodeCount
        self.outputReceiptNodeCount = projection.summary.outputReceiptNodeCount
        self.durationMs = projection.summary.durationMs
        self.abortedAtPath = projection.summary.abortedAtPath
        self.expectations = projection.summary.expectations.map { PublicHeistExpectations(projection: $0) }
        self.netDelta = projection.netDelta.map { PublicDelta(projection: $0) }
    }
}

struct PublicHeistReport: Encodable {
    let summary: PublicHeistReportSummary
    let nodes: [PublicHeistReportNode]

    init(result: HeistExecutionResult) {
        self.init(projection: HeistReportProjection(result: result, netDelta: nil, profile: .mcp))
    }

    init(projection: HeistReportProjection) {
        self.summary = PublicHeistReportSummary(projection: projection.summary)
        self.nodes = projection.nodes.map { PublicHeistReportNode(projection: $0) }
    }
}

struct PublicHeistReportSummary: Encodable {
    let executedTopLevelStepCount: Int
    let executedNodeCount: Int
    let outputReceiptNodeCount: Int
    let abortedAtPath: String?
    let durationMs: Int
    let expectations: PublicHeistExpectations?

    init(result: HeistExecutionResult) {
        self.init(projection: HeistReportProjection(result: result, netDelta: nil, profile: .mcp).summary)
    }

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
    let failure: HeistFailureDetail?
    let abortedAtChildPath: String?
    let expectation: PublicExpectationResult?
    let children: [PublicHeistReportNode]

    init(step: HeistExecutionStepResult) {
        self.init(projection: HeistReportNodeProjection(step: step, profile: .mcp))
    }

    init(projection: HeistReportNodeProjection) {
        self.path = projection.path.rawValue
        self.kind = projection.kind
        self.capability = projection.capability
        self.status = projection.status.rawValue
        self.message = projection.message
        self.durationMs = projection.durationMs
        self.intent = projection.intent
        self.evidence = projection.evidence.flatMap { PublicHeistReportEvidence(projection: $0) }
        self.failure = projection.failure
        self.abortedAtChildPath = projection.abortedAtChildPath
        self.expectation = projection.expectation.map { PublicExpectationResult(projection: $0) }
        self.children = projection.children.map { PublicHeistReportNode(projection: $0) }
    }
}

struct PublicHeistReportEvidence: Encodable {
    let action: PublicHeistActionEvidence?
    let wait: PublicHeistWaitEvidence?
    let caseSelection: PublicHeistCaseSelectionEvidence?
    let forEachString: PublicHeistForEachStringEvidence?
    let forEachElement: PublicHeistForEachElementEvidence?
    let repeatUntil: PublicHeistRepeatUntilEvidence?
    let invocation: PublicHeistInvocationEvidence?
    let warning: PublicHeistWarningEvidence?

    init?(
        step: HeistExecutionStepResult
    ) {
        self.init(projection: HeistReportNodeProjection(step: step, profile: .mcp).evidence)
    }

    init?(projection: HeistReportEvidenceProjection?) {
        guard let projection else { return nil }
        self.init(
            action: projection.action.map { PublicHeistActionEvidence(projection: $0) },
            wait: projection.wait.map { PublicHeistWaitEvidence(projection: $0) },
            caseSelection: projection.caseSelection.map { PublicHeistCaseSelectionEvidence(projection: $0) },
            forEachString: projection.forEachString.map { PublicHeistForEachStringEvidence(projection: $0) },
            forEachElement: projection.forEachElement.map { PublicHeistForEachElementEvidence(projection: $0) },
            repeatUntil: projection.repeatUntil.map { PublicHeistRepeatUntilEvidence(projection: $0) },
            invocation: projection.invocation.map { PublicHeistInvocationEvidence(projection: $0) },
            warning: projection.warning.map { PublicHeistWarningEvidence(projection: $0) }
        )
    }

    private init(
        action: PublicHeistActionEvidence? = nil,
        wait: PublicHeistWaitEvidence? = nil,
        caseSelection: PublicHeistCaseSelectionEvidence? = nil,
        forEachString: PublicHeistForEachStringEvidence? = nil,
        forEachElement: PublicHeistForEachElementEvidence? = nil,
        repeatUntil: PublicHeistRepeatUntilEvidence? = nil,
        invocation: PublicHeistInvocationEvidence? = nil,
        warning: PublicHeistWarningEvidence? = nil
    ) {
        self.action = action
        self.wait = wait
        self.caseSelection = caseSelection
        self.forEachString = forEachString
        self.forEachElement = forEachElement
        self.repeatUntil = repeatUntil
        self.invocation = invocation
        self.warning = warning
    }
}

struct PublicHeistActionEvidence: Encodable {
    let commandName: String?
    let target: ElementTarget?
    let result: PublicHeistReportActionResult?
    let expectationResult: PublicHeistReportActionResult?
    let expectation: PublicExpectationResult?

    init(evidence: HeistActionEvidence) {
        self.init(projection: HeistActionEvidenceProjection(evidence: evidence, profile: .mcp))
    }

    init(projection: HeistActionEvidenceProjection) {
        self.commandName = projection.commandName
        self.target = projection.target
        self.result = projection.result.map { PublicHeistReportActionResult(projection: $0) }
        self.expectationResult = projection.expectationResult.map { PublicHeistReportActionResult(projection: $0) }
        self.expectation = projection.expectation.map { PublicExpectationResult(projection: $0) }
    }
}

struct PublicHeistWaitEvidence: Encodable {
    let result: PublicHeistReportActionResult
    let expectation: PublicExpectationResult
    let baselineSummary: String?
    let finalSummary: String?

    init(evidence: HeistWaitEvidence) {
        self.init(projection: HeistWaitEvidenceProjection(evidence: evidence, profile: .mcp))
    }

    init(projection: HeistWaitEvidenceProjection) {
        self.result = PublicHeistReportActionResult(projection: projection.result)
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

    init(evidence: HeistCaseSelectionEvidence) {
        self.init(projection: HeistCaseSelectionEvidenceProjection(evidence: evidence, profile: .mcp))
    }

    init(projection: HeistCaseSelectionEvidenceProjection) {
        self.outcome = projection.outcome
        self.elapsedMs = projection.elapsedMs
        self.timeout = projection.timeout
        self.lastObservedSummary = projection.lastObservedSummary
        self.caseCount = projection.caseCount
        self.cases = projection.cases.isEmpty ? nil : projection.cases.map { PublicHeistCaseMatchResult(projection: $0) }
        self.omittedCaseCount = projection.omittedCaseCount
    }
}

struct PublicHeistCaseMatchResult: Encodable {
    let predicate: AccessibilityPredicate
    let met: Bool
    let actual: String?

    init(match: HeistCaseMatchResult) {
        self.init(projection: HeistCaseMatchProjection(match: match))
    }

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

    init(evidence: HeistForEachStringEvidence) {
        self.init(projection: HeistForEachStringEvidenceProjection(evidence: evidence))
    }

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

    init(evidence: HeistForEachElementEvidence) {
        self.init(projection: HeistForEachElementEvidenceProjection(evidence: evidence))
    }

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
    let predicate: AccessibilityPredicate
    let timeout: Double
    let iterationCount: Int
    let iterationOrdinal: Int?
    let expectation: PublicExpectationResult
    let result: PublicHeistReportActionResult?
    let lastObservedSummary: String?
    let failureReason: String?

    init(evidence: HeistRepeatUntilEvidence) {
        self.init(projection: HeistRepeatUntilEvidenceProjection(evidence: evidence, profile: .mcp))
    }

    init(projection: HeistRepeatUntilEvidenceProjection) {
        self.predicate = projection.predicate
        self.timeout = projection.timeout
        self.iterationCount = projection.iterationCount
        self.iterationOrdinal = projection.iterationOrdinal
        self.expectation = PublicExpectationResult(projection: projection.expectation)
        self.result = projection.result.map { PublicHeistReportActionResult(projection: $0) }
        self.lastObservedSummary = projection.lastObservedSummary
        self.failureReason = projection.failureReason
    }
}

struct PublicHeistInvocationEvidence: Encodable {
    let capability: String?
    let name: String?
    let argument: String?
    let childFailedPath: String?
    let expectationResult: PublicHeistReportActionResult?
    let expectation: PublicExpectationResult?

    init(evidence: HeistInvocationEvidence) {
        self.init(projection: HeistInvocationEvidenceProjection(evidence: evidence, profile: .mcp))
    }

    init(projection: HeistInvocationEvidenceProjection) {
        self.capability = projection.capability
        self.name = projection.name
        self.argument = projection.argument
        self.childFailedPath = projection.childFailedPath
        self.expectationResult = projection.expectationResult.map { PublicHeistReportActionResult(projection: $0) }
        self.expectation = projection.expectation.map { PublicExpectationResult(projection: $0) }
    }
}

struct PublicHeistWarningEvidence: Encodable {
    let path: String
    let message: String

    init(warning: HeistExecutionWarning) {
        self.init(projection: HeistWarningEvidenceProjection(warning: warning))
    }

    init(projection: HeistWarningEvidenceProjection) {
        self.path = projection.path
        self.message = projection.message
    }
}

struct PublicHeistReportActionResult: Encodable {
    let status: PublicStatus
    let method: String
    let message: String?
    let value: String?
    let rotor: PublicRotorResult?
    let delta: PublicHeistDelta?
    let screenName: String?
    let screenId: String?
    let errorClass: String?
    let errorCode: String?
    let phase: String?
    let retryable: Bool?
    let hint: String?
    let activationTrace: ActivationTrace?
    let timing: ActionPerformanceTiming?
    let omitted: PublicHeistActionResultOmissions?

    init(method: String, result: ActionResult) {
        self.init(projection: ActionProjection(
            method: method,
            result: result,
            profile: .mcp,
            includeOmissions: true
        ))
    }

    init(projection: ActionProjection) {
        self.status = PublicStatus(projection.status)
        self.method = projection.method
        self.message = projection.message
        switch projection.payload {
        case .value(let value):
            self.value = value
            self.rotor = nil
        case .rotor(let rotor):
            self.value = nil
            self.rotor = PublicRotorResult(result: rotor)
        case .screenshot, .heistExecutionStepCount, .none:
            self.value = nil
            self.rotor = nil
        }
        self.delta = projection.delta.map { PublicHeistDelta(projection: $0) }
        self.screenName = projection.screenName
        self.screenId = projection.screenId
        let failure = projection.failure
        self.errorClass = failure?.errorClass
        self.errorCode = failure?.errorCode
        self.phase = failure?.phase
        self.retryable = failure?.retryable
        self.hint = failure?.hint
        self.activationTrace = projection.activationTrace
        self.timing = projection.timing
        self.omitted = projection.omitted.flatMap {
            let omissions = PublicHeistActionResultOmissions(projection: $0)
            return omissions.isEmpty ? nil : omissions
        }
    }
}

struct PublicHeistActionResultOmissions: Encodable {
    let accessibilityTrace: PublicProjectionOmission?
    let subjectEvidence: PublicProjectionOmission?

    var isEmpty: Bool {
        accessibilityTrace == nil && subjectEvidence == nil
    }

    init(result: ActionResult) {
        self.init(projection: ActionResultOmissionsProjection(result: result))
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

    init(reason: String, projectedAs: String?, omittedCount: Int?) {
        self.reason = reason
        self.projectedAs = projectedAs
        self.omittedCount = omittedCount
    }

    init(projection: ProjectionOmission) {
        self.reason = projection.reason
        self.projectedAs = projection.projectedAs
        self.omittedCount = projection.omittedCount
    }
}

struct PublicHeistDelta: Encodable {
    let kind: String
    let elementCount: Int
    let captureEdge: AccessibilityTrace.CaptureEdge?
    let transient: [PublicElement]?
    let edits: PublicHeistElementEdits?
    let screen: PublicHeistScreenProjection?
    let omitted: PublicHeistDeltaOmissions?

    init(delta: AccessibilityTrace.Delta) {
        self.init(projection: DeltaProjection(delta: delta, profile: .mcp, includeScreenInterface: false))
    }

    init(projection: DeltaProjection) {
        switch projection.kind {
        case .noChange:
            let transient = Self.elements(projection.transient.elements)
            self.kind = AccessibilityTrace.DeltaKind.noChange.rawValue
            self.elementCount = projection.elementCount
            self.captureEdge = projection.captureEdge
            self.transient = transient.isEmpty ? nil : transient
            self.edits = nil
            self.screen = nil
            let omitted = PublicHeistDeltaOmissions(transient: projection.transient.omittedCount)
            self.omitted = omitted.isEmpty ? nil : omitted

        case .elementsChanged:
            let transient = Self.elements(projection.transient.elements)
            let edits = projection.edits.map { PublicHeistElementEdits(projection: $0) }
            self.kind = AccessibilityTrace.DeltaKind.elementsChanged.rawValue
            self.elementCount = projection.elementCount
            self.captureEdge = projection.captureEdge
            self.transient = transient.isEmpty ? nil : transient
            self.edits = edits?.isEmpty == false ? edits : nil
            self.screen = nil
            let omitted = PublicHeistDeltaOmissions(transient: projection.transient.omittedCount)
            self.omitted = omitted.isEmpty ? nil : omitted

        case .screenChanged:
            let transient = Self.elements(projection.transient.elements)
            self.kind = AccessibilityTrace.DeltaKind.screenChanged.rawValue
            self.elementCount = projection.elementCount
            self.captureEdge = projection.captureEdge
            self.transient = transient.isEmpty ? nil : transient
            self.edits = nil
            self.screen = projection.screen.map { PublicHeistScreenProjection(projection: $0) }
            let omitted = PublicHeistDeltaOmissions(transient: projection.transient.omittedCount)
            self.omitted = omitted.isEmpty ? nil : omitted
        }
    }

    private static func elements(_ elements: [HeistElement]) -> [PublicElement] {
        elements.map { PublicElement(element: $0, detail: .summary) }
    }
}

struct PublicHeistElementEdits: Encodable {
    let added: [PublicElement]?
    let removed: [PublicElement]?
    let updated: [PublicElementUpdate]?
    let omitted: PublicHeistElementEditOmissions?

    var isEmpty: Bool {
        added == nil && removed == nil && updated == nil && omitted == nil
    }

    init(edits: ElementEdits) {
        self.init(projection: DeltaEditsProjection(edits: edits, profile: .mcp))
    }

    init(projection: DeltaEditsProjection) {
        let added = Self.elements(projection.added.elements)
        let removed = Self.elements(projection.removed.elements)
        let updated = projection.updated.updates.compactMap(PublicElementUpdate.init(update:))
        self.added = added.isEmpty ? nil : added
        self.removed = removed.isEmpty ? nil : removed
        self.updated = updated.isEmpty ? nil : updated
        let omitted = PublicHeistElementEditOmissions(
            added: projection.added.omittedCount,
            removed: projection.removed.omittedCount,
            updated: projection.updated.omittedCount
        )
        self.omitted = omitted.isEmpty ? nil : omitted
    }

    private static func elements(_ elements: [HeistElement]) -> [PublicElement] {
        elements.map { PublicElement(element: $0, detail: .summary) }
    }
}

struct PublicHeistElementEditOmissions: Encodable {
    let added: Int?
    let removed: Int?
    let updated: Int?

    var isEmpty: Bool {
        added == nil && removed == nil && updated == nil
    }
}

struct PublicHeistDeltaOmissions: Encodable {
    let transient: Int?

    var isEmpty: Bool {
        transient == nil
    }
}

struct PublicHeistScreenProjection: Encodable {
    let screenDescription: String
    let screenId: String?
    let elementCount: Int
    let elements: [PublicElement]?
    let omittedElementCount: Int?

    init(interface: Interface) {
        self.init(projection: DeltaScreenProjection(interface: interface, profile: .mcp, includeInterface: false))
    }

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

    init(checked: Int, met: Int) {
        self.checked = checked
        self.met = met
        self.allMet = checked == met
    }

    init(projection: HeistExpectationsProjection) {
        self.checked = projection.checked
        self.met = projection.met
        self.allMet = projection.allMet
    }
}
