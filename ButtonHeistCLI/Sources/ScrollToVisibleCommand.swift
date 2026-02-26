import ArgumentParser
import Foundation
import Darwin
import ButtonHeist

struct ScrollToVisibleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll-to-visible",
        abstract: "Scroll until a target element is visible",
        discussion: """
            Finds the nearest scroll view ancestor and adjusts its content offset
            so the target element's accessibility frame is fully within the viewport.

            Examples:
              buttonheist scroll-to-visible --identifier "buttonheist.longList.last"
              buttonheist scroll-to-visible --index 42
            """
    )

    @Option(name: .long, help: "Element identifier")
    var identifier: String?

    @Option(name: .long, help: "Element index")
    var index: Int?

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @MainActor
    mutating func run() async throws {
        guard identifier != nil || index != nil else {
            throw ValidationError("Must specify --identifier or --index")
        }

        let connector = DeviceConnector(deviceFilter: connection.device, token: connection.token, quiet: connection.quiet, force: connection.force)
        try await connector.connect()
        defer { connector.disconnect() }
        let client = connector.client

        let target = ActionTarget(identifier: identifier, order: index)
        let message = ClientMessage.scrollToVisible(target)

        if !connection.quiet {
            logStatus("Sending scroll_to_visible...")
        }

        client.send(message)

        let result = try await client.waitForActionResult(timeout: timeout)
        outputActionResult(result, format: format, quiet: connection.quiet, verb: "Scroll to visible")
    }
}
