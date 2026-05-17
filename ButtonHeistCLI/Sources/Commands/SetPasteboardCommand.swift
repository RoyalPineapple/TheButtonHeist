import ArgumentParser
import ButtonHeist

struct SetPasteboardCommand: AsyncParsableCommand, CLICommandContract {
    static let fenceCommand = TheFence.Command.setPasteboard

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
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
        let request = Self.fenceRequest(["text": text])
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Writing to pasteboard..."
        )
    }
}
