import ArgumentParser
import ButtonHeist

struct ScrollToVisibleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll_to_visible",
        abstract: "Scroll a known element into view (one-shot)",
        discussion: """
            Jumps directly to a known element's position in its scroll view. \
            The element must already be in the registry (seen in a previous \
            get_interface or action delta). If the element has never been seen, \
            use element_search instead.

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

        var request: [String: Any] = [
            "command": TheFence.Command.scrollToVisible.rawValue,
            "timeout": timeout,
        ]
        try element.applyTo(&request)

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Scrolling to element..."
        )
    }
}
