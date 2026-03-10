import ArgumentParser
import ButtonHeist

struct ScrollToEdgeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll-to-edge",
        abstract: "Scroll to the edge of a scroll view",
        discussion: """
            Finds the nearest scroll view ancestor of the target element and
            scrolls it all the way to the specified edge.

            Examples:
              buttonheist scroll-to-edge --identifier "buttonheist.longList.item-5" --edge bottom
              buttonheist scroll-to-edge --index 3 --edge top
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
        let target = try element.requireTarget()

        guard let scrollEdge = ScrollEdge(rawValue: edge.lowercased()) else {
            throw ValidationError("Invalid edge '\(edge)'. Valid: top, bottom, left, right")
        }

        let connector = DeviceConnector(deviceFilter: connection.device, token: connection.token, quiet: connection.quiet)
        try await connector.connect()
        defer { connector.disconnect() }
        let client = connector.client

        let message = ClientMessage.scrollToEdge(ScrollToEdgeTarget(elementTarget: target, edge: scrollEdge))

        if !connection.quiet {
            logStatus("Sending scroll_to_edge...")
        }

        client.send(message)

        let result = try await client.waitForActionResult(timeout: timeout)
        outputActionResult(result, format: output.format, quiet: connection.quiet, verb: "Scroll to edge")
    }
}
