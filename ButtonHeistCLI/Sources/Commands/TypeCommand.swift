import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist

struct TypeCommand: AsyncParsableCommand, CLICommandContract {
    private static let defaultTimeout: Double = {
        guard let seconds = TheFence.Command.typeText.descriptor.timeout.singleStepBaseSeconds else {
            preconditionFailure("type_text descriptor must expose a single-step action timeout")
        }
        return seconds
    }()

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Type text into a field by tapping keyboard keys",
        discussion: """
            Type non-empty text character-by-character.
            Returns the current text field value after the operation.

            Examples:
              buttonheist type_text --text "Hello"
              buttonheist type_text --text "Hello" --identifier "nameField"
            """
    )

    @Option(name: .long, help: "Text to type")
    var text: String

    @OptionGroup var element: ElementTargetOptions
    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds (default: \(Int(TypeCommand.defaultTimeout)))")
    var timeout: Double = TypeCommand.defaultTimeout

    func validate() throws {
        if text.isEmpty {
            throw ValidationError("text must be non-empty")
        }
    }

    @ButtonHeistActor
    mutating func run() async throws {
        let target = try element.parsedTarget()

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: Self.fenceCommand,
            arguments: Self.fenceArguments(
                target: target,
                CommandArgumentWriter.value(.timeout, timeout),
                CommandArgumentWriter.value(.text, text)
            ),
            statusMessage: "Sending type command..."
        )
    }
}
