import ArgumentParser
import ButtonHeist

struct ScrollToEdgeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll_to_edge",
        abstract: "Scroll to the edge of a scroll view",
        discussion: """
            Finds the nearest scroll view ancestor of the target element and
            scrolls it all the way to the specified edge. Defaults to bottom.

            Examples:
              buttonheist scroll_to_edge btn_list
              buttonheist scroll_to_edge btn_list -e top
              buttonheist scroll_to_edge -id "longList" -e left
            """
    )

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .shortAndLong, help: "Edge to scroll to: top, bottom, left, right (default: bottom)")
    var edge: String = "bottom"

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions
    @OptionGroup var timeoutOption: TimeoutOption

    @ButtonHeistActor
    mutating func run() async throws {
        _ = try element.requireTarget()

        guard ScrollEdge(rawValue: edge.lowercased()) != nil else {
            throw ValidationError("Invalid edge '\(edge)'. Valid: \(ScrollEdge.allCases.map(\.rawValue).joined(separator: ", "))")
        }

        var request: [String: Any] = [
            "command": TheFence.Command.scrollToEdge.rawValue,
            "edge": edge.lowercased(),
            "timeout": timeoutOption.timeout,
        ]
        try element.applyTo(&request)

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Sending scroll_to_edge..."
        )
    }
}
