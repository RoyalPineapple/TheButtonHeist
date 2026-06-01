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
        self.delta = result.accessibilityTrace?.endpointDeltaProjection.map(PublicDelta.init)
        self.screenName = result.accessibilityTrace?.endpointScreenNameProjection
        self.screenId = result.accessibilityTrace?.endpointScreenIdProjection
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

    init(result: ExpectationResult) {
        self.met = result.met
        self.actual = result.actual
        self.expected = result.predicate
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
    let results: [PublicResponseModel]
    let completedSteps: Int
    let totalTimingMs: Int
    let failedIndex: Int?
    let expectations: PublicHeistExpectations?
    let netDelta: PublicDelta?

    init(
        plan: HeistPlan,
        result: HeistExecutionResult,
        accessibilityTrace: AccessibilityTrace?
    ) {
        let failedIndex = result.stoppedFailedIndex
        self.status = PublicStatus(value: failedIndex == nil ? "ok" : "partial")
        self.results = result.projectedOutcomes(for: plan).compactMap { projection in
            guard let response = projection.outcome.actionResponse(
                command: projection.step.fenceCommand ?? .runHeist,
                step: projection.step
            )
            else { return nil }
            return PublicResponseModel(response: response)
        }
        self.completedSteps = result.completedStepCount
        self.totalTimingMs = result.totalTimingMs
        self.failedIndex = failedIndex
        let checked = result.projectedExpectationsChecked(for: plan)
        self.expectations = checked > 0
            ? PublicHeistExpectations(checked: checked, met: result.projectedExpectationsMet(for: plan))
            : nil
        self.netDelta = accessibilityTrace?.meaningfulEndpointDeltaProjection.map(PublicDelta.init)
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
}

private extension HeistStep {
    var fenceCommand: TheFence.Command? {
        guard case .action(let action) = self else { return nil }
        return TheFence.Command(clientWireType: action.command.wireType)
    }
}

private extension TheFence.Command {
    init?(clientWireType: ClientWireMessageType) {
        self.init(rawValue: clientWireType.commandName)
    }
}

private extension ClientWireMessageType {
    var commandName: String {
        switch self {
        case .performCustomAction: return TheFence.Command.activate.rawValue
        case .oneFingerTap: return TheFence.Command.oneFingerTap.rawValue
        case .longPress: return TheFence.Command.longPress.rawValue
        case .typeText: return TheFence.Command.typeText.rawValue
        case .setPasteboard: return TheFence.Command.setPasteboard.rawValue
        case .scrollToVisible: return TheFence.Command.scrollToVisible.rawValue
        case .elementSearch: return TheFence.Command.elementSearch.rawValue
        case .scrollToEdge: return TheFence.Command.scrollToEdge.rawValue
        case .resignFirstResponder: return TheFence.Command.dismissKeyboard.rawValue
        default: return rawValue
        }
    }
}
