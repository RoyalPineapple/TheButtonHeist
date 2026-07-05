import Foundation

import AccessibilitySnapshotModel
import TheScore

enum ProjectionRenderingState: String, Sendable {
    case full
    case truncated
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

    init(screenTitle: String?, elements: [HeistElement]) {
        self.screenTitle = screenTitle
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
    let scrollInventory: ScrollInventory?
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
        let projectedElementRecords = interface.projectedElementRecords
        let projectedElements = projectedElementRecords.map(\.element)
        let screenTitle = InterfaceSummary.screenTitle(forProjectedElements: projectedElements)

        timestamp = interface.timestamp
        detail = profile.interfaceDetail
        screenDescription = InterfaceSummary.screenDescription(forProjectedElements: projectedElements)
        screenId = InterfaceSummary.screenId(forProjectedElements: projectedElements)
        diagnostics = interface.diagnostics
        navigation = InterfaceNavigationProjection(screenTitle: screenTitle, elements: projectedElements)
        elementCount = projectedElementRecords.count

        var accumulator = InterfaceProjectionAccumulator(totalNodeBudget: profile.limits.totalNodeBudget)
        let context = InterfaceProjectionContext(
            detail: profile.interfaceDetail,
            visibleElementBudget: profile.limits.visibleElementBudget,
            elementsByPath: Dictionary(uniqueKeysWithValues: projectedElementRecords.map { ($0.path, $0.element) }),
            containerAnnotations: interface.annotations.containerByPath
        )
        var counter = 0
        var remainingElements: Int?
        tree = interface.tree.enumerated().compactMap { index, node in
            Self.project(
                InterfaceNodeProjectionRequest(
                    node: node,
                    path: TreePath([index])
                ),
                context: context,
                accumulator: &accumulator,
                counter: &counter,
                remainingElements: &remainingElements
            )
        }
        rendering = accumulator.rendering(
            observedElementCount: elementCount,
            visibleElementBudget: profile.limits.visibleElementBudget,
            totalNodeBudget: profile.limits.totalNodeBudget
        )
    }

    private static func project(
        _ request: InterfaceNodeProjectionRequest,
        context: InterfaceProjectionContext,
        accumulator: inout InterfaceProjectionAccumulator,
        counter: inout Int,
        remainingElements: inout Int?
    ) -> InterfaceNodeProjection? {
        switch request.node {
        case .element:
            let order = counter
            counter += 1
            if let remaining = remainingElements {
                guard remaining > 0 else { return nil }
            }
            guard accumulator.consumeNode() else { return nil }
            if let remaining = remainingElements {
                remainingElements = remaining - 1
            }
            accumulator.recordRenderedElement()
            guard let projected = context.elementsByPath[request.path] else {
                preconditionFailure("InterfaceProjection missing projected element at path \(request.path.indices)")
            }
            return .element(InterfaceElementProjection(element: projected, order: order))

        case .container(let container, let children):
            let observedElementCount = children.reduce(0) { $0 + $1.pathIndexedElements().count }
            if let remaining = remainingElements, remaining <= 0 {
                counter += observedElementCount
                return nil
            }
            guard accumulator.consumeNode() else {
                counter += observedElementCount
                return nil
            }

            let scrollPolicy = ScrollSubtreeProjectionPolicy(
                container: container,
                observedElementCount: observedElementCount,
                visibleElementBudget: context.visibleElementBudget,
                parentRemainingElementBudget: remainingElements
            )
            let childResult = projectChildren(
                InterfaceChildrenProjectionRequest(
                    children: children,
                    parentPath: request.path,
                    remainingElementBudget: scrollPolicy.childRemainingElementBudget
                ),
                context: context,
                accumulator: &accumulator,
                counter: &counter
            )
            remainingElements = scrollPolicy.parentRemainingElementBudget(after: childResult)
            let truncation = scrollPolicy.truncation(after: childResult, accumulator: &accumulator)

            return .container(InterfaceContainerProjection(
                container: container,
                containerName: context.containerAnnotations[request.path]?.containerName?.rawValue,
                scrollInventory: context.containerAnnotations[request.path]?.scrollInventory,
                observedElementCount: observedElementCount,
                truncation: truncation,
                children: childResult.children
            ))
        }
    }

    private static func projectChildren(
        _ request: InterfaceChildrenProjectionRequest,
        context: InterfaceProjectionContext,
        accumulator: inout InterfaceProjectionAccumulator,
        counter: inout Int
    ) -> InterfaceChildrenProjectionResult {
        var remainingElementBudget = request.remainingElementBudget
        let children = request.children.enumerated().compactMap { index, child in
            project(
                InterfaceNodeProjectionRequest(
                    node: child,
                    path: request.parentPath.appending(index)
                ),
                context: context,
                accumulator: &accumulator,
                counter: &counter,
                remainingElements: &remainingElementBudget
            )
        }
        return InterfaceChildrenProjectionResult(
            children: children,
            remainingElementBudget: remainingElementBudget
        )
    }
}

private struct InterfaceProjectionContext {
    let detail: InterfaceDetail
    let visibleElementBudget: Int
    let elementsByPath: [TreePath: HeistElement]
    let containerAnnotations: [TreePath: InterfaceContainerAnnotation]
}

private struct InterfaceNodeProjectionRequest {
    let node: AccessibilityHierarchy
    let path: TreePath
}

private struct InterfaceChildrenProjectionRequest {
    let children: [AccessibilityHierarchy]
    let parentPath: TreePath
    let remainingElementBudget: Int?
}

private struct InterfaceChildrenProjectionResult {
    let children: [InterfaceNodeProjection]
    let remainingElementBudget: Int?
}

private struct ScrollSubtreeProjectionPolicy {
    let observedElementCount: Int
    let visibleElementBudget: Int
    let parentRemainingElementBudget: Int?
    let isActive: Bool

    init(
        container: AccessibilityContainer,
        observedElementCount: Int,
        visibleElementBudget: Int,
        parentRemainingElementBudget: Int?
    ) {
        self.observedElementCount = observedElementCount
        self.visibleElementBudget = max(0, visibleElementBudget)
        self.parentRemainingElementBudget = parentRemainingElementBudget
        isActive = Self.isScrollable(container) && observedElementCount > self.visibleElementBudget
    }

    var childRemainingElementBudget: Int? {
        guard isActive else { return parentRemainingElementBudget }
        return effectiveElementBudget
    }

    func parentRemainingElementBudget(after result: InterfaceChildrenProjectionResult) -> Int? {
        guard isActive else { return result.remainingElementBudget }
        guard let parentRemainingElementBudget else { return nil }
        return max(0, parentRemainingElementBudget - renderedElementCount(after: result))
    }

    func truncation(
        after result: InterfaceChildrenProjectionResult,
        accumulator: inout InterfaceProjectionAccumulator
    ) -> InterfaceSubtreeTruncationProjection? {
        guard isActive else { return nil }

        let renderedElementCount = renderedElementCount(after: result)
        let omittedElementCount = max(0, observedElementCount - renderedElementCount)
        let scrollBudgetHit = (result.remainingElementBudget ?? 0) <= 0
        guard scrollBudgetHit, omittedElementCount > 0 else { return nil }

        accumulator.recordTruncatedScrollContainer()
        return InterfaceSubtreeTruncationProjection(
            reason: .scrollSubtreeElementBudget,
            observedElementCount: observedElementCount,
            renderedElementCount: renderedElementCount,
            omittedElementCount: omittedElementCount,
            visibleElementBudget: visibleElementBudget
        )
    }

    private var effectiveElementBudget: Int {
        min(parentRemainingElementBudget ?? visibleElementBudget, visibleElementBudget)
    }

    private func renderedElementCount(after result: InterfaceChildrenProjectionResult) -> Int {
        max(0, effectiveElementBudget - (result.remainingElementBudget ?? 0))
    }

    private static func isScrollable(_ container: AccessibilityContainer) -> Bool {
        if case .scrollable = container.type { return true }
        return false
    }
}

private struct InterfaceProjectionAccumulator {
    private(set) var renderedElementCount = 0
    private(set) var truncatedScrollContainerCount = 0
    private(set) var remainingNodeBudget: Int
    private(set) var nodeLimitHit = false

    init(totalNodeBudget: Int) {
        remainingNodeBudget = max(0, totalNodeBudget)
    }

    mutating func recordRenderedElement() {
        renderedElementCount += 1
    }

    mutating func recordTruncatedScrollContainer() {
        truncatedScrollContainerCount += 1
    }

    mutating func consumeNode() -> Bool {
        guard remainingNodeBudget > 0 else {
            nodeLimitHit = true
            return false
        }
        remainingNodeBudget -= 1
        return true
    }

    func rendering(
        observedElementCount: Int,
        visibleElementBudget: Int,
        totalNodeBudget: Int
    ) -> InterfaceRenderingProjection {
        let omittedElementCount = max(0, observedElementCount - renderedElementCount)
        guard truncatedScrollContainerCount > 0 || omittedElementCount > 0 || nodeLimitHit else {
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
            reason: nodeLimitHit ? .totalNodeBudget : .scrollSubtreeElementBudget,
            observedElementCount: observedElementCount,
            renderedElementCount: renderedElementCount,
            omittedElementCount: omittedElementCount,
            visibleElementBudget: truncatedScrollContainerCount > 0 ? max(0, visibleElementBudget) : nil,
            totalNodeBudget: nodeLimitHit ? max(0, totalNodeBudget) : nil
        )
    }
}
