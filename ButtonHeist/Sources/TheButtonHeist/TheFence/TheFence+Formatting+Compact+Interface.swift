import Foundation

import AccessibilitySnapshotModel
import TheScore

extension FenceResponse {

    /// Compact one-line element format for LLM agents. Geometry is omitted.
    public static func compactElementLine(
        _ element: HeistElement,
        displayIndex: Int? = nil,
        detail: InterfaceDetail = .summary
    ) -> String {
        var parts: [String] = []
        if let displayIndex { parts.append("[\(displayIndex)]") }

        var labelValue = quotedString(nonEmpty(element.label) ?? "")
        if let value = nonEmpty(element.value) {
            labelValue += ":\(quotedString(value))"
        }
        parts.append(labelValue)

        let traits = element.traits.filter { $0.rawValue != "none" }
        if !traits.isEmpty {
            parts.append(traits.map(\.rawValue).joined(separator: " | "))
        }

        let actions = meaningfulActions(element)
        if !actions.isEmpty {
            parts.append("{\(actions.map(\.description).joined(separator: ", "))}")
        }
        if let rotors = element.rotors?.compactMap({ nonEmpty($0.name) }), !rotors.isEmpty {
            parts.append("[\(rotors.joined(separator: ", "))]")
        }
        if let hint = nonEmpty(element.hint) {
            parts.append("hint=\(quotedString(hint))")
        }
        if let identifier = nonEmpty(element.identifier) {
            parts.append("id=\(quotedString(identifier))")
        }
        if detail == .full {
            parts.append("frame=(\(Int(element.frameX)),\(Int(element.frameY)),\(Int(element.frameWidth)),\(Int(element.frameHeight)))")
            parts.append("activation=(\(Int(element.activationPointX)),\(Int(element.activationPointY)))")
        }

        return parts.joined(separator: " ")
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    static func quotedString(_ value: String) -> String {
        // Boundary try?: compact presentation escapes strings for display only;
        // failed JSON encoding falls back to a deterministic local escape.
        if let data = try? JSONEncoder().encode(value),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    static func compactInterface(
        _ interface: Interface,
        detail: InterfaceDetail = .summary,
        visibleElementBudget: Int = ButtonHeistRuntimeKnobs.current.visibleElementBudget,
        totalNodeBudget: Int = ButtonHeistRuntimeKnobs.current.totalNodeBudget
    ) -> String {
        var lines: [String] = ["\(interface.projectedElements.count) elements"]
        lines.append(contentsOf: compactDiscoveryDiagnostics(interface.diagnostics?.discovery))
        lines.append(contentsOf: compactTreeLines(
            interface,
            detail: detail,
            visibleElementBudget: visibleElementBudget,
            totalNodeBudget: totalNodeBudget
        ))
        return lines.joined(separator: "\n")
    }

    private static func compactDiscoveryDiagnostics(
        _ diagnostics: InterfaceDiscoveryDiagnostics?
    ) -> [String] {
        guard let diagnostics else { return [] }
        let reason = diagnostics.reasonCodes.isEmpty ? "" : "[\(diagnostics.reasonCodes.joined(separator: ","))]"
        var lines = [
            """
            discovery: \(diagnostics.state)\(reason) includedElements=\(diagnostics.includedElementCount) \
            scrollAttempts=\(diagnostics.scrollAttempts)/\(diagnostics.maxScrollsPerDiscovery) \
            maxScrollsPerContainer=\(diagnostics.maxScrollsPerContainer) \
            exploredContainers=\(diagnostics.exploredScrollableContainerCount) \
            omittedContainers=\(diagnostics.omittedScrollableContainerCount)
            """,
        ]
        for omittedContainer in diagnostics.omittedContainers.prefix(3) {
            lines.append("  omitted: \(compactDiscoveryOmittedContainer(omittedContainer))")
        }
        let omittedRemainder = diagnostics.omittedContainers.count - 3
        if omittedRemainder > 0 {
            lines.append("  omitted: \(omittedRemainder) more")
        }
        if let nextAction = nonEmpty(diagnostics.nextAction) {
            lines.append("  next: \(nextAction)")
        }
        return lines
    }

    private static func compactDiscoveryOmittedContainer(
        _ container: InterfaceDiscoveryOmittedContainer
    ) -> String {
        var parts = [container.type]
        if let containerName = nonEmpty(container.containerName?.rawValue) {
            parts.append("containerName=\(quotedString(containerName))")
        }
        if let scrollAxis = container.scrollAxis {
            parts.append("scrollAxis=\(scrollAxis.rawValue)")
        }
        if let viewportWidth = container.viewportWidth,
           let viewportHeight = container.viewportHeight {
            parts.append("viewport=\(Int(viewportWidth))x\(Int(viewportHeight))")
        }
        if let contentWidth = container.contentWidth,
           let contentHeight = container.contentHeight {
            parts.append("content=\(Int(contentWidth))x\(Int(contentHeight))")
        }
        if !container.reasonCodes.isEmpty {
            parts.append("reason=\(container.reasonCodes.joined(separator: ","))")
        }
        return parts.joined(separator: " ")
    }

    static func compactTreeLines(
        _ interface: Interface,
        detail: InterfaceDetail,
        visibleElementBudget: Int = ButtonHeistRuntimeKnobs.current.visibleElementBudget,
        totalNodeBudget: Int = ButtonHeistRuntimeKnobs.current.totalNodeBudget
    ) -> [String] {
        let counter = LineIndexCounter()
        let elementAnnotations = interface.annotations.elementByPath
        let containerAnnotations = interface.annotations.containerByPath
        let totalNodeBudgetTracker = PublicNodeBudgetTracker(budget: totalNodeBudget)
        let projectionStats = PublicInterfaceProjectionStats(observedElementCount: interface.projectedElements.count)
        let context = CompactTreeRenderContext(
            detail: detail,
            counter: counter,
            elementAnnotations: elementAnnotations,
            containerAnnotations: containerAnnotations,
            visibleElementBudget: visibleElementBudget,
            totalNodeBudget: totalNodeBudgetTracker,
            projectionStats: projectionStats
        )
        var remainingElements: Int?
        var lines: [String] = []
        for (index, node) in interface.tree.enumerated() {
            lines.append(contentsOf: compactTreeLines(
                node,
                path: TreePath([index]),
                context: context,
                remainingElements: &remainingElements
            ))
        }
        if totalNodeBudgetTracker.wasLimited {
            let omittedElementCount = max(
                0,
                projectionStats.observedElementCount - projectionStats.renderedElementCount
            )
            lines.append(
                "... interface truncated: omitted \(omittedElementCount) observed elements " +
                "(totalNodeBudget=\(totalNodeBudgetTracker.budget))"
            )
        }
        return lines
    }

    /// Reference counter used by `compactTreeLines` to thread display indices
    /// through the parser hierarchy recursion.
    private final class LineIndexCounter {
        var value: Int = 0
    }

    private struct CompactTreeRenderContext {
        let detail: InterfaceDetail
        let counter: LineIndexCounter
        let elementAnnotations: [TreePath: InterfaceElementAnnotation]
        let containerAnnotations: [TreePath: InterfaceContainerAnnotation]
        let visibleElementBudget: Int
        let totalNodeBudget: PublicNodeBudgetTracker
        let projectionStats: PublicInterfaceProjectionStats
    }

    private static func compactTreeLines(
        _ node: AccessibilityHierarchy,
        path: TreePath,
        context: CompactTreeRenderContext,
        remainingElements: inout Int?
    ) -> [String] {
        switch node {
        case .element(let element, _):
            let index = context.counter.value
            context.counter.value += 1
            if let remaining = remainingElements {
                guard remaining > 0 else { return [] }
            }
            guard context.totalNodeBudget.consumeNode() else { return [] }
            if let remaining = remainingElements {
                remainingElements = remaining - 1
            }
            context.projectionStats.recordRenderedElement()
            let projected = HeistElement(
                accessibilityElement: element,
                annotation: context.elementAnnotations[path]
            )
            return [compactElementLine(projected, displayIndex: index, detail: context.detail)]

        case .container(let container, let children):
            var observedElementCount = 0
            for child in children {
                observedElementCount += child.pathIndexedElements().count
            }
            let isScrollable = {
                if case .scrollable = container.type { return true }
                return false
            }()
            if let remaining = remainingElements, remaining <= 0 {
                context.counter.value += observedElementCount
                return []
            }
            guard context.totalNodeBudget.consumeNode() else {
                context.counter.value += observedElementCount
                return []
            }
            let header = compactContainerLine(
                container,
                annotation: context.containerAnnotations[path],
                detail: context.detail,
                observedElementCount: observedElementCount
            )
            let budgetCap = max(0, context.visibleElementBudget)
            let shouldTruncate = isScrollable && observedElementCount > budgetCap
            let parentRemainingBefore = remainingElements
            var scrollRemainingElements: Int? = shouldTruncate
                ? min(parentRemainingBefore ?? budgetCap, budgetCap)
                : nil
            var body: [String] = []

            for (index, child) in children.enumerated() {
                let lines: [String]
                if shouldTruncate {
                    lines = compactTreeLines(
                        child,
                        path: path.appending(index),
                        context: context,
                        remainingElements: &scrollRemainingElements
                    )
                } else {
                    lines = compactTreeLines(
                        child,
                        path: path.appending(index),
                        context: context,
                        remainingElements: &remainingElements
                    )
                }
                body.append(contentsOf: indented(lines: lines))
            }

            if shouldTruncate {
                let effectiveBudget = min(parentRemainingBefore ?? budgetCap, budgetCap)
                let renderedElementCount = max(0, effectiveBudget - (scrollRemainingElements ?? 0))
                if let parentRemainingBefore {
                    remainingElements = max(0, parentRemainingBefore - renderedElementCount)
                }
                let omittedElementCount = max(0, observedElementCount - renderedElementCount)
                let scrollBudgetHit = (scrollRemainingElements ?? 0) <= 0
                if scrollBudgetHit, omittedElementCount > 0 {
                    body.append(
                        "  ... subtree truncated: omitted \(omittedElementCount) observed elements " +
                        "(visibleElementBudget=\(budgetCap))"
                    )
                }
            }

            if !isScrollable, remainingElements != nil, observedElementCount > 0, body.isEmpty {
                return []
            }
            return [header] + body
        }
    }

    private static func indented(lines: [String], by depth: Int = 1) -> [String] {
        guard depth > 0 else { return lines }
        let prefix = String(repeating: "  ", count: depth)
        return lines.map { prefix + $0 }
    }

    private static func compactContainerLine(
        _ container: AccessibilityContainer,
        annotation: InterfaceContainerAnnotation?,
        detail: InterfaceDetail,
        observedElementCount: Int? = nil
    ) -> String {
        var parts: [String]
        switch container.type {
        case .semanticGroup(let label, let value, let identifier):
            parts = ["group"]
            if let label = nonEmpty(label) { parts.append("label=\(quotedString(label))") }
            if let value = nonEmpty(value) { parts.append("value=\(quotedString(value))") }
            if let identifier = nonEmpty(identifier) { parts.append("id=\(quotedString(identifier))") }
            if let containerName = nonEmpty(annotation?.containerName?.rawValue) {
                parts.append("containerName=\(quotedString(containerName))")
            }
        case .list:
            parts = ["list"]
            if let containerName = nonEmpty(annotation?.containerName?.rawValue) {
                parts.append("containerName=\(quotedString(containerName))")
            }
        case .landmark:
            parts = ["landmark"]
            if let containerName = nonEmpty(annotation?.containerName?.rawValue) {
                parts.append("containerName=\(quotedString(containerName))")
            }
        case .dataTable(let rowCount, let columnCount):
            parts = ["table", "rows=\(rowCount)", "columns=\(columnCount)"]
            if let containerName = nonEmpty(annotation?.containerName?.rawValue) {
                parts.append("containerName=\(quotedString(containerName))")
            }
        case .tabBar:
            parts = ["tab_bar"]
            if let containerName = nonEmpty(annotation?.containerName?.rawValue) {
                parts.append("containerName=\(quotedString(containerName))")
            }
        case .scrollable(let contentSize):
            let frame = container.frame
            parts = ["scrollable"]
            if let containerName = nonEmpty(annotation?.containerName?.rawValue) {
                parts.append("containerName=\(quotedString(containerName))")
            }
            parts.append("viewport=\(Int(frame.size.width))x\(Int(frame.size.height))")
            parts.append("content=\(Int(contentSize.width))x\(Int(contentSize.height))")
            let scrollAxis = ScrollContainerMetrics.axis(
                contentWidth: Double(contentSize.width),
                contentHeight: Double(contentSize.height),
                viewportWidth: Double(frame.size.width),
                viewportHeight: Double(frame.size.height)
            )
            parts.append("scrollAxis=\(scrollAxis.rawValue)")
            let horizontalPageScrolls = ScrollContainerMetrics.estimatedHorizontalPageScrolls(
                contentWidth: Double(contentSize.width),
                viewportWidth: Double(frame.size.width)
            )
            if horizontalPageScrolls > 0 {
                parts.append("pageScrollsX=\(horizontalPageScrolls)")
            }
            let verticalPageScrolls = ScrollContainerMetrics.estimatedVerticalPageScrolls(
                contentHeight: Double(contentSize.height),
                viewportHeight: Double(frame.size.height)
            )
            if verticalPageScrolls > 0 {
                parts.append("pageScrollsY=\(verticalPageScrolls)")
            }
            if let observedElementCount {
                parts.append("observedElementCount=\(observedElementCount)")
            }
        }
        if container.isModalBoundary {
            parts.append("modal=true")
        }
        if detail == .full {
            let frame = container.frame
            parts.append(
                "frame=(\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.size.width)),\(Int(frame.size.height)))"
            )
        }
        return parts.joined(separator: " ")
    }

}
