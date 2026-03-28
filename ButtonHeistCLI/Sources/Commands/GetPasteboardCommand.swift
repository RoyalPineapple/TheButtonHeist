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
        let config = EnvironmentConfig.resolve(deviceFilter: connection.device, token: connection.token)
        let connector = DeviceConnector(deviceFilter: config.deviceFilter, token: config.token, driverId: config.driverId, quiet: connection.quiet)
        try await connector.connect()
        defer { connector.disconnect() }

        if !connection.quiet {
            logStatus("Reading pasteboard...")
        }

        connector.send(.getPasteboard)
        let result = try await connector.waitForActionResult(timeout: 15)
        outputActionResult(result, format: output.format, quiet: connection.quiet, verb: "Get pasteboard")
    }
}
