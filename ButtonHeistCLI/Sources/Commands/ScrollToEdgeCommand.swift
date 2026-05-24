import ArgumentParser
import ButtonHeist

struct ScrollToEdgeCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Scroll to the edge of a scroll view",
        discussion: """
            Scrolls an explicit or primary scroll view all the way to the
            specified edge. Defaults to top.

            Examples:
              buttonheist scroll_to_edge
              buttonheist scroll_to_edge btn_list
              buttonheist scroll_to_edge btn_list -e top
              buttonheist scroll_to_edge --stable-id "main_scroll" -e left
              buttonheist scroll_to_edge -id "longList" -e left
            """
    )

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .customLong("stable-id"), help: "Scrollable container stableId from get_interface")
    var stableId: String?

    @Option(name: .shortAndLong, help: "Edge to scroll to: top, bottom, left, right (default: top)")
    var edge: String = Self.catalogDefaultString(for: .edge)

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions
    @OptionGroup var timeoutOption: TimeoutOption

    @ButtonHeistActor
    mutating func run() async throws {
        guard let scrollEdge = ScrollEdge(rawValue: edge.lowercased()) else {
            throw ValidationError("Invalid edge '\(edge)'. Valid: \(ScrollEdge.allCases.map(\.rawValue).joined(separator: ", "))")
        }

        var request = Self.fenceRequest([
            .edge: .string(scrollEdge.rawValue),
            .timeout: .double(timeoutOption.timeout),
        ])
        if let stableId { request.set(.stableId, stableId) }
        try element.applyTo(&request)

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Sending scroll_to_edge..."
        )
    }
}
