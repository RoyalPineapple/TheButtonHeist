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

    init(method: String, result: ActionResult, expectation: ExpectationResult?) {
        let surfacedExpectation = result.success ? expectation : nil
        self.status = PublicStatus(result.publicStatus(expectation: surfacedExpectation))
        self.method = method
        self.message = result.message
        switch result.payload {
        case .value(let value):
            self.value = value
            self.rotor = nil
        case .rotor(let rotor):
            self.value = nil
            self.rotor = PublicRotorResult(result: rotor)
        case .heistExecution, .none:
            self.value = nil
            self.rotor = nil
        }
        self.delta = result.accessibilityTrace?.endpointDelta.map(PublicDelta.init)
        self.screenName = result.accessibilityTrace?.endpointScreenName
        self.screenId = result.accessibilityTrace?.endpointScreenId
        self.errorClass = result.publicErrorClass
        let details = result.publicFailureDetails
        self.errorCode = details?.errorCode
        self.phase = details?.phase.rawValue
        self.retryable = details?.retryable
        self.hint = details?.hint
        self.expectation = surfacedExpectation.map(PublicExpectationResult.init(result:))
    }

}

/// Status vocabulary for public command responses.
enum PublicResponseStatus: String {
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
    let report: PublicHeistReport
    let completedSteps: Int
    let durationMs: Int
    let abortedAtPath: String?
    let expectations: PublicHeistExpectations?
    let netDelta: PublicDelta?

    init(result: HeistExecutionResult, netDelta: AccessibilityTrace.Delta?) {
        self.status = PublicStatus(result.abortedAtPath == nil ? .ok : .partial)
        self.report = PublicHeistReport(result: result)
        self.completedSteps = result.completedStepCount
        self.durationMs = result.durationMs
        self.abortedAtPath = result.abortedAtPath
        let checked = result.expectationsChecked
        self.expectations = checked > 0
            ? PublicHeistExpectations(checked: checked, met: result.expectationsMet)
            : nil
        self.netDelta = netDelta.map(PublicDelta.init)
    }
}

struct PublicHeistReport: Encodable {
    let summary: PublicHeistReportSummary
    let nodes: [PublicHeistReportNode]

    init(result: HeistExecutionResult) {
        self.summary = PublicHeistReportSummary(result: result)
        self.nodes = result.steps.map(PublicHeistReportNode.init(step:))
    }
}

struct PublicHeistReportSummary: Encodable {
    let completedSteps: Int
    let abortedAtPath: String?
    let durationMs: Int
    let expectations: PublicHeistExpectations?

    init(result: HeistExecutionResult) {
        self.completedSteps = result.completedStepCount
        self.abortedAtPath = result.abortedAtPath
        self.durationMs = result.durationMs
        let checked = result.expectationsChecked
        self.expectations = checked > 0
            ? PublicHeistExpectations(checked: checked, met: result.expectationsMet)
            : nil
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
    let evidence: HeistStepEvidence?
    let failure: HeistFailureDetail?
    let abortedAtChildPath: String?
    let action: PublicHeistReportAction?
    let expectation: PublicExpectationResult?
    let children: [PublicHeistReportNode]

    init(step: HeistExecutionStepResult) {
        self.path = step.path
        self.kind = step.reportStepName
        self.capability = step.invocationEvidence?.invocation?.capabilityName
        self.status = step.status.rawValue
        self.message = step.reportMessage
        self.durationMs = step.durationMs
        self.intent = step.intent
        self.evidence = step.evidence
        self.failure = step.failure
        self.abortedAtChildPath = step.abortedAtChildPath
        self.action = PublicHeistReportAction(step: step)
        self.expectation = step.reportExpectation.map(PublicExpectationResult.init(result:))
        self.children = step.children.map(PublicHeistReportNode.init(step:))
    }
}

struct PublicHeistReportAction: Encodable {
    let commandName: String
    let target: ElementTarget?
    let result: PublicActionResponse?

    init?(step: HeistExecutionStepResult) {
        guard step.kind == .action, let commandName = step.reportCommandName else { return nil }
        self.commandName = commandName
        self.target = step.reportTarget
        self.result = step.reportActionResult.map {
            PublicActionResponse(method: commandName, result: $0, expectation: nil)
        }
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
