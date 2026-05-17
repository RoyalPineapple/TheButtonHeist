import ArgumentParser
import ButtonHeist

struct ScrollToVisibleCommand: AsyncParsableCommand, CLICommandContract {
    static let fenceCommand = TheFence.Command.scrollToVisible

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Scroll a known element into view",
        discussion: """
            Brings an element from the current hierarchy into view. \
            The element must have been returned by get_interface or an action delta. \
            If the element has not been seen yet, use element_search instead.

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

        var request = Self.fenceRequest(["timeout": timeout])
        try element.applyTo(&request)

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Scrolling to element..."
        )
    }
}
