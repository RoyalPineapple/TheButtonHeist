import ArgumentParser
import ButtonHeist

struct ScrollToVisibleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll_to_visible",
        abstract: "Scroll until a target element is visible",
        discussion: """
            Finds the nearest scroll view ancestor and adjusts its content offset
            so the target element's accessibility frame is fully within the viewport.

            Examples:
              buttonheist scroll_to_visible --identifier "buttonheist.longList.last"
              buttonheist scroll_to_visible --index 42
            """
    )

    @OptionGroup var element: ElementTargetOptions
    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        let target = try element.requireTarget()

        let connector = DeviceConnector(deviceFilter: connection.device, token: connection.token, quiet: connection.quiet)
        try await connector.connect()
        defer { connector.disconnect() }
        let client = connector.client

        let message = ClientMessage.scrollToVisible(target)

        if !connection.quiet {
            logStatus("Sending scroll_to_visible...")
        }

        client.send(message)

        let result = try await client.waitForActionResult(timeout: timeout)
        outputActionResult(result, format: output.format, quiet: connection.quiet, verb: "Scroll to visible")
    }
}
