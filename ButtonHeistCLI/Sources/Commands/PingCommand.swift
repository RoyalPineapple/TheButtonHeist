import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist

struct PingCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Check Button Heist connection health",
        discussion: """
            Sends a lightweight health ping to the connected app and returns \
            cheap server/app identity metadata.

            Examples:
              buttonheist ping
              buttonheist ping --format json
            """
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    mutating func run() async throws {
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: Self.fenceCommand,
            arguments: Self.fenceArguments(),
            statusMessage: "Checking health..."
        )
    }
}
