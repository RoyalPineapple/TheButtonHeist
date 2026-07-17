import Foundation

import TheScore

import AccessibilitySnapshotModel

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
        var lines: [String] = []
        if let screenTitle = nonEmpty(projection.navigation.screenTitle) {
            lines.append(screenTitle)
        }
        if !projection.screenActions.isEmpty {
            lines.append("Actions: \(projection.screenActions.map(\.rawValue).joined(separator: ", "))")
        }
        lines.append("\(projection.elementCount) elements")
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
        var parts = [container.type.rawValue]
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
                observedElementCount: projection.observedElementCount,
                scrollInventory: projection.scrollInventory
            )
            var body = compactScrollMetadataLine(projection)
            body.append(contentsOf: projection.children.flatMap {
                indented(lines: compactTreeLines($0, detail: detail))
            })
            if let truncation = projection.truncation {
                body.append("  ⋮ \(truncation.omittedElementCount) more")
            } else if let inventoryOmission = inventoryOmissionLine(projection) {
                body.append(inventoryOmission)
            }
            return [header] + body + [compactContainerClosingLine(projection)]
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
        observedElementCount: Int? = nil,
        scrollInventory: ScrollInventory? = nil
    ) -> String {
        let facts = container.containerPredicateFacts
        let identifier = nonEmpty(facts.identifier)
        let containerName = nonEmpty(annotation?.containerName?.rawValue)
        var parts: [String]
        switch facts.role {
        case .none:
            parts = ["container"]
        case .semanticGroup(let label, let value):
            parts = ["group"]
            if let label = nonEmpty(label) { parts.append(quotedString(label)) }
            if let value = nonEmpty(value) { parts.append("value=\(quotedString(value))") }
            if let identifier {
                parts.append("id=\(quotedString(identifier))")
            }
        case .list:
            parts = ["list"]
        case .landmark:
            parts = ["landmark"]
        case .dataTable(let rowCount, let columnCount):
            parts = ["table", "rows=\(rowCount)", "columns=\(columnCount)"]
        case .tabBar:
            parts = ["tab_bar"]
        case .series:
            parts = ["series"]
        }
        if let containerName {
            parts.append(quotedString(containerName))
        }
        if case .semanticGroup = facts.role {
        } else if let identifier {
            parts.append("id=\(quotedString(identifier))")
        }
        let actionNames = container.customActions.map(\.name).filter { !$0.isEmpty }
        if !actionNames.isEmpty {
            parts.append("actions=\(actionNames.map(quotedString).joined(separator: ","))")
        }
        if container.scrollableContentSize != nil, let observedElementCount {
            let totalElementCount = scrollInventory?.totalElementCount
            if let totalElementCount, totalElementCount > observedElementCount {
                parts.append("\(totalElementCount) elements, showing \(observedElementCount)")
            } else {
                parts.append("\(totalElementCount ?? observedElementCount) elements")
            }
        }
        if facts.isModalBoundary {
            parts.append("modal")
        }
        if detail == .full {
            let frame = container.frame
            parts.append(
                "frame=(\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.size.width)),\(Int(frame.size.height)))"
            )
        }
        return "── \(parts.joined(separator: " ")) ──"
    }

    private static func compactContainerLine(
        _ container: AccessibilityContainer,
        containerName: String?,
        detail: InterfaceDetail,
        observedElementCount: Int? = nil,
        scrollInventory: ScrollInventory? = nil
    ) -> String {
        compactContainerLine(
            container,
            annotation: containerName.flatMap {
                try? InterfaceContainerAnnotation(path: .root, containerName: ContainerName(validating: $0))
            },
            detail: detail,
            observedElementCount: observedElementCount,
            scrollInventory: scrollInventory
        )
    }

    private static func compactContainerClosingLine(_ projection: InterfaceContainerProjection) -> String {
        let name = projection.containerName
            ?? semanticContainerLabel(projection.container)
            ?? semanticContainerType(projection.container)
        return "── /\(name) ──"
    }

    private static func compactScrollMetadataLine(_ projection: InterfaceContainerProjection) -> [String] {
        guard let contentSize = projection.container.scrollableContentSize else { return [] }
        let frame = projection.container.frame
        let axis = ScrollContainerMetrics.axis(
            contentWidth: Double(contentSize.width),
            contentHeight: Double(contentSize.height),
            viewportWidth: Double(frame.size.width),
            viewportHeight: Double(frame.size.height)
        )
        let pageScrollsX = ScrollContainerMetrics.estimatedHorizontalPageScrolls(
            contentWidth: Double(contentSize.width),
            viewportWidth: Double(frame.size.width)
        )
        let pageScrollsY = ScrollContainerMetrics.estimatedVerticalPageScrolls(
            contentHeight: Double(contentSize.height),
            viewportHeight: Double(frame.size.height)
        )
        let pages = max(1, max(pageScrollsX, pageScrollsY) + 1)
        return [
            "  \(Int(frame.size.width))×\(Int(frame.size.height)) view, "
                + "\(Int(contentSize.width))×\(Int(contentSize.height)) content "
                + "(\(pages) pages), \(axis.rawValue)",
        ]
    }

    private static func inventoryOmissionLine(_ projection: InterfaceContainerProjection) -> String? {
        guard let totalElementCount = projection.scrollInventory?.totalElementCount else { return nil }
        let omitted = totalElementCount - projection.observedElementCount
        guard omitted > 0 else { return nil }
        return "  ⋮ \(omitted) more"
    }

    private static func semanticContainerType(_ container: AccessibilityContainer) -> String {
        switch container.containerPredicateFacts.role {
        case .none:
            return "container"
        case .semanticGroup:
            return "group"
        case .list:
            return "list"
        case .landmark:
            return "landmark"
        case .dataTable:
            return "table"
        case .tabBar:
            return "tab_bar"
        case .series:
            return "series"
        }
    }

    private static func semanticContainerLabel(_ container: AccessibilityContainer) -> String? {
        if case .semanticGroup(let label, _) = container.containerPredicateFacts.role {
            return nonEmpty(label)
        }
        return nil
    }
}
