import ArgumentParser
import ButtonHeist

struct SetPasteboardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set_pasteboard",
        abstract: "Write text to the general pasteboard",
        discussion: """
            Write text to the device's general pasteboard from within the app.
            Content written this way does not trigger the iOS "Allow Paste" dialog
            when subsequently read by the same app.

            Examples:
              buttonheist set_pasteboard --text "Hello, clipboard"
            """
    )

    @Option(name: .long, help: "Text to write to the pasteboard")
    var text: String

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    mutating func run() async throws {
        let connector = DeviceConnector(deviceFilter: connection.device, token: connection.token, quiet: connection.quiet)
        try await connector.connect()
        defer { connector.disconnect() }

        if !connection.quiet {
            logStatus("Writing to pasteboard...")
        }

        connector.send(.setPasteboard(SetPasteboardTarget(text: text)))
        let result = try await connector.waitForActionResult(timeout: 15)
        outputActionResult(result, format: output.format, quiet: connection.quiet, verb: "Set pasteboard")
    }
}
