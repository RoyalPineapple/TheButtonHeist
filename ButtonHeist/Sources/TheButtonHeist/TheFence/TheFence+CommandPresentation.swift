import Foundation

extension TheFence.Command {
    static func presentationDescription(for toolName: String) -> String {
        observationPresentationDescription(for: toolName) ??
            interactionPresentationDescription(for: toolName) ??
            sessionPresentationDescription(for: toolName) ??
            "Descriptor metadata for \(toolName) is missing a public description."
    }
}
