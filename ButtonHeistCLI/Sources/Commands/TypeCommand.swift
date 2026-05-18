import ArgumentParser
import ButtonHeist

struct TypeCommand: AsyncParsableCommand, CLICommandContract {
    static let fenceCommand = TheFence.Command.typeText

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Type text into a field by tapping keyboard keys",
        discussion: """
            Type non-empty text character-by-character.
            Returns the current text field value after the operation.

            A single positional argument is always interpreted as text, not \
            as a heistId. Use -id or --heist-id to target a specific field.

            Examples:
              buttonheist type_text "Hello" btn_nameField
              buttonheist type_text "Hello"
              buttonheist type_text "Hello" -id "nameField"
            """
    )

    @Argument(help: "Text to type")
    var text: String

    @OptionGroup var element: ElementTargetOptions
    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 30.0

    func validate() throws {
        if text.isEmpty {
            throw ValidationError("text must be non-empty")
        }
    }

    @ButtonHeistActor
    mutating func run() async throws {
        var request = Self.fenceRequest(["timeout": timeout])
        request["text"] = text
        try element.applyTo(&request)

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Sending type command..."
        )
    }
}
