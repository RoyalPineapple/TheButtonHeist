import SwiftUI
import ButtonHeist

enum ElementStyling {
    /// Returns the color for an element based on its available actions
    static func color(for element: UIElement) -> Color {
        let actions = element.actions
        if actions.contains("increment") || actions.contains("decrement") { return .orange }
        if actions.contains("activate") { return .blue }
        return .gray
    }

    /// Returns the SF Symbol name for an element based on its available actions
    static func iconName(for element: UIElement) -> String {
        let actions = element.actions
        if actions.contains("increment") || actions.contains("decrement") { return "slider.horizontal.3" }
        if actions.contains("activate") { return "button.horizontal" }
        return "text.alignleft"
    }

    // MARK: - Container Styling

    /// Returns the SF Symbol name for a container type
    static func iconName(forContainerType type: String) -> String {
        switch type {
        case "list": return "list.bullet"
        case "landmark": return "signpost.right"
        case "dataTable": return "tablecells"
        case "tabBar": return "menubar.rectangle"
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
        case "tabBar": return .purple
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
        case "tabBar": return "Tab Bar"
        case "semanticGroup": return "Group"
        case "none": return "Container"
        default: return "Container"
        }
    }
}
