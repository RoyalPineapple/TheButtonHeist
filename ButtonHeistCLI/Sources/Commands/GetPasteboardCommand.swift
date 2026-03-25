import ArgumentParser
import ButtonHeist

struct GetPasteboardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get_pasteboard",
        abstract: "Read text from the general pasteboard",
        discussion: """
            Read text from the device's general pasteboard.
            If the content was written by another app, iOS may show
            an "Allow Paste" system dialog.

            Examples:
              buttonheist get_pasteboard
            """
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    mutating func run() async throws {
        let connector = DeviceConnector(deviceFilter: connection.device, token: connection.token, quiet: connection.quiet)
        try await connector.connect()
        defer { connector.disconnect() }
        let client = connector.client

        if !connection.quiet {
            logStatus("Reading pasteboard...")
        }

        client.send(.getPasteboard)
        let result = try await client.waitForActionResult(timeout: 15)
        outputActionResult(result, format: output.format, quiet: connection.quiet, verb: "Get pasteboard")
    }
}
