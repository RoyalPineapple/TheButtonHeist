import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist

struct ScrollToVisibleCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Scroll a resolved element into view",
        discussion: """
            Resolves a semantic element target and brings it into view. \
            Target with matcher fields such as label, identifier, value, \
            traits, or excludeTraits. Ordinal only disambiguates a matcher.

            Examples:
              buttonheist scroll_to_visible -l "Last Item"
              buttonheist scroll_to_visible -l "Color Picker"
            """
    )

    @OptionGroup var element: ElementTargetOptions
    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 15.0

    @ButtonHeistActor
    mutating func run() async throws {
        let target = try element.requireTarget()

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: Self.fenceCommand,
            arguments: Self.fenceArguments(
                target: target,
                CommandArgumentWriter.value(.timeout, timeout)
            ),
            statusMessage: "Scrolling to element..."
        )
    }
}
