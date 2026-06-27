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
        HeistFailureDiagnostics.elementLine(
            element,
            displayIndex: displayIndex,
            includeGeometry: detail == .full
        )
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
        let profile = ProjectionProfile(
            kind: detail == .full ? .full : .summary,
            limits: .current(
                visibleElementBudget: visibleElementBudget,
                totalNodeBudget: totalNodeBudget
            )
        )
        return compactInterface(InterfaceProjection(interface: interface, profile: profile))
    }

    static func compactInterface(_ projection: InterfaceProjection) -> String {
        var lines: [String] = ["\(projection.elementCount) elements"]
        lines.append(contentsOf: compactDiscoveryDiagnostics(projection.diagnostics?.discovery))
        lines.append(contentsOf: compactTreeLines(projection))
        return lines.joined(separator: "\n")
    }

    private static func compactDiscoveryDiagnostics(
        _ diagnostics: InterfaceDiscoveryDiagnostics?
    ) -> [String] {
        guard let diagnostics else { return [] }
        let reasonCodes = diagnostics.reasonCodes.map(\.rawValue)
        let reason = reasonCodes.isEmpty ? "" : "[\(reasonCodes.joined(separator: ","))]"
        var lines = [
            """
            discovery: \(diagnostics.state.rawValue)\(reason) includedElements=\(diagnostics.includedElementCount) \
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
            parts.append("reason=\(container.reasonCodes.map(\.rawValue).joined(separator: ","))")
        }
        return parts.joined(separator: " ")
    }

    static func compactTreeLines(
        _ interface: Interface,
        detail: InterfaceDetail,
        visibleElementBudget: Int = ButtonHeistRuntimeKnobs.current.visibleElementBudget,
        totalNodeBudget: Int = ButtonHeistRuntimeKnobs.current.totalNodeBudget
    ) -> [String] {
        let profile = ProjectionProfile(
            kind: detail == .full ? .full : .summary,
            limits: .current(
                visibleElementBudget: visibleElementBudget,
                totalNodeBudget: totalNodeBudget
            )
        )
        return compactTreeLines(InterfaceProjection(interface: interface, profile: profile))
    }

    static func compactTreeLines(_ projection: InterfaceProjection) -> [String] {
        var lines: [String] = []
        for node in projection.tree {
            lines.append(contentsOf: compactTreeLines(node, detail: projection.detail))
        }
        if projection.rendering.reason == .totalNodeBudget,
           let totalNodeBudget = projection.rendering.totalNodeBudget {
            lines.append(
                "... interface truncated: omitted \(projection.rendering.omittedElementCount) observed elements " +
                "(totalNodeBudget=\(totalNodeBudget))"
            )
        }
        return lines
    }

    private static func compactTreeLines(
        _ node: InterfaceNodeProjection,
        detail: InterfaceDetail
    ) -> [String] {
        switch node {
        case .element(let projection):
            return [compactElementLine(projection.element, displayIndex: projection.order, detail: detail)]

        case .container(let projection):
            let header = compactContainerLine(
                projection.container,
                containerName: projection.containerName,
                detail: detail,
                observedElementCount: projection.observedElementCount
            )
            var body = projection.children.flatMap {
                indented(lines: compactTreeLines($0, detail: detail))
            }
            if let truncation = projection.truncation {
                body.append(
                    "  ... subtree truncated: omitted \(truncation.omittedElementCount) observed elements " +
                    "(visibleElementBudget=\(truncation.visibleElementBudget))"
                )
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

    private static func compactContainerLine(
        _ container: AccessibilityContainer,
        containerName: String?,
        detail: InterfaceDetail,
        observedElementCount: Int? = nil
    ) -> String {
        compactContainerLine(
            container,
            annotation: containerName.map {
                InterfaceContainerAnnotation(path: .root, containerName: ContainerName(rawValue: $0))
            },
            detail: detail,
            observedElementCount: observedElementCount
        )
    }

}
