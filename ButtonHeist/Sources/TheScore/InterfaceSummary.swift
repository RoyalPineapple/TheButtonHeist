import ThePlans
import Foundation

/// Derived orientation text for public presentation and trace summaries.
///
/// `Interface` stores accessibility capture truth. Screen names and summaries
/// are projections from elements, not stored interface state.
public enum InterfaceSummary {
    public static func screenDescription(for interface: Interface) -> String {
        screenDescription(from: interface.projectedElements)
    }

    public static func screenId(for interface: Interface) -> String? {
        slugify(screenTitle(for: interface))
    }

    public static func screenTitle(for interface: Interface) -> String? {
        screenTitle(from: interface.projectedElements)
    }
}

package extension InterfaceSummary {
    static func screenDescription(forProjectedElements elements: [HeistElement]) -> String {
        screenDescription(from: elements)
    }

    static func screenId(forProjectedElements elements: [HeistElement]) -> String? {
        slugify(screenTitle(from: elements))
    }

    static func screenTitle(forProjectedElements elements: [HeistElement]) -> String? {
        screenTitle(from: elements)
    }
}

private extension InterfaceSummary {
    static func screenDescription(from elements: [HeistElement]) -> String {
        let screenName = screenTitle(from: elements)

        var textFields = 0
        var buttons = 0
        var switches = 0
        var sliders = 0
        var searchFields = 0
        var links = 0
        var secureFields = 0

        for element in elements {
            let traits = element.traits
            if traits.contains(.secureTextField) {
                secureFields += 1
            } else if traits.contains(.textEntry) {
                textFields += 1
            } else if traits.contains(.searchField) {
                searchFields += 1
            } else if traits.contains(.switchButton) {
                switches += 1
            } else if traits.contains(.adjustable) {
                sliders += 1
            } else if traits.contains(.link) {
                links += 1
            } else if traits.contains(.button) && !traits.contains(.backButton) {
                buttons += 1
            }
        }

        var parts: [String] = []
        if textFields > 0 { parts.append("\(textFields) text field\(textFields == 1 ? "" : "s")") }
        if secureFields > 0 { parts.append("\(secureFields) password field\(secureFields == 1 ? "" : "s")") }
        if searchFields > 0 { parts.append("\(searchFields) search field\(searchFields == 1 ? "" : "s")") }
        if buttons > 0 { parts.append("\(buttons) button\(buttons == 1 ? "" : "s")") }
        if switches > 0 { parts.append("\(switches) toggle\(switches == 1 ? "" : "s")") }
        if sliders > 0 { parts.append("\(sliders) slider\(sliders == 1 ? "" : "s")") }
        if links > 0 { parts.append("\(links) link\(links == 1 ? "" : "s")") }

        let summary = parts.joined(separator: ", ")

        if let name = screenName, !summary.isEmpty {
            return "\(name) — \(summary)"
        } else if let name = screenName {
            return name
        } else if !summary.isEmpty {
            return summary
        } else {
            return "\(elements.count) elements"
        }
    }

    static func screenTitle(from elements: [HeistElement]) -> String? {
        elements
            .enumerated()
            .compactMap { index, element -> (index: Int, element: HeistElement)? in
                guard element.traits.contains(.header), element.label != nil else { return nil }
                return (index, element)
            }
            .min { left, right in
                if left.element.frameY != right.element.frameY { return left.element.frameY < right.element.frameY }
                if left.element.frameX != right.element.frameX { return left.element.frameX < right.element.frameX }
                return left.index < right.index
            }?
            .element
            .label
    }
}
