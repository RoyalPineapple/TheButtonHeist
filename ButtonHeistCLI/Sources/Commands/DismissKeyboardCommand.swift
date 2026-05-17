import ArgumentParser
import ButtonHeist

struct DismissKeyboardCommand: AsyncParsableCommand, CLICommandContract {
    static let fenceCommand = TheFence.Command.dismissKeyboard

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Dismiss the software keyboard by resigning first responder"
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    mutating func run() async throws {
        let request = Self.fenceRequest()
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Dismissing keyboard..."
        )
    }
}
