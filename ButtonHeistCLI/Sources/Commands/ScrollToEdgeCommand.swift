import ArgumentParser
import ButtonHeist

struct ScrollToEdgeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll_to_edge",
        abstract: "Scroll to the edge of a scroll view",
        discussion: """
            Finds the nearest scroll view ancestor of the target element and
            scrolls it all the way to the specified edge.

            Examples:
              buttonheist scroll_to_edge --identifier "buttonheist.longList.item-5" --edge bottom
              buttonheist scroll_to_edge --index 3 --edge top
            """
    )

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .long, help: "Edge to scroll to: top, bottom, left, right")
    var edge: String

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        _ = try element.requireTarget()

        guard ScrollEdge(rawValue: edge.lowercased()) != nil else {
            throw ValidationError("Invalid edge '\(edge)'. Valid: top, bottom, left, right")
        }

        var request: [String: Any] = [
            "command": TheFence.Command.scrollToEdge.rawValue,
            "edge": edge.lowercased(),
            "timeout": timeout,
        ]
        element.applyTo(&request)

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Sending scroll_to_edge..."
        )
    }
}
