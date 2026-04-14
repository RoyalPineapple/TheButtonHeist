import ArgumentParser
import ButtonHeist

struct DismissKeyboardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dismiss_keyboard",
        abstract: "Dismiss the software keyboard by resigning first responder"
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    mutating func run() async throws {
        let request: [String: Any] = [
            "command": TheFence.Command.dismissKeyboard.rawValue,
        ]
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Dismissing keyboard..."
        )
    }
}
