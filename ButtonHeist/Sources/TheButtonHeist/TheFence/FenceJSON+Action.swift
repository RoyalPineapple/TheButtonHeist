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
    let interactionDigest: AccessibilityTrace.InteractionDigest?
    let transient: [PublicElement]?
    let edits: PublicElementEdits?
    let newInterface: PublicInterface?

    init(projection: DeltaProjection) {
        switch projection.kind {
        case .noChange:
            self.kind = projection.kind.rawValue
            self.elementCount = projection.elementCount
            self.captureEdge = projection.captureEdge
            self.interactionDigest = projection.interactionDigest
            self.transient = projection.transient.elements.isEmpty
                ? nil
                : projection.transient.elements.map { PublicElement(element: $0, detail: .summary) }
            self.edits = nil
            self.newInterface = nil
        case .elementsChanged:
            self.kind = projection.kind.rawValue
            self.elementCount = projection.elementCount
            self.captureEdge = projection.captureEdge
            self.interactionDigest = projection.interactionDigest
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
            self.kind = projection.kind.rawValue
            self.elementCount = projection.elementCount
            self.captureEdge = projection.captureEdge
            self.interactionDigest = projection.interactionDigest
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

    init(projection: HeistReportNodeProjection) {
        self.path = projection.path
        self.kind = projection.kind
        self.capability = projection.capability
        self.status = projection.status.rawValue
        self.message = projection.message
        self.durationMs = projection.durationMs
        self.intent = projection.intent
        self.evidence = projection.evidence.map { PublicHeistReportEvidence(projection: $0) }
        self.failure = projection.failure
        self.abortedAtChildPath = projection.abortedAtChildPath
        self.expectation = projection.expectation.map { PublicExpectationResult(projection: $0) }
        self.children = projection.children.map { PublicHeistReportNode(projection: $0) }
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
    let commandName: String?
    let target: ElementTarget?
    let result: PublicHeistReportActionResult?
    let expectationResult: PublicHeistReportActionResult?
    let expectation: PublicExpectationResult?

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
    let predicate: AccessibilityPredicate
    let timeout: Double
    let iterationCount: Int
    let iterationOrdinal: Int?
    let expectation: PublicExpectationResult
    let result: PublicHeistReportActionResult?
    let lastObservedSummary: String?
    let failureReason: String?

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
        self.reason = projection.reason
        self.projectedAs = projection.projectedAs
        self.omittedCount = projection.omittedCount
    }
}

struct PublicHeistDelta: Encodable {
    let kind: String
    let elementCount: Int
    let captureEdge: AccessibilityTrace.CaptureEdge?
    let interactionDigest: AccessibilityTrace.InteractionDigest?
    let transient: [PublicElement]?
    let edits: PublicHeistElementEdits?
    let screen: PublicHeistScreenProjection?
    let omitted: PublicHeistDeltaOmissions?

    init(projection: DeltaProjection) {
        switch projection.kind {
        case .noChange:
            let transient = Self.elements(projection.transient.elements)
            self.kind = projection.kind.rawValue
            self.elementCount = projection.elementCount
            self.captureEdge = projection.captureEdge
            self.interactionDigest = projection.interactionDigest
            self.transient = transient.isEmpty ? nil : transient
            self.edits = nil
            self.screen = nil
            let omitted = PublicHeistDeltaOmissions(projection: projection.transient)
            self.omitted = omitted.isEmpty ? nil : omitted

        case .elementsChanged:
            let transient = Self.elements(projection.transient.elements)
            let edits = projection.edits.map { PublicHeistElementEdits(projection: $0) }
            self.kind = projection.kind.rawValue
            self.elementCount = projection.elementCount
            self.captureEdge = projection.captureEdge
            self.interactionDigest = projection.interactionDigest
            self.transient = transient.isEmpty ? nil : transient
            self.edits = edits?.isEmpty == false ? edits : nil
            self.screen = nil
            let omitted = PublicHeistDeltaOmissions(projection: projection.transient)
            self.omitted = omitted.isEmpty ? nil : omitted

        case .screenChanged:
            let transient = Self.elements(projection.transient.elements)
            self.kind = projection.kind.rawValue
            self.elementCount = projection.elementCount
            self.captureEdge = projection.captureEdge
            self.interactionDigest = projection.interactionDigest
            self.transient = transient.isEmpty ? nil : transient
            self.edits = nil
            self.screen = projection.screen.map { PublicHeistScreenProjection(projection: $0) }
            let omitted = PublicHeistDeltaOmissions(projection: projection.transient)
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

    init(projection: DeltaEditsProjection) {
        let added = Self.elements(projection.added.elements)
        let removed = Self.elements(projection.removed.elements)
        let updated = projection.updated.updates.compactMap(PublicElementUpdate.init(update:))
        self.added = added.isEmpty ? nil : added
        self.removed = removed.isEmpty ? nil : removed
        self.updated = updated.isEmpty ? nil : updated
        let omitted = PublicHeistElementEditOmissions(projection: projection)
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
