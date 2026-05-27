import ArgumentParser
import ButtonHeist

struct ScrollToVisibleCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Scroll a resolved element into view",
        discussion: """
            Resolves a semantic element target and brings it into view. \
            Target with a heistId or matcher fields such as label, identifier, value, \
            traits, excludeTraits, or ordinal.

            Examples:
              buttonheist scroll_to_visible btn_last
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
        _ = try element.requireTarget()

        var request = Self.fenceRequest([.timeout: .double(timeout)])
        try element.applyTo(&request)

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Scrolling to element..."
        )
    }
}
