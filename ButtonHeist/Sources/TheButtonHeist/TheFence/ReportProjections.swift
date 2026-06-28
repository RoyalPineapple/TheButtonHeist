import Foundation

import AccessibilitySnapshotModel
import ThePlans
import TheScore

@_spi(ButtonHeistInternals) public struct ProjectionLimits: Sendable, Equatable {
    public let visibleElementBudget: Int
    public let totalNodeBudget: Int
    public let deltaElementsPerBucket: Int
    public let screenPreviewElements: Int
    public let caseResults: Int
    public let failureInterfaceElements: Int

    public init(
        visibleElementBudget: Int,
        totalNodeBudget: Int,
        deltaElementsPerBucket: Int,
        screenPreviewElements: Int,
        caseResults: Int,
        failureInterfaceElements: Int
    ) {
        self.visibleElementBudget = max(0, visibleElementBudget)
        self.totalNodeBudget = max(0, totalNodeBudget)
        self.deltaElementsPerBucket = max(0, deltaElementsPerBucket)
        self.screenPreviewElements = max(0, screenPreviewElements)
        self.caseResults = max(0, caseResults)
        self.failureInterfaceElements = max(0, failureInterfaceElements)
    }

    public static func current(
        deltaElementsPerBucket: Int = Int.max,
        screenPreviewElements: Int = Int.max,
        caseResults: Int = Int.max,
        failureInterfaceElements: Int = HeistFailureDiagnostics.defaultElementLimit
    ) -> ProjectionLimits {
        ProjectionLimits(
            visibleElementBudget: ButtonHeistRuntimeKnobs.current.visibleElementBudget,
            totalNodeBudget: ButtonHeistRuntimeKnobs.current.totalNodeBudget,
            deltaElementsPerBucket: deltaElementsPerBucket,
            screenPreviewElements: screenPreviewElements,
            caseResults: caseResults,
            failureInterfaceElements: failureInterfaceElements
        )
    }

    public static func current(
        visibleElementBudget: Int,
        totalNodeBudget: Int,
        deltaElementsPerBucket: Int = Int.max,
        screenPreviewElements: Int = Int.max,
        caseResults: Int = Int.max,
        failureInterfaceElements: Int = HeistFailureDiagnostics.defaultElementLimit
    ) -> ProjectionLimits {
        ProjectionLimits(
            visibleElementBudget: visibleElementBudget,
            totalNodeBudget: totalNodeBudget,
            deltaElementsPerBucket: deltaElementsPerBucket,
            screenPreviewElements: screenPreviewElements,
            caseResults: caseResults,
            failureInterfaceElements: failureInterfaceElements
        )
    }
}

@_spi(ButtonHeistInternals) public struct ProjectionProfile: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case summary
        case full
        case mcp
        case junit
    }

    public let kind: Kind
    public let limits: ProjectionLimits

    public init(kind: Kind, limits: ProjectionLimits) {
        self.kind = kind
        self.limits = limits
    }

    public static var summary: ProjectionProfile {
        ProjectionProfile(kind: .summary, limits: .current())
    }

    public static var full: ProjectionProfile {
        ProjectionProfile(kind: .full, limits: .current())
    }

    public static var mcp: ProjectionProfile {
        ProjectionProfile(
            kind: .mcp,
            limits: .current(deltaElementsPerBucket: 5, screenPreviewElements: 5, caseResults: 10)
        )
    }

    public static var junit: ProjectionProfile {
        ProjectionProfile(kind: .junit, limits: .current())
    }

    var interfaceDetail: InterfaceDetail {
        kind == .full ? .full : .summary
    }
}

// MARK: - Interface Projection

enum ProjectionRenderingState: String, Sendable {
    case full
    case truncated
}

enum ProjectionOmissionReason: String, Sendable {
    case rawAccessibilityTrace = "raw accessibility trace omitted from public heist report"
    case rawSubjectEvidence = "raw subject evidence omitted from public heist report"
    case scrollSubtreeElementBudget = "scroll-subtree-element-budget"
    case totalNodeBudget = "total-node-budget"
}

struct InterfaceRenderingProjection: Sendable {
    let state: ProjectionRenderingState
    let reason: ProjectionOmissionReason?
    let observedElementCount: Int
    let renderedElementCount: Int
    let omittedElementCount: Int
    let visibleElementBudget: Int?
    let totalNodeBudget: Int?
}

struct InterfaceSubtreeTruncationProjection: Sendable {
    let reason: ProjectionOmissionReason
    let observedElementCount: Int
    let renderedElementCount: Int
    let omittedElementCount: Int
    let visibleElementBudget: Int
}

struct InterfaceNavigationProjection: Sendable {
    let screenTitle: String?
    let backButton: NavigationItemProjection?
    let tabBarItems: [TabBarItemProjection]

    init(interface: Interface) {
        let elements = interface.projectedElements
        screenTitle = InterfaceSummary.screenTitle(for: interface)
        backButton = elements
            .first(where: { $0.traits.contains(.backButton) })
            .map(NavigationItemProjection.init(element:))
        tabBarItems = elements
            .filter { $0.traits.contains(.tabBarItem) }
            .map(TabBarItemProjection.init(element:))
    }
}

struct NavigationItemProjection: Sendable {
    let label: String?
    let value: String?

    init(element: HeistElement) {
        label = element.label
        value = element.value
    }
}

struct TabBarItemProjection: Sendable {
    let label: String?
    let value: String?
    let selected: Bool

    init(element: HeistElement) {
        label = element.label
        value = element.value
        selected = element.traits.contains(.selected)
    }
}

struct InterfaceElementProjection: Sendable {
    let element: HeistElement
    let order: Int?
}

struct InterfaceContainerProjection: Sendable {
    let container: AccessibilityContainer
    let containerName: String?
    let observedElementCount: Int
    let truncation: InterfaceSubtreeTruncationProjection?
    let children: [InterfaceNodeProjection]
}

indirect enum InterfaceNodeProjection: Sendable {
    case element(InterfaceElementProjection)
    case container(InterfaceContainerProjection)

    var elementCount: Int {
        switch self {
        case .element:
            return 1
        case .container(let container):
            return container.children.reduce(0) { $0 + $1.elementCount }
        }
    }
}

struct InterfaceProjection: Sendable {
    let timestamp: Date
    let detail: InterfaceDetail
    let screenDescription: String
    let screenId: String?
    let diagnostics: InterfaceDiagnostics?
    let navigation: InterfaceNavigationProjection
    let rendering: InterfaceRenderingProjection
    let tree: [InterfaceNodeProjection]
    let elementCount: Int

    init(interface: Interface, profile: ProjectionProfile) {
        timestamp = interface.timestamp
        detail = profile.interfaceDetail
        screenDescription = InterfaceSummary.screenDescription(for: interface)
        screenId = InterfaceSummary.screenId(for: interface)
        diagnostics = interface.diagnostics
        navigation = InterfaceNavigationProjection(interface: interface)
        elementCount = interface.projectedElements.count

        let stats = InterfaceProjectionStats(observedElementCount: elementCount)
        let totalNodeBudget = InterfaceNodeBudgetTracker(budget: profile.limits.totalNodeBudget)
        let context = InterfaceProjectionContext(
            detail: profile.interfaceDetail,
            visibleElementBudget: profile.limits.visibleElementBudget,
            totalNodeBudget: totalNodeBudget,
            stats: stats,
            elementAnnotations: interface.annotations.elementByPath,
            containerAnnotations: interface.annotations.containerByPath
        )
        var counter = 0
        var remainingElements: Int?
        tree = interface.tree.enumerated().compactMap { index, node in
            Self.project(
                node,
                path: TreePath([index]),
                context: context,
                counter: &counter,
                remainingElements: &remainingElements
            )
        }
        rendering = stats.rendering(
            visibleElementBudget: profile.limits.visibleElementBudget,
            totalNodeBudget: profile.limits.totalNodeBudget,
            totalNodeBudgetHit: totalNodeBudget.wasLimited
        )
    }

    private static func project(
        _ node: AccessibilityHierarchy,
        path: TreePath,
        context: InterfaceProjectionContext,
        counter: inout Int,
        remainingElements: inout Int?
    ) -> InterfaceNodeProjection? {
        switch node {
        case .element(let element, _):
            let order = counter
            counter += 1
            if let remaining = remainingElements {
                guard remaining > 0 else { return nil }
            }
            guard context.totalNodeBudget.consumeNode() else { return nil }
            if let remaining = remainingElements {
                remainingElements = remaining - 1
            }
            context.stats.recordRenderedElement()
            let projected = HeistElement(
                accessibilityElement: element,
                annotation: context.elementAnnotations[path]
            )
            return .element(InterfaceElementProjection(element: projected, order: order))

        case .container(let container, let children):
            let observedElementCount = children.reduce(0) { $0 + $1.pathIndexedElements().count }
            if let remaining = remainingElements, remaining <= 0 {
                counter += observedElementCount
                return nil
            }
            guard context.totalNodeBudget.consumeNode() else {
                counter += observedElementCount
                return nil
            }

            let budgetCap = max(0, context.visibleElementBudget)
            let isScrollable: Bool = {
                if case .scrollable = container.type { return true }
                return false
            }()
            let shouldTruncate = isScrollable && observedElementCount > budgetCap
            let parentRemainingBefore = remainingElements
            var scrollRemainingElements: Int?
            var projectedChildren: [InterfaceNodeProjection] = []

            if shouldTruncate {
                scrollRemainingElements = min(parentRemainingBefore ?? budgetCap, budgetCap)
                for (index, child) in children.enumerated() {
                    if let projectedChild = project(
                        child,
                        path: path.appending(index),
                        context: context,
                        counter: &counter,
                        remainingElements: &scrollRemainingElements
                    ) {
                        projectedChildren.append(projectedChild)
                    }
                }
            } else {
                for (index, child) in children.enumerated() {
                    if let projectedChild = project(
                        child,
                        path: path.appending(index),
                        context: context,
                        counter: &counter,
                        remainingElements: &remainingElements
                    ) {
                        projectedChildren.append(projectedChild)
                    }
                }
            }

            let truncation: InterfaceSubtreeTruncationProjection?
            if shouldTruncate {
                let effectiveBudget = min(parentRemainingBefore ?? budgetCap, budgetCap)
                let renderedElementCount = max(0, effectiveBudget - (scrollRemainingElements ?? 0))
                if let parentRemainingBefore {
                    remainingElements = max(0, parentRemainingBefore - renderedElementCount)
                }
                let omittedElementCount = max(0, observedElementCount - renderedElementCount)
                let scrollBudgetHit = (scrollRemainingElements ?? 0) <= 0
                if scrollBudgetHit, omittedElementCount > 0 {
                    context.stats.recordTruncatedScrollContainer()
                    truncation = InterfaceSubtreeTruncationProjection(
                        reason: .scrollSubtreeElementBudget,
                        observedElementCount: observedElementCount,
                        renderedElementCount: renderedElementCount,
                        omittedElementCount: omittedElementCount,
                        visibleElementBudget: budgetCap
                    )
                } else {
                    truncation = nil
                }
            } else {
                truncation = nil
            }

            return .container(InterfaceContainerProjection(
                container: container,
                containerName: context.containerAnnotations[path]?.containerName?.rawValue,
                observedElementCount: observedElementCount,
                truncation: truncation,
                children: projectedChildren
            ))
        }
    }
}

private struct InterfaceProjectionContext {
    let detail: InterfaceDetail
    let visibleElementBudget: Int
    let totalNodeBudget: InterfaceNodeBudgetTracker
    let stats: InterfaceProjectionStats
    let elementAnnotations: [TreePath: InterfaceElementAnnotation]
    let containerAnnotations: [TreePath: InterfaceContainerAnnotation]
}

private final class InterfaceProjectionStats {
    let observedElementCount: Int
    private(set) var renderedElementCount = 0
    private(set) var truncatedScrollContainerCount = 0

    init(observedElementCount: Int) {
        self.observedElementCount = observedElementCount
    }

    func recordRenderedElement() {
        renderedElementCount += 1
    }

    func recordTruncatedScrollContainer() {
        truncatedScrollContainerCount += 1
    }

    func rendering(
        visibleElementBudget: Int,
        totalNodeBudget: Int,
        totalNodeBudgetHit: Bool
    ) -> InterfaceRenderingProjection {
        let omittedElementCount = max(0, observedElementCount - renderedElementCount)
        guard truncatedScrollContainerCount > 0 || omittedElementCount > 0 || totalNodeBudgetHit else {
            return InterfaceRenderingProjection(
                state: .full,
                reason: nil,
                observedElementCount: observedElementCount,
                renderedElementCount: renderedElementCount,
                omittedElementCount: 0,
                visibleElementBudget: nil,
                totalNodeBudget: nil
            )
        }

        return InterfaceRenderingProjection(
            state: .truncated,
            reason: totalNodeBudgetHit ? .totalNodeBudget : .scrollSubtreeElementBudget,
            observedElementCount: observedElementCount,
            renderedElementCount: renderedElementCount,
            omittedElementCount: omittedElementCount,
            visibleElementBudget: truncatedScrollContainerCount > 0 ? max(0, visibleElementBudget) : nil,
            totalNodeBudget: totalNodeBudgetHit ? max(0, totalNodeBudget) : nil
        )
    }
}

private final class InterfaceNodeBudgetTracker {
    let budget: Int
    private(set) var remaining: Int
    private(set) var wasLimited = false

    init(budget: Int) {
        let boundedBudget = max(0, budget)
        self.budget = boundedBudget
        remaining = boundedBudget
    }

    func consumeNode() -> Bool {
        guard remaining > 0 else {
            wasLimited = true
            return false
        }
        remaining -= 1
        return true
    }
}

// MARK: - Delta Projection

struct ElementProjectionBucket: Sendable {
    let elements: [HeistElement]
    let omittedCount: Int?
    let omittedKeys: [String]?

    init(elements: [HeistElement], limit: Int) {
        let visible = Array(elements.prefix(max(0, limit)))
        self.elements = visible
        let omittedElements = Array(elements.dropFirst(visible.count))
        omittedCount = omittedElements.isEmpty ? nil : omittedElements.count
        omittedKeys = omittedElements.isEmpty
            ? nil
            : omittedElements.map(Self.omissionKey(for:))
    }

    var isEmpty: Bool {
        elements.isEmpty
    }

    static func omissionKey(for element: HeistElement) -> String {
        if let identifier = element.identifier, !identifier.isEmpty {
            return "identifier:\(identifier)"
        }
        if let label = element.label, !label.isEmpty {
            return "label:\(label)"
        }
        if let value = element.value, !value.isEmpty {
            return "value:\(value)"
        }
        return "description:\(element.description)"
    }
}

struct ElementUpdateProjectionBucket: Sendable {
    let updates: [ElementUpdate]
    let omittedCount: Int?
    let omittedKeys: [String]?

    init(updates: [ElementUpdate], limit: Int) {
        let visible = Array(updates.prefix(max(0, limit)))
        self.updates = visible
        let omittedUpdates = Array(updates.dropFirst(visible.count))
        omittedCount = omittedUpdates.isEmpty ? nil : omittedUpdates.count
        omittedKeys = omittedUpdates.isEmpty
            ? nil
            : omittedUpdates.map { ElementProjectionBucket.omissionKey(for: $0.after) }
    }

    var isEmpty: Bool {
        updates.isEmpty
    }
}

struct DeltaEditsProjection: Sendable {
    let added: ElementProjectionBucket
    let removed: ElementProjectionBucket
    let updated: ElementUpdateProjectionBucket

    init(edits: ElementEdits, profile: ProjectionProfile) {
        let limit = profile.limits.deltaElementsPerBucket
        added = ElementProjectionBucket(elements: edits.added, limit: limit)
        removed = ElementProjectionBucket(elements: edits.removed, limit: limit)
        let meaningfulUpdates = edits.updated.compactMap { update -> ElementUpdate? in
            let changes = update.changes.filter { !$0.property.isGeometry }
            guard !changes.isEmpty else { return nil }
            return ElementUpdate(before: update.before, after: update.after, changes: changes)
        }
        updated = ElementUpdateProjectionBucket(updates: meaningfulUpdates, limit: limit)
    }

    var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && updated.isEmpty
    }
}

struct DeltaScreenProjection: Sendable {
    let screenDescription: String
    let screenId: String?
    let elementCount: Int
    let elements: [HeistElement]
    let omittedElementCount: Int?
    let interface: Interface?

    init(interface: Interface, profile: ProjectionProfile, includeInterface: Bool) {
        let projectedElements = interface.projectedElements
        let visible = Array(projectedElements.prefix(max(0, profile.limits.screenPreviewElements)))
        screenDescription = InterfaceSummary.screenDescription(for: interface)
        screenId = InterfaceSummary.screenId(for: interface)
        elementCount = projectedElements.count
        elements = visible
        let omitted = projectedElements.count - visible.count
        omittedElementCount = omitted > 0 ? omitted : nil
        self.interface = includeInterface ? interface : nil
    }
}

enum DeltaProjectionKind: String, Sendable {
    case noChange
    case elementsChanged
    case screenChanged
}

struct DeltaProjection: Sendable {
    let kind: DeltaProjectionKind
    let elementCount: Int
    let captureEdge: AccessibilityTrace.CaptureEdge?
    let interactionDigest: AccessibilityTrace.InteractionDigest?
    let transient: ElementProjectionBucket
    let edits: DeltaEditsProjection?
    let screen: DeltaScreenProjection?

    init(delta: AccessibilityTrace.Delta, profile: ProjectionProfile, includeScreenInterface: Bool = false) {
        switch delta {
        case .noChange(let payload):
            kind = .noChange
            elementCount = payload.elementCount
            captureEdge = payload.captureEdge
            interactionDigest = payload.interactionDigest
            transient = ElementProjectionBucket(
                elements: payload.transient,
                limit: profile.limits.deltaElementsPerBucket
            )
            edits = nil
            screen = nil
        case .elementsChanged(let payload):
            kind = .elementsChanged
            elementCount = payload.elementCount
            captureEdge = payload.captureEdge
            interactionDigest = payload.interactionDigest
            transient = ElementProjectionBucket(
                elements: payload.transient,
                limit: profile.limits.deltaElementsPerBucket
            )
            let editProjection = DeltaEditsProjection(edits: payload.edits, profile: profile)
            edits = editProjection.isEmpty ? nil : editProjection
            screen = nil
        case .screenChanged(let payload):
            kind = .screenChanged
            elementCount = payload.elementCount
            captureEdge = payload.captureEdge
            interactionDigest = payload.interactionDigest
            transient = ElementProjectionBucket(
                elements: payload.transient,
                limit: profile.limits.deltaElementsPerBucket
            )
            edits = nil
            screen = DeltaScreenProjection(
                interface: payload.newInterface,
                profile: profile,
                includeInterface: includeScreenInterface
            )
        }
    }
}

// MARK: - Action Projection

struct ExpectationProjection: Sendable {
    let met: Bool
    let actual: String?
    let expected: AccessibilityPredicate?
    let hint: String?

    init(result: ExpectationResult, hint: String? = nil) {
        met = result.met
        actual = result.actual
        expected = result.predicate
        self.hint = hint
    }
}

enum ActionPayloadProjection: Sendable {
    case value(String)
    case rotor(RotorResult)
    case screenshot(width: Double, height: Double)
    case heistExecutionStepCount(Int)
    case none
}

enum ActionMethodProjection: Sendable, Equatable, CustomStringConvertible {
    case fence(TheFence.Command)
    case heist(HeistActionCommand)
    case result(ActionMethod)

    var rawValue: String {
        switch self {
        case .fence(let command):
            return command.rawValue
        case .heist(let command):
            return command.wireType.rawValue
        case .result(let method):
            return method.rawValue
        }
    }

    var description: String { rawValue }
}

struct ActionProjection: Sendable {
    let status: PublicResponseStatus
    let actionMethod: ActionMethodProjection
    let message: String?
    let payload: ActionPayloadProjection
    let delta: DeltaProjection?
    let screenName: String?
    let screenId: String?
    let failure: ActionFailureProjection?
    let expectation: ExpectationProjection?
    let activationTrace: ActivationTrace?
    let timing: ActionPerformanceTiming?
    let omitted: ActionResultOmissionsProjection?

    init(
        actionMethod: ActionMethodProjection,
        result: ActionResult,
        expectation: ExpectationResult? = nil,
        expectationHint: String? = nil,
        profile: ProjectionProfile,
        includeOmissions: Bool = false
    ) {
        let surfacedExpectation = result.success ? expectation : nil
        status = result.publicStatus(expectation: surfacedExpectation)
        self.actionMethod = actionMethod
        message = result.message
        switch result.payload {
        case .value(let value):
            payload = .value(value)
        case .rotor(let rotor):
            payload = .rotor(rotor)
        case .screenshot(let screen):
            payload = .screenshot(width: screen.width, height: screen.height)
        case .heistExecution(let heist):
            payload = .heistExecutionStepCount(heist.steps.count)
        case .none:
            payload = .none
        }
        delta = result.accessibilityTrace?.endpointDelta.map {
            DeltaProjection(delta: $0, profile: profile, includeScreenInterface: true)
        }
        screenName = result.accessibilityTrace?.endpointScreenName
        screenId = result.accessibilityTrace?.endpointScreenId
        failure = result.diagnosticFailureProjection(fallbackMessage: actionMethod.rawValue)
        self.expectation = surfacedExpectation.map {
            ExpectationProjection(result: $0, hint: expectationHint)
        }
        activationTrace = result.activationTrace
        timing = result.timing
        omitted = includeOmissions ? ActionResultOmissionsProjection(result: result) : nil
    }
}

struct ActionResultOmissionsProjection: Sendable {
    let accessibilityTrace: ProjectionOmission?
    let subjectEvidence: ProjectionOmission?

    init(result: ActionResult) {
        accessibilityTrace = result.accessibilityTrace.map {
            ProjectionOmission(
                reason: .rawAccessibilityTrace,
                projectedAs: "delta",
                omittedCount: $0.captures.count
            )
        }
        subjectEvidence = result.subjectEvidence.map { _ in
            ProjectionOmission(
                reason: .rawSubjectEvidence,
                projectedAs: nil,
                omittedCount: nil
            )
        }
    }

    var isEmpty: Bool {
        accessibilityTrace == nil && subjectEvidence == nil
    }
}

struct ProjectionOmission: Sendable {
    let reason: ProjectionOmissionReason
    let projectedAs: String?
    let omittedCount: Int?
}

struct HeistReportFailureProjection: Sendable {
    let detail: HeistFailureDetail
    let diagnosticFailure: DiagnosticFailure

    init(detail: HeistFailureDetail, message: String, actionErrorKind: ErrorKind?) {
        self.detail = detail
        if let actionErrorKind {
            diagnosticFailure = DiagnosticFailureMapper.map(errorKind: actionErrorKind, message: message)
        } else {
            diagnosticFailure = DiagnosticFailureMapper.map(reportFailure: detail, message: message)
        }
    }
}

// MARK: - Heist Report Projection

struct HeistReportSummaryProjection: Sendable {
    let executedTopLevelStepCount: Int
    let executedNodeCount: Int
    let outputReceiptNodeCount: Int
    let abortedAtPath: String?
    let durationMs: Int
    let expectationsChecked: Int
    let expectationsMet: Int

    var expectations: HeistExpectationsProjection? {
        expectationsChecked > 0
            ? HeistExpectationsProjection(checked: expectationsChecked, met: expectationsMet)
            : nil
    }

    init(result: HeistExecutionResult, outputReceiptNodeCount: Int) {
        executedTopLevelStepCount = result.executedTopLevelStepCount
        executedNodeCount = result.executedNodeCount
        self.outputReceiptNodeCount = outputReceiptNodeCount
        abortedAtPath = result.abortedAtPath
        durationMs = result.durationMs
        expectationsChecked = result.expectationsChecked
        expectationsMet = result.expectationsMet
    }
}

struct HeistExpectationsProjection: Sendable {
    let checked: Int
    let met: Int
    let allMet: Bool

    init(checked: Int, met: Int) {
        self.checked = checked
        self.met = met
        allMet = checked == met
    }
}

struct HeistReportProjection: Sendable {
    let status: PublicResponseStatus
    let summary: HeistReportSummaryProjection
    let nodes: [HeistReportNodeProjection]
    let outputNodes: [HeistReportNodeProjection]
    let failedStepPath: String?
    let failureScreenshotSummary: String?
    let failureInterfaceDump: String?
    let netDelta: DeltaProjection?
    let finalScreenId: String?

    init(
        result: HeistExecutionResult,
        netDelta: AccessibilityTrace.Delta?,
        profile: ProjectionProfile
    ) {
        status = result.abortedAtPath == nil ? .ok : .partial
        nodes = result.steps.map { HeistReportNodeProjection(step: $0, profile: profile) }
        outputNodes = nodes.flatMap(\.flattened)
        summary = HeistReportSummaryProjection(result: result, outputReceiptNodeCount: outputNodes.count)
        failedStepPath = result.failedStepPath
        failureScreenshotSummary = result.failureScreenshotSummary
        failureInterfaceDump = result.failureInterfaceDump(
            elementLimit: profile.limits.failureInterfaceElements
        )
        self.netDelta = netDelta.map { DeltaProjection(delta: $0, profile: profile, includeScreenInterface: true) }
        finalScreenId = result.traceResultsInExecutionOrder
            .compactMap { $0.accessibilityTrace?.endpointScreenId }
            .last
    }
}

struct HeistReportNodeProjection: Sendable {
    let path: String
    let kind: String
    let capability: String?
    let displayName: String
    let commandName: String?
    let target: ElementTarget?
    let status: HeistExecutionStepStatus
    let message: String?
    let durationMs: Int
    let intent: HeistStepIntent?
    let evidence: HeistReportEvidenceProjection?
    let failure: HeistReportFailureProjection?
    let failureMessage: String?
    let failureCategory: HeistFailureCategory?
    let abortedAtChildPath: String?
    let expectation: ExpectationProjection?
    let actionErrorKind: ErrorKind?
    let traceDelta: DeltaProjection?
    let children: [HeistReportNodeProjection]

    init(step: HeistExecutionStepResult, profile: ProjectionProfile) {
        let reportedFailureMessage = step.reportFailureMessage
        let reportedActionErrorKind = step.reportActionResult?.success == false ? step.reportActionResult?.errorKind : nil

        path = step.path
        kind = step.reportStepName
        capability = step.invocationEvidence?.invocation?.capabilityName
        displayName = step.reportDisplayName
        commandName = step.reportCommandName
        target = step.reportTarget
        status = step.status
        message = step.reportMessage
        durationMs = step.durationMs
        intent = step.intent
        evidence = HeistReportEvidenceProjection(step: step, profile: profile)
        failureMessage = reportedFailureMessage
        failure = step.failure.map {
            HeistReportFailureProjection(
                detail: $0,
                message: reportedFailureMessage ?? $0.observed,
                actionErrorKind: reportedActionErrorKind
            )
        }
        failureCategory = step.failure?.category
        abortedAtChildPath = step.abortedAtChildPath
        expectation = step.reportExpectation.map { ExpectationProjection(result: $0) }
        actionErrorKind = reportedActionErrorKind
        traceDelta = step.traceEvidenceResult?.accessibilityTrace?.endpointDelta.map {
            DeltaProjection(delta: $0, profile: profile, includeScreenInterface: true)
        }
        children = step.children.map { HeistReportNodeProjection(step: $0, profile: profile) }
    }

    var flattened: [HeistReportNodeProjection] {
        [self] + children.flatMap(\.flattened)
    }
}

enum HeistReportEvidenceProjection: Sendable {
    case action(HeistActionEvidenceProjection)
    case wait(HeistWaitEvidenceProjection)
    case caseSelection(HeistCaseSelectionEvidenceProjection)
    case forEachString(HeistForEachStringEvidenceProjection)
    case forEachElement(HeistForEachElementEvidenceProjection)
    case repeatUntil(HeistRepeatUntilEvidenceProjection)
    case invocation(HeistInvocationEvidenceProjection)
    case warning(HeistWarningEvidenceProjection)

    init?(step: HeistExecutionStepResult, profile: ProjectionProfile) {
        guard let evidence = step.evidence else { return nil }
        switch evidence {
        case .action(let evidence):
            self = .action(HeistActionEvidenceProjection(evidence: evidence, profile: profile))
        case .wait(let evidence):
            self = .wait(HeistWaitEvidenceProjection(evidence: evidence, profile: profile))
        case .caseSelection(let evidence):
            self = .caseSelection(HeistCaseSelectionEvidenceProjection(evidence: evidence, profile: profile))
        case .forEachString(let evidence):
            self = .forEachString(HeistForEachStringEvidenceProjection(evidence: evidence))
        case .forEachElement(let evidence):
            self = .forEachElement(HeistForEachElementEvidenceProjection(evidence: evidence))
        case .repeatUntil(let evidence):
            self = .repeatUntil(HeistRepeatUntilEvidenceProjection(evidence: evidence, profile: profile))
        case .invocation(let evidence):
            self = .invocation(HeistInvocationEvidenceProjection(evidence: evidence, profile: profile))
        case .warning(let warning):
            self = .warning(HeistWarningEvidenceProjection(warning: warning))
        }
    }

    var warning: HeistWarningEvidenceProjection? {
        guard case .warning(let warning) = self else { return nil }
        return warning
    }
}

struct HeistActionEvidenceProjection: Sendable {
    let commandName: String?
    let target: ElementTarget?
    let result: ActionProjection?
    let expectationResult: ActionProjection?
    let expectation: ExpectationProjection?

    init(evidence: HeistActionEvidence, profile: ProjectionProfile) {
        commandName = evidence.command?.wireType.rawValue
        target = evidence.command?.reportTarget
        result = evidence.actionResult.map {
            ActionProjection(
                actionMethod: evidence.command.map(ActionMethodProjection.heist) ?? .result($0.method),
                result: $0,
                profile: profile,
                includeOmissions: true
            )
        }
        expectationResult = evidence.expectationActionResult.map {
            ActionProjection(actionMethod: .result($0.method), result: $0, profile: profile, includeOmissions: true)
        }
        expectation = evidence.expectation.map { ExpectationProjection(result: $0) }
    }
}

struct HeistWaitEvidenceProjection: Sendable {
    let result: ActionProjection
    let expectation: ExpectationProjection
    let baselineSummary: String?
    let finalSummary: String?

    init(evidence: HeistWaitEvidence, profile: ProjectionProfile) {
        result = ActionProjection(
            actionMethod: .result(evidence.actionResult.method),
            result: evidence.actionResult,
            profile: profile,
            includeOmissions: true
        )
        expectation = ExpectationProjection(result: evidence.expectation)
        baselineSummary = evidence.baselineSummary
        finalSummary = evidence.finalSummary
    }
}

struct HeistCaseSelectionEvidenceProjection: Sendable {
    let outcome: HeistCaseSelectionOutcome
    let elapsedMs: Int
    let timeout: Double?
    let lastObservedSummary: String?
    let caseCount: Int
    let cases: [HeistCaseMatchProjection]
    let omittedCaseCount: Int?

    init(evidence: HeistCaseSelectionEvidence, profile: ProjectionProfile) {
        let selection = evidence.selection
        outcome = selection.outcome
        elapsedMs = selection.elapsedMs
        timeout = selection.timeout
        lastObservedSummary = selection.lastObservedSummary
        caseCount = selection.cases.count
        let visibleCases = Array(selection.cases.prefix(profile.limits.caseResults))
        cases = visibleCases.map(HeistCaseMatchProjection.init(match:))
        let omitted = selection.cases.count - visibleCases.count
        omittedCaseCount = omitted > 0 ? omitted : nil
    }
}

struct HeistCaseMatchProjection: Sendable {
    let predicate: AccessibilityPredicate
    let met: Bool
    let actual: String?

    init(match: HeistCaseMatchResult) {
        predicate = match.predicate
        met = match.result.met
        actual = match.result.actual
    }
}

struct HeistForEachStringEvidenceProjection: Sendable {
    let parameter: HeistReferenceName
    let count: Int
    let iterationCount: Int
    let iterationOrdinal: Int?
    let value: String?
    let failureReason: String?

    init(evidence: HeistForEachStringEvidence) {
        parameter = evidence.parameter
        count = evidence.count
        iterationCount = evidence.iterationCount
        iterationOrdinal = evidence.iterationOrdinal
        value = evidence.value
        failureReason = evidence.failureReason
    }
}

struct HeistForEachElementEvidenceProjection: Sendable {
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
        parameter = evidence.parameter
        matching = evidence.matching
        limit = evidence.limit
        matchedCount = evidence.matchedCount
        iterationCount = evidence.iterationCount
        iterationOrdinal = evidence.iterationOrdinal
        targetOrdinal = evidence.targetOrdinal
        targetSummary = evidence.targetSummary
        failureReason = evidence.failureReason
    }
}

struct HeistRepeatUntilEvidenceProjection: Sendable {
    let predicate: AccessibilityPredicate
    let timeout: Double
    let iterationCount: Int
    let iterationOrdinal: Int?
    let expectation: ExpectationProjection
    let result: ActionProjection?
    let lastObservedSummary: String?
    let failureReason: String?

    init(evidence: HeistRepeatUntilEvidence, profile: ProjectionProfile) {
        predicate = evidence.predicate
        timeout = evidence.timeout
        iterationCount = evidence.iterationCount
        iterationOrdinal = evidence.iterationOrdinal
        expectation = ExpectationProjection(result: evidence.expectation)
        result = evidence.actionResult.map {
            ActionProjection(actionMethod: .result($0.method), result: $0, profile: profile, includeOmissions: true)
        }
        lastObservedSummary = evidence.lastObservedSummary
        failureReason = evidence.failureReason
    }
}

struct HeistInvocationEvidenceProjection: Sendable {
    let capability: String?
    let name: String?
    let argument: String?
    let childFailedPath: String?
    let expectationResult: ActionProjection?
    let expectation: ExpectationProjection?

    init(evidence: HeistInvocationEvidence, profile: ProjectionProfile) {
        capability = evidence.invocation?.capabilityName
        name = evidence.name
        argument = evidence.argument
        childFailedPath = evidence.childFailedPath
        expectationResult = evidence.expectationActionResult.map {
            ActionProjection(actionMethod: .result($0.method), result: $0, profile: profile, includeOmissions: true)
        }
        expectation = evidence.expectation.map { ExpectationProjection(result: $0) }
    }
}

struct HeistWarningEvidenceProjection: Sendable {
    let path: String
    let message: String

    init(warning: HeistExecutionWarning) {
        path = warning.path
        message = warning.message
    }
}
