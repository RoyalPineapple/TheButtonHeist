import ArgumentParser
import ButtonHeist

struct EditActionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit_action",
        abstract: "Perform an edit menu action on the current first responder",
        discussion: """
            Triggers copy, paste, cut, select, or selectAll on the element \
            that currently has focus.

            Examples:
              buttonheist edit_action copy
              buttonheist edit_action paste
              buttonheist edit_action selectAll
            """
    )

    @Argument(help: "Edit action: copy, paste, cut, select, selectAll")
    var action: String

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    func validate() throws {
        let normalized = action.lowercased().replacingOccurrences(of: "_", with: "")
        guard EditAction.allCases.contains(where: {
            $0.rawValue.lowercased().replacingOccurrences(of: "_", with: "") == normalized
        }) else {
            throw ValidationError("Unknown edit action: \(action). Valid: copy, paste, cut, select, selectAll")
        }
    }

    @ButtonHeistActor
    mutating func run() async throws {
        let normalized = action.lowercased().replacingOccurrences(of: "_", with: "")
        guard let editAction = EditAction.allCases.first(where: {
            $0.rawValue.lowercased().replacingOccurrences(of: "_", with: "") == normalized
        }) else {
            throw ValidationError("Unknown edit action: \(action)")
        }

        let request: [String: Any] = [
            "command": TheFence.Command.editAction.rawValue,
            "action": editAction.rawValue,
        ]

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Sending \(editAction.rawValue)..."
        )
    }
}
