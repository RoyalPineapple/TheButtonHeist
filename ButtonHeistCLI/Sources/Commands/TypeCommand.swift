import ArgumentParser
import ButtonHeist

struct TypeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type_text",
        abstract: "Type text into a field by tapping keyboard keys",
        discussion: """
            Type text character-by-character and/or delete characters.
            Returns the current text field value after the operation.

            A single positional argument is always interpreted as text, not \
            as a heistId. Use -id or --heist-id to target without typing.

            Examples:
              buttonheist type_text "Hello" btn_nameField
              buttonheist type_text "Hello"
              buttonheist type_text --delete 3 -id "nameField"
              buttonheist type_text --delete 4 "orld" -id "nameField"
            """
    )

    @Argument(help: "Text to type")
    var text: String?

    @Option(name: .long, help: "Number of characters to delete before typing")
    var delete: Int?

    @OptionGroup var element: ElementTargetOptions
    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 30.0

    @ButtonHeistActor
    mutating func run() async throws {
        guard text != nil || delete != nil else {
            throw ValidationError("Must specify text to type, --delete, or both")
        }

        var request: [String: Any] = [
            "command": TheFence.Command.typeText.rawValue,
            "timeout": timeout,
        ]
        if let text { request["text"] = text }
        if let delete { request["deleteCount"] = delete }
        try element.applyTo(&request)

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Sending type command..."
        )
    }
}
