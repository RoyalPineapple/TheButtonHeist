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

    @Argument(help: "Edit action: \(EditAction.allCases.map(\.rawValue).joined(separator: ", "))")
    var action: String

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    func validate() throws {
        guard EditAction(rawValue: action) != nil else {
            throw ValidationError("Unknown edit action: \(action). Valid: \(EditAction.allCases.map(\.rawValue).joined(separator: ", "))")
        }
    }

    @ButtonHeistActor
    mutating func run() async throws {
        let request: [String: Any] = [
            "command": TheFence.Command.editAction.rawValue,
            "action": action,
        ]

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Sending \(action)..."
        )
    }
}
