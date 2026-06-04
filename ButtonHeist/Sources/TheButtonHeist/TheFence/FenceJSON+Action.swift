import Foundation

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

    init(projection: PublicActionProjection) {
        self.status = PublicStatus(projection.status)
        self.method = projection.commandName
        self.message = projection.message
        self.value = projection.value
        self.rotor = projection.rotor.map(PublicRotorResult.init(result:))
        self.delta = projection.delta.map(PublicDelta.init)
        self.screenName = projection.screenName
        self.screenId = projection.screenId
        self.errorClass = projection.failure?.errorClass
        self.errorCode = projection.failure?.errorCode
        self.phase = projection.failure?.phase?.rawValue
        self.retryable = projection.failure?.retryable
        self.hint = projection.failure?.hint
        self.expectation = projection.expectation.map(PublicExpectationResult.init(projection:))
    }

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

    init(projection: PublicExpectationProjection) {
        self.met = projection.met
        self.actual = projection.actual
        self.expected = projection.expected
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
        switch delta {
        case .noChange(let payload):
            self.kind = AccessibilityTrace.DeltaKind.noChange.rawValue
            self.elementCount = payload.elementCount
            self.captureEdge = payload.captureEdge
            self.transient = payload.transient.isEmpty
                ? nil
                : payload.transient.map { PublicElement(element: $0, detail: .summary) }
            self.edits = nil
            self.newInterface = nil
        case .elementsChanged(let payload):
            self.kind = AccessibilityTrace.DeltaKind.elementsChanged.rawValue
            self.elementCount = payload.elementCount
            self.captureEdge = payload.captureEdge
            self.transient = payload.transient.isEmpty
                ? nil
                : payload.transient.map { PublicElement(element: $0, detail: .summary) }
            let edits = PublicElementEdits(edits: payload.edits)
            self.edits = edits.isEmpty ? nil : edits
            self.newInterface = nil
        case .screenChanged(let payload):
            self.kind = AccessibilityTrace.DeltaKind.screenChanged.rawValue
            self.elementCount = payload.elementCount
            self.captureEdge = payload.captureEdge
            self.transient = payload.transient.isEmpty
                ? nil
                : payload.transient.map { PublicElement(element: $0, detail: .summary) }
            self.edits = nil
            self.newInterface = PublicInterface(interface: payload.newInterface, detail: .summary)
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
}

struct PublicElementUpdate: Encodable {
    let element: PublicElement
    let changes: [PropertyChange]

    init?(update: ElementUpdate) {
        let meaningfulChanges = update.changes.filter { !$0.property.isGeometry }
        guard !meaningfulChanges.isEmpty else { return nil }
        self.element = PublicElement(element: update.element, detail: .summary)
        self.changes = meaningfulChanges
    }
}

struct PublicHeistExecutionResponse: FencePublicJSONResponse {
    let status: PublicStatus
    let report: PublicHeistReport
    let completedSteps: Int
    let totalTimingMs: Int
    let failedIndex: Int?
    let expectations: PublicHeistExpectations?
    let netDelta: PublicDelta?

    init(projection: PublicHeistExecutionProjection) {
        self.status = PublicStatus(projection.status)
        self.report = PublicHeistReport(projection: projection.report)
        self.completedSteps = projection.completedSteps
        self.totalTimingMs = projection.totalTimingMs
        self.failedIndex = projection.failedIndex
        self.expectations = projection.expectations.map(PublicHeistExpectations.init(projection:))
        self.netDelta = projection.netDelta.map(PublicDelta.init)
    }
}

struct PublicHeistReport: Encodable {
    let summary: PublicHeistReportSummary
    let nodes: [PublicHeistReportNode]

    init(projection: HeistReportProjection) {
        self.summary = PublicHeistReportSummary(summary: projection.summary)
        self.nodes = projection.nodes.map(PublicHeistReportNode.init(node:))
    }
}

struct PublicHeistReportSummary: Encodable {
    let completedSteps: Int
    let failedIndex: Int?
    let totalTimingMs: Int
    let expectations: PublicHeistExpectations?

    init(summary: HeistReportSummary) {
        self.completedSteps = summary.completedStepCount
        self.failedIndex = summary.failedIndex
        self.totalTimingMs = summary.totalTimingMs
        self.expectations = summary.expectationsChecked > 0
            ? PublicHeistExpectations(checked: summary.expectationsChecked, met: summary.expectationsMet)
            : nil
    }
}

struct PublicHeistReportNode: Encodable {
    let path: String
    let kind: String
    let status: String
    let message: String?
    let durationMs: Int
    let action: PublicHeistReportAction?
    let expectation: PublicExpectationResult?
    let caseSelection: HeistCaseSelectionResult?
    let forEachResult: HeistForEachResult?
    let children: [PublicHeistReportNode]

    init(node: HeistReportNode) {
        self.path = node.path
        self.kind = node.kind.rawValue
        self.status = node.status.rawValue
        self.message = node.message
        self.durationMs = node.durationMs
        self.action = node.action.map(PublicHeistReportAction.init(action:))
        self.expectation = node.expectationProjection.map(PublicExpectationResult.init(projection:))
        self.caseSelection = node.caseSelection
        self.forEachResult = node.forEachResult
        self.children = node.children.map(PublicHeistReportNode.init(node:))
    }
}

struct PublicHeistReportAction: Encodable {
    let commandName: String
    let target: ElementTarget?
    let result: PublicActionResponse?

    init(action: HeistActionReportProjection) {
        self.commandName = action.commandName
        self.target = action.target
        self.result = action.finalActionProjection.map(PublicActionResponse.init(projection:))
    }
}

struct PublicHeistExpectations: Encodable {
    let checked: Int
    let met: Int
    let allMet: Bool

    init(projection: PublicHeistExpectationsProjection) {
        self.checked = projection.checked
        self.met = projection.met
        self.allMet = projection.allMet
    }

    init(checked: Int, met: Int) {
        self.checked = checked
        self.met = met
        self.allMet = checked == met
    }
}
