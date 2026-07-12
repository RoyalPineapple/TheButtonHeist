import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist

struct GetAnnouncementsCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Read recent accessibility announcements",
        discussion: """
            Read recent spoken accessibility text captured from announcement,
            elementChanged, or screenChanged notifications.

            Examples:
              buttonheist get_announcements
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
            statusMessage: "Reading announcements..."
        )
    }
}
