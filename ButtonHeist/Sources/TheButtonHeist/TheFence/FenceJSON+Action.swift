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
        let surfacedExpectation = result.success ? expectation : nil
        let expectationHint = surfacedExpectation.flatMap {
            FenceResponse.expectationFailureHint($0, command: command, result: result)
        }
        self.init(
            method: command.rawValue,
            result: result,
            expectation: expectation,
            expectationHint: expectationHint
        )
    }

    init(
        method: String,
        result: ActionResult,
        expectation: ExpectationResult?,
        expectationHint: String? = nil
    ) {
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
        self.expectation = surfacedExpectation.map {
            PublicExpectationResult(result: $0, hint: expectationHint)
        }
        self.activationTrace = result.activationTrace
        self.timing = result.timing
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
    let hint: String?

    init(result: ExpectationResult, hint: String? = nil) {
        self.met = result.met
        self.actual = result.actual
        self.expected = result.predicate
        self.hint = hint
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
    let executedTopLevelStepCount: Int
    let executedNodeCount: Int
    let outputReceiptNodeCount: Int
    let durationMs: Int
    let abortedAtPath: String?
    let expectations: PublicHeistExpectations?
    let netDelta: PublicDelta?

    init(result: HeistExecutionResult, netDelta: AccessibilityTrace.Delta?) {
        self.status = PublicStatus(result.abortedAtPath == nil ? .ok : .partial)
        self.report = PublicHeistReport(result: result)
        self.executedTopLevelStepCount = result.executedTopLevelStepCount
        self.executedNodeCount = result.executedNodeCount
        self.outputReceiptNodeCount = result.outputReceiptNodes.count
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
    let executedTopLevelStepCount: Int
    let executedNodeCount: Int
    let outputReceiptNodeCount: Int
    let abortedAtPath: String?
    let durationMs: Int
    let expectations: PublicHeistExpectations?

    init(result: HeistExecutionResult) {
        self.executedTopLevelStepCount = result.executedTopLevelStepCount
        self.executedNodeCount = result.executedNodeCount
        self.outputReceiptNodeCount = result.outputReceiptNodes.count
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
    let evidence: PublicHeistReportEvidence?
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
        self.evidence = PublicHeistReportEvidence(step: step)
        self.failure = step.failure
        self.abortedAtChildPath = step.abortedAtChildPath
        self.action = PublicHeistReportAction(step: step)
        self.expectation = step.reportExpectation.map {
            PublicExpectationResult(result: $0)
        }
        self.children = step.children.map(PublicHeistReportNode.init(step:))
    }
}

struct PublicHeistReportAction: Encodable {
    let commandName: String
    let target: ElementTarget?
    let result: PublicHeistReportActionResult?

    init?(step: HeistExecutionStepResult) {
        guard step.kind == .action, let commandName = step.reportCommandName else { return nil }
        self.commandName = commandName
        self.target = step.reportTarget
        self.result = step.reportActionResult.map {
            PublicHeistReportActionResult(method: commandName, result: $0)
        }
    }
}

struct PublicHeistReportEvidence: Encodable {
    let action: PublicHeistActionEvidence?
    let wait: PublicHeistWaitEvidence?
    let caseSelection: PublicHeistCaseSelectionEvidence?
    let forEachString: PublicHeistForEachStringEvidence?
    let forEachElement: PublicHeistForEachElementEvidence?
    let invocation: PublicHeistInvocationEvidence?
    let warning: PublicHeistWarningEvidence?

    init?(
        step: HeistExecutionStepResult
    ) {
        guard let evidence = step.evidence else { return nil }
        switch evidence {
        case .action(let evidence):
            self.init(action: PublicHeistActionEvidence(evidence: evidence))
        case .wait(let evidence):
            self.init(wait: PublicHeistWaitEvidence(evidence: evidence))
        case .caseSelection(let evidence):
            self.init(caseSelection: PublicHeistCaseSelectionEvidence(evidence: evidence))
        case .forEachString(let evidence):
            self.init(forEachString: PublicHeistForEachStringEvidence(evidence: evidence))
        case .forEachElement(let evidence):
            self.init(forEachElement: PublicHeistForEachElementEvidence(evidence: evidence))
        case .invocation(let evidence):
            self.init(invocation: PublicHeistInvocationEvidence(evidence: evidence))
        case .warning(let warning):
            self.init(warning: PublicHeistWarningEvidence(warning: warning))
        }
    }

    private init(
        action: PublicHeistActionEvidence? = nil,
        wait: PublicHeistWaitEvidence? = nil,
        caseSelection: PublicHeistCaseSelectionEvidence? = nil,
        forEachString: PublicHeistForEachStringEvidence? = nil,
        forEachElement: PublicHeistForEachElementEvidence? = nil,
        invocation: PublicHeistInvocationEvidence? = nil,
        warning: PublicHeistWarningEvidence? = nil
    ) {
        self.action = action
        self.wait = wait
        self.caseSelection = caseSelection
        self.forEachString = forEachString
        self.forEachElement = forEachElement
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
        let commandName = evidence.command?.wireType.rawValue
        self.commandName = commandName
        self.target = evidence.command?.reportTarget
        self.result = evidence.actionResult.map {
            PublicHeistReportActionResult(method: commandName ?? $0.method.rawValue, result: $0)
        }
        self.expectationResult = evidence.expectationActionResult.map {
            PublicHeistReportActionResult(method: $0.method.rawValue, result: $0)
        }
        self.expectation = evidence.expectation.map {
            PublicExpectationResult(result: $0)
        }
    }
}

struct PublicHeistWaitEvidence: Encodable {
    let result: PublicHeistReportActionResult
    let expectation: PublicExpectationResult
    let baselineSummary: String?
    let finalSummary: String?

    init(evidence: HeistWaitEvidence) {
        self.result = PublicHeistReportActionResult(method: evidence.actionResult.method.rawValue, result: evidence.actionResult)
        self.expectation = PublicExpectationResult(result: evidence.expectation)
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
    let cases: [PublicHeistCaseMatchResult]?
    let omittedCaseCount: Int?

    init(evidence: HeistCaseSelectionEvidence) {
        let selection = evidence.selection
        self.outcome = selection.outcome
        self.elapsedMs = selection.elapsedMs
        self.timeout = selection.timeout
        self.lastObservedSummary = selection.lastObservedSummary
        self.caseCount = selection.cases.count
        let visibleCases = Array(selection.cases.prefix(PublicHeistProjectionLimits.caseResults))
        self.cases = visibleCases.isEmpty ? nil : visibleCases.map(PublicHeistCaseMatchResult.init(match:))
        self.omittedCaseCount = Self.omittedCount(
            total: selection.cases.count,
            visible: visibleCases.count
        )
    }

    private static func omittedCount(total: Int, visible: Int) -> Int? {
        let omitted = total - visible
        return omitted > 0 ? omitted : nil
    }
}

struct PublicHeistCaseMatchResult: Encodable {
    let predicate: AccessibilityPredicate
    let met: Bool
    let actual: String?

    init(match: HeistCaseMatchResult) {
        self.predicate = match.predicate
        self.met = match.result.met
        self.actual = match.result.actual
    }
}

struct PublicHeistForEachStringEvidence: Encodable {
    let parameter: String
    let count: Int
    let iterationCount: Int
    let iterationOrdinal: Int?
    let value: String?
    let failureReason: String?

    init(evidence: HeistForEachStringEvidence) {
        self.parameter = evidence.parameter
        self.count = evidence.count
        self.iterationCount = evidence.iterationCount
        self.iterationOrdinal = evidence.iterationOrdinal
        self.value = evidence.value
        self.failureReason = evidence.failureReason
    }
}

struct PublicHeistForEachElementEvidence: Encodable {
    let parameter: String
    let matching: ElementPredicate
    let limit: Int
    let matchedCount: Int
    let iterationCount: Int
    let iterationOrdinal: Int?
    let targetOrdinal: Int?
    let targetSummary: String?
    let failureReason: String?

    init(evidence: HeistForEachElementEvidence) {
        self.parameter = evidence.parameter
        self.matching = evidence.matching
        self.limit = evidence.limit
        self.matchedCount = evidence.matchedCount
        self.iterationCount = evidence.iterationCount
        self.iterationOrdinal = evidence.iterationOrdinal
        self.targetOrdinal = evidence.targetOrdinal
        self.targetSummary = evidence.targetSummary
        self.failureReason = evidence.failureReason
    }
}

struct PublicHeistInvocationEvidence: Encodable {
    let capability: String?
    let name: String?
    let argument: String?
    let childFailedPath: String?

    init(evidence: HeistInvocationEvidence) {
        self.capability = evidence.invocation?.capabilityName
        self.name = evidence.name
        self.argument = evidence.argument
        self.childFailedPath = evidence.childFailedPath
    }
}

struct PublicHeistWarningEvidence: Encodable {
    let path: String
    let message: String

    init(warning: HeistExecutionWarning) {
        self.path = warning.path
        self.message = warning.message
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
        self.status = PublicStatus(result.publicStatus(expectation: nil))
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
        self.delta = result.accessibilityTrace?.endpointDelta.map(PublicHeistDelta.init(delta:))
        self.screenName = result.accessibilityTrace?.endpointScreenName
        self.screenId = result.accessibilityTrace?.endpointScreenId
        self.errorClass = result.publicErrorClass
        let details = result.publicFailureDetails
        self.errorCode = details?.errorCode
        self.phase = details?.phase.rawValue
        self.retryable = details?.retryable
        self.hint = details?.hint
        self.activationTrace = result.activationTrace
        self.timing = result.timing
        let omissions = PublicHeistActionResultOmissions(result: result)
        self.omitted = omissions.isEmpty ? nil : omissions
    }
}

struct PublicHeistActionResultOmissions: Encodable {
    let accessibilityTrace: PublicProjectionOmission?
    let subjectEvidence: PublicProjectionOmission?

    var isEmpty: Bool {
        accessibilityTrace == nil && subjectEvidence == nil
    }

    init(result: ActionResult) {
        self.accessibilityTrace = result.accessibilityTrace.map {
            PublicProjectionOmission(
                reason: "raw accessibility trace omitted from public heist report",
                projectedAs: "delta",
                omittedCount: $0.captures.count
            )
        }
        self.subjectEvidence = result.subjectEvidence.map { _ in
            PublicProjectionOmission(
                reason: "raw subject evidence omitted from public heist report",
                projectedAs: nil,
                omittedCount: nil
            )
        }
    }
}

struct PublicProjectionOmission: Encodable {
    let reason: String
    let projectedAs: String?
    let omittedCount: Int?
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
        switch delta {
        case .noChange(let payload):
            let transient = Self.elements(payload.transient)
            let omittedTransientCount = Self.omittedCount(
                total: payload.transient.count,
                visible: transient.count
            )
            self.kind = AccessibilityTrace.DeltaKind.noChange.rawValue
            self.elementCount = payload.elementCount
            self.captureEdge = payload.captureEdge
            self.transient = transient.isEmpty ? nil : transient
            self.edits = nil
            self.screen = nil
            let omitted = PublicHeistDeltaOmissions(transient: omittedTransientCount)
            self.omitted = omitted.isEmpty ? nil : omitted

        case .elementsChanged(let payload):
            let transient = Self.elements(payload.transient)
            let omittedTransientCount = Self.omittedCount(
                total: payload.transient.count,
                visible: transient.count
            )
            let edits = PublicHeistElementEdits(edits: payload.edits)
            self.kind = AccessibilityTrace.DeltaKind.elementsChanged.rawValue
            self.elementCount = payload.elementCount
            self.captureEdge = payload.captureEdge
            self.transient = transient.isEmpty ? nil : transient
            self.edits = edits.isEmpty ? nil : edits
            self.screen = nil
            let omitted = PublicHeistDeltaOmissions(transient: omittedTransientCount)
            self.omitted = omitted.isEmpty ? nil : omitted

        case .screenChanged(let payload):
            let transient = Self.elements(payload.transient)
            let omittedTransientCount = Self.omittedCount(
                total: payload.transient.count,
                visible: transient.count
            )
            self.kind = AccessibilityTrace.DeltaKind.screenChanged.rawValue
            self.elementCount = payload.elementCount
            self.captureEdge = payload.captureEdge
            self.transient = transient.isEmpty ? nil : transient
            self.edits = nil
            self.screen = PublicHeistScreenProjection(interface: payload.newInterface)
            let omitted = PublicHeistDeltaOmissions(transient: omittedTransientCount)
            self.omitted = omitted.isEmpty ? nil : omitted
        }
    }

    private static func elements(_ elements: [HeistElement]) -> [PublicElement] {
        elements.prefix(PublicHeistProjectionLimits.deltaElementsPerBucket).map {
            PublicElement(element: $0, detail: .summary)
        }
    }

    private static func omittedCount(total: Int, visible: Int) -> Int? {
        let omitted = total - visible
        return omitted > 0 ? omitted : nil
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
        let added = Self.elements(edits.added)
        let removed = Self.elements(edits.removed)
        let meaningfulUpdates = edits.updated.compactMap { PublicElementUpdate(update: $0) }
        let updated = Array(meaningfulUpdates.prefix(PublicHeistProjectionLimits.deltaElementsPerBucket))
        self.added = added.isEmpty ? nil : added
        self.removed = removed.isEmpty ? nil : removed
        self.updated = updated.isEmpty ? nil : updated
        let omitted = PublicHeistElementEditOmissions(
            added: Self.omittedCount(total: edits.added.count, visible: added.count),
            removed: Self.omittedCount(total: edits.removed.count, visible: removed.count),
            updated: Self.omittedCount(total: meaningfulUpdates.count, visible: updated.count)
        )
        self.omitted = omitted.isEmpty ? nil : omitted
    }

    private static func elements(_ elements: [HeistElement]) -> [PublicElement] {
        elements.prefix(PublicHeistProjectionLimits.deltaElementsPerBucket).map {
            PublicElement(element: $0, detail: .summary)
        }
    }

    private static func omittedCount(total: Int, visible: Int) -> Int? {
        let omitted = total - visible
        return omitted > 0 ? omitted : nil
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
        let elements = interface.projectedElements
        let visible = Array(elements.prefix(PublicHeistProjectionLimits.screenPreviewElements))
        self.screenDescription = InterfaceSummary.screenDescription(for: interface)
        self.screenId = InterfaceSummary.screenId(for: interface)
        self.elementCount = elements.count
        self.elements = visible.isEmpty
            ? nil
            : visible.map { PublicElement(element: $0, detail: .summary) }
        let omitted = elements.count - visible.count
        self.omittedElementCount = omitted > 0 ? omitted : nil
    }
}

private enum PublicHeistProjectionLimits {
    static let deltaElementsPerBucket = 5
    static let screenPreviewElements = 5
    static let caseResults = 10
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
