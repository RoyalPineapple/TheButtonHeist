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

    init(commandName: String, result: ActionResult, expectation: ExpectationResult?) {
        if let expectation, !expectation.met {
            self.status = PublicStatus(value: "expectation_failed")
        } else {
            self.status = result.success ? .ok : .error
        }
        self.method = commandName
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

    init(
        commands: [TheFence.Command],
        steps: [TheScore.BatchStep],
        result: BatchExecutionResult,
        accessibilityTrace: AccessibilityTrace?
    ) {
        let failedIndex = result.stoppedFailedIndex
        self.status = PublicStatus(value: failedIndex == nil ? "ok" : "partial")
        self.results = result.steps.compactMap { step in
            guard commands.indices.contains(step.index),
                  steps.indices.contains(step.index),
                  let response = step.actionResponse(
                    command: commands[step.index],
                    step: steps[step.index]
                  )
            else { return nil }
            return PublicResponseModel(response: response)
        }
        self.completedSteps = result.completedStepCount
        self.totalTimingMs = result.totalTimingMs
        self.failedIndex = failedIndex
        let checked = result.expectationsChecked(steps: steps)
        self.expectations = checked > 0
            ? PublicBatchExpectations(checked: checked, met: result.expectationsMet(steps: steps))
            : nil
        let summaries = result.steps.map { step in
            PublicBatchStepSummary(
                step: step,
                command: commands.indices.contains(step.index) ? commands[step.index] : nil,
                typedStep: steps.indices.contains(step.index) ? steps[step.index] : nil
            )
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

    init(
        step: BatchExecutionStepResult,
        command: TheFence.Command?,
        typedStep: TheScore.BatchStep?
    ) {
        self.index = step.index
        self.command = command?.rawValue ?? "step \(step.index)"
        let actionResult = step.finalActionResult()
        self.deltaKind = actionResult?.accessibilityDelta?.kindRawValue
        self.screenName = actionResult?.screenName
        self.screenId = actionResult?.screenId
        self.expectationMet = typedStep.flatMap { step.expectationMet(for: $0) }
        self.elementCount = nil
        if let skipped = step.skipped {
            self.error = skipped.reason
            self.errorCode = nil
            self.phase = nil
            self.nextCommand = nil
        } else if actionResult?.success == false {
            self.error = actionResult?.message
            self.errorCode = nil
            self.phase = nil
            self.nextCommand = nil
        } else if let typedStep,
                  let command,
                  case .error(let message, let details) = step.actionResponse(command: command, step: typedStep) {
            self.error = message
            self.errorCode = details?.errorCode
            self.phase = details?.phase.rawValue
            self.nextCommand = Self.batchNextCommand(from: details)
        } else {
            self.error = nil
            self.errorCode = nil
            self.phase = nil
            self.nextCommand = nil
        }
    }

    private static func batchNextCommand(from details: FailureDetails?) -> String? {
        guard details?.errorCode == FenceRequestErrorCode.missingTarget else { return nil }
        return details?.hint
    }
}
