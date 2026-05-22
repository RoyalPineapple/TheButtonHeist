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
        parts.append(element.heistId)

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

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func quotedString(_ value: String) -> String {
        if let data = try? JSONEncoder().encode(value),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    static func compactInterface(_ interface: Interface) -> String {
        var lines: [String] = ["\(interface.elements.count) elements"]
        lines.append(contentsOf: compactTreeLines(interface, detail: .summary))
        return lines.joined(separator: "\n")
    }

    static func compactTreeLines(
        _ interface: Interface,
        detail: InterfaceDetail
    ) -> [String] {
        let counter = LineIndexCounter()
        let elementAnnotations = interface.annotations.elementByPath
        let containerAnnotations = interface.annotations.containerByPath
        return interface.tree.enumerated().flatMap { index, node in
            compactTreeLines(
                node,
                path: TreePath([index]),
                detail: detail,
                counter: counter,
                elementAnnotations: elementAnnotations,
                containerAnnotations: containerAnnotations
            )
        }
    }

    /// Reference counter used by `compactTreeLines` to thread display indices
    /// through the parser hierarchy recursion.
    private final class LineIndexCounter {
        var value: Int = 0
    }

    private static func compactTreeLines(
        _ node: AccessibilityHierarchy,
        path: TreePath,
        detail: InterfaceDetail,
        counter: LineIndexCounter,
        elementAnnotations: [TreePath: InterfaceElementAnnotation],
        containerAnnotations: [TreePath: InterfaceContainerAnnotation]
    ) -> [String] {
        switch node {
        case .element(let element, _):
            let projected = HeistElement(
                accessibilityElement: element,
                annotation: elementAnnotations[path]
            )
            let index = counter.value
            counter.value += 1
            return [compactElementLine(projected, displayIndex: index, detail: detail)]

        case .container(let container, let children):
            let header = "<\(compactContainerLine(container, annotation: containerAnnotations[path], detail: detail))>"
            let body = children.enumerated().flatMap { index, child in
                indented(lines: compactTreeLines(
                    child,
                    path: path.appending(index),
                    detail: detail,
                    counter: counter,
                    elementAnnotations: elementAnnotations,
                    containerAnnotations: containerAnnotations
                ))
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
        detail: InterfaceDetail
    ) -> String {
        var parts: [String]
        switch container.type {
        case .semanticGroup(let label, let value, let identifier):
            parts = ["semanticGroup"]
            if let stableId = annotation?.stableId, !stableId.isEmpty { parts.append("stableId=\"\(stableId)\"") }
            if let identifier, !identifier.isEmpty { parts.append("id=\"\(identifier)\"") }
            if let label, !label.isEmpty { parts.append("\"\(label)\"") }
            if let value, !value.isEmpty { parts.append("= \"\(value)\"") }
        case .list:
            parts = ["list"]
            if let stableId = annotation?.stableId, !stableId.isEmpty { parts.append("stableId=\"\(stableId)\"") }
        case .landmark:
            parts = ["landmark"]
            if let stableId = annotation?.stableId, !stableId.isEmpty { parts.append("stableId=\"\(stableId)\"") }
        case .dataTable(let rowCount, let columnCount):
            parts = ["dataTable", "\(rowCount)x\(columnCount)"]
            if let stableId = annotation?.stableId, !stableId.isEmpty { parts.append("stableId=\"\(stableId)\"") }
        case .tabBar:
            parts = ["tabBar"]
            if let stableId = annotation?.stableId, !stableId.isEmpty { parts.append("stableId=\"\(stableId)\"") }
        case .scrollable(let contentSize):
            parts = ["scrollable", "= \"\(Int(contentSize.width))x\(Int(contentSize.height))\""]
            if let stableId = annotation?.stableId, !stableId.isEmpty { parts.append("stableId=\"\(stableId)\"") }
        }
        if container.isModalBoundary {
            parts.append("modal")
        }
        if let actions = annotation?.actions, !actions.isEmpty {
            parts.append("{\(actions.map(\.description).joined(separator: ","))}")
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
