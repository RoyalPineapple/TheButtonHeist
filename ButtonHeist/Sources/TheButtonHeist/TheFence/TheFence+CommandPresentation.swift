import Foundation

extension TheFence.Command {
    static func presentationDescription(for toolName: String) -> String {
        observationPresentationDescription(for: toolName) ??
            interactionPresentationDescription(for: toolName) ??
            sessionPresentationDescription(for: toolName) ??
            "Execute the \(toolName) Button Heist tool."
    }
}
