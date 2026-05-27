import Foundation

import AccessibilitySnapshotModel
import TheScore

struct PublicActionResponse: FencePublicJSONResponse {
    let status: PublicStatus
    let method: String
    let message: String?
    let value: String?
    let rotor: PublicRotorResult?
    let animating: Bool?
    let delta: PublicDelta?
    let screenName: String?
    let screenId: String?
    let explore: PublicExploreResult?
    let errorClass: String?
    let errorCode: String?
    let phase: String?
    let retryable: Bool?
    let hint: String?
    let expectation: PublicExpectationResult?

    init(result: ActionResult, expectation: ExpectationResult?) {
        if let expectation, !expectation.met {
            self.status = PublicStatus(value: "expectation_failed")
        } else {
            self.status = result.success ? .ok : .error
        }
        self.method = result.method.rawValue
        self.message = result.message
        if case .value(let value) = result.payload {
            self.value = value
        } else {
            self.value = nil
        }
        if case .rotor(let rotor) = result.payload {
            self.rotor = PublicRotorResult(result: rotor)
        } else {
            self.rotor = nil
        }
        self.animating = result.animating == true ? true : nil
        self.delta = result.accessibilityDelta.map(PublicDelta.init)
        self.screenName = result.screenName
        self.screenId = result.screenId
        if case .explore(let explore) = result.payload {
            self.explore = PublicExploreResult(result: explore)
        } else {
            self.explore = nil
        }
        if result.success {
            self.errorClass = nil
            self.errorCode = nil
            self.phase = nil
            self.retryable = nil
            self.hint = nil
        } else {
            self.errorClass = (result.errorKind ?? .actionFailed).rawValue
            let details = FenceResponse.actionFailureDetails(result)
            self.errorCode = details?.errorCode
            self.phase = details?.phase.rawValue
            self.retryable = details?.retryable
            self.hint = details?.hint
        }
        self.expectation = expectation.map { PublicExpectationResult(result: $0) }
    }
}

struct PublicRotorResult: Encodable {
    let name: String
    let direction: String
    let foundElement: PublicElement?
    let textRange: PublicRotorTextRange?

    init(result: RotorResult) {
        self.name = result.rotor
        self.direction = result.direction.rawValue
        self.foundElement = result.foundElement.map { PublicElement(element: $0, detail: .summary) }
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

struct PublicExploreResult: Encodable {
    let elementCount: Int
    let scrollCount: Int
    let containersExplored: Int
    let explorationTime: String

    init(result: ExploreResult) {
        self.elementCount = result.elements.count
        self.scrollCount = result.scrollCount
        self.containersExplored = result.containersExplored
        self.explorationTime = String(format: "%.2f", result.explorationTime)
    }
}

struct PublicExpectationResult: Encodable {
    let met: Bool
    let actual: String?
    let expected: ActionExpectation?

    init(result: ExpectationResult) {
        self.met = result.met
        self.actual = result.actual
        self.expected = result.expectation
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
        self.kind = delta.kindRawValue
        self.elementCount = delta.elementCount
        self.captureEdge = delta.captureEdge
        self.transient = delta.transient.isEmpty ? nil : delta.transient.map { PublicElement(element: $0, detail: .summary) }
        switch delta {
        case .noChange:
            self.edits = nil
            self.newInterface = nil
        case .elementsChanged(let payload):
            let edits = PublicElementEdits(edits: payload.edits)
            self.edits = edits.isEmpty ? nil : edits
            self.newInterface = nil
        case .screenChanged(let payload):
            self.edits = nil
            self.newInterface = PublicInterface(interface: payload.newInterface, detail: .summary)
        }
    }
}

struct PublicElementEdits: Encodable {
    let added: [PublicElement]?
    let removed: [String]?
    let updated: [PublicElementUpdate]?
    let treeInserted: [PublicTreeInsertion]?
    let treeRemoved: [TreeRemoval]?
    let treeMoved: [TreeMove]?

    var isEmpty: Bool {
        added == nil && removed == nil && updated == nil && treeInserted == nil && treeRemoved == nil && treeMoved == nil
    }

    init(edits: ElementEdits) {
        self.added = edits.added.isEmpty ? nil : edits.added.map { PublicElement(element: $0, detail: .summary) }
        self.removed = edits.removed.isEmpty ? nil : edits.removed
        let filteredUpdates = edits.updated.compactMap { PublicElementUpdate(update: $0) }
        self.updated = filteredUpdates.isEmpty ? nil : filteredUpdates
        self.treeInserted = edits.treeInserted.isEmpty ? nil : edits.treeInserted.map { PublicTreeInsertion(insertion: $0) }
        self.treeRemoved = edits.treeRemoved.isEmpty ? nil : edits.treeRemoved
        self.treeMoved = edits.treeMoved.isEmpty ? nil : edits.treeMoved
    }
}

struct PublicElementUpdate: Encodable {
    let heistId: String
    let changes: [PropertyChange]

    init?(update: ElementUpdate) {
        let meaningfulChanges = update.changes.filter { !$0.property.isGeometry }
        guard !meaningfulChanges.isEmpty else { return nil }
        self.heistId = update.heistId
        self.changes = meaningfulChanges
    }
}

struct PublicTreeInsertion: Encodable {
    let location: TreeLocation
    let node: PublicTreeNode

    init(insertion: TreeInsertion) {
        self.location = insertion.location
        self.node = PublicTreeNode.node(
            from: insertion.node,
            path: .root,
            detail: .summary,
            counter: nil,
            elementAnnotations: insertion.annotations.elementByPath,
            containerAnnotations: insertion.annotations.containerByPath
        )
    }
}

struct PublicBatchResponse: FencePublicJSONResponse {
    let status: PublicStatus
    let results: [PublicResponseModel]
    let completedSteps: Int
    let totalTimingMs: Int
    let failedIndex: Int?
    let expectations: PublicBatchExpectations?
    let stepSummaries: [PublicBatchStepSummary]?
    let netDelta: PublicDelta?

    init(outcomes: [BatchStepOutcome], totalTimingMs: Int, accessibilityTrace: AccessibilityTrace?) {
        let failedIndex = outcomes.stoppedFailedIndex
        self.status = PublicStatus(value: failedIndex == nil ? "ok" : "partial")
        self.results = outcomes.compactMap(\.response).map(PublicResponseModel.init)
        self.completedSteps = outcomes.completedStepCount
        self.totalTimingMs = totalTimingMs
        self.failedIndex = failedIndex
        let checked = outcomes.expectationsChecked
        self.expectations = checked > 0
            ? PublicBatchExpectations(checked: checked, met: outcomes.expectationsMet)
            : nil
        let summaries = outcomes.stepSummaries.enumerated().map { index, summary in
            PublicBatchStepSummary(index: index, summary: summary)
        }
        self.stepSummaries = summaries.isEmpty ? nil : summaries
        self.netDelta = accessibilityTrace?.meaningfulEndpointDeltaProjection.map(PublicDelta.init)
    }
}

struct PublicBatchExpectations: Encodable {
    let checked: Int
    let met: Int
    let allMet: Bool

    init(checked: Int, met: Int) {
        self.checked = checked
        self.met = met
        self.allMet = checked == met
    }
}

struct PublicBatchStepSummary: Encodable {
    let index: Int
    let command: String
    let deltaKind: String?
    let screenName: String?
    let screenId: String?
    let expectationMet: Bool?
    let elementCount: Int?
    let error: String?
    let errorCode: String?
    let phase: String?
    let nextCommand: String?

    init(index: Int, summary: BatchStepSummary) {
        self.index = index
        self.command = summary.command
        self.deltaKind = summary.deltaKind
        self.screenName = summary.screenName
        self.screenId = summary.screenId
        self.expectationMet = summary.expectationMet
        self.elementCount = summary.elementCount
        self.error = summary.error
        self.errorCode = summary.errorCode
        self.phase = summary.phase
        self.nextCommand = summary.nextCommand
    }
}
