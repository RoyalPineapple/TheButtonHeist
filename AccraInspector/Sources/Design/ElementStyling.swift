import SwiftUI
import AccraCore

enum ElementStyling {
    /// Returns the color for an element based on its traits
    static func color(for element: AccessibilityElementData) -> Color {
        let traits = element.traits
        if traits.contains("button") { return .blue }
        if traits.contains("link") { return .purple }
        if traits.contains("textField") || traits.contains("searchField") { return .green }
        if traits.contains("adjustable") { return .orange }
        if traits.contains("staticText") { return .gray }
        if traits.contains("image") { return .pink }
        if traits.contains("header") { return .red }
        return .cyan
    }

    /// Returns the SF Symbol name for an element based on its traits
    static func iconName(for element: AccessibilityElementData) -> String {
        let traits = element.traits
        if traits.contains("button") { return "button.horizontal" }
        if traits.contains("link") { return "link" }
        if traits.contains("textField") { return "character.cursor.ibeam" }
        if traits.contains("searchField") { return "magnifyingglass" }
        if traits.contains("adjustable") { return "slider.horizontal.3" }
        if traits.contains("staticText") { return "text.alignleft" }
        if traits.contains("image") { return "photo" }
        if traits.contains("header") { return "text.badge.star" }
        if traits.contains("tabBar") { return "menubar.rectangle" }
        if traits.contains("selected") { return "checkmark.circle.fill" }
        return "square.dashed"
    }

    // MARK: - Container Styling

    /// Returns the SF Symbol name for a container type
    static func iconName(forContainerType type: String) -> String {
        switch type {
        case "list": return "list.bullet"
        case "landmark": return "signpost.right"
        case "dataTable": return "tablecells"
        case "semanticGroup": return "square.stack"
        case "none": return "folder"
        default: return "folder"
        }
    }

    /// Returns the color for a container type
    static func color(forContainerType type: String) -> Color {
        switch type {
        case "list": return .indigo
        case "landmark": return .teal
        case "dataTable": return .mint
        case "semanticGroup": return .brown
        default: return .secondary
        }
    }

    /// Returns a display label for a container type
    static func displayName(forContainerType type: String) -> String {
        switch type {
        case "list": return "List"
        case "landmark": return "Landmark"
        case "dataTable": return "Table"
        case "semanticGroup": return "Group"
        case "none": return "Container"
        default: return "Container"
        }
    }
}
