import ArgumentParser
import ButtonHeist

struct DismissKeyboardCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Dismiss the software keyboard by resigning first responder"
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    mutating func run() async throws {
        let request: CLIRequestParameters = [:]
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            operation: try Self.fenceOperation(request),
            statusMessage: "Dismissing keyboard..."
        )
    }
}
