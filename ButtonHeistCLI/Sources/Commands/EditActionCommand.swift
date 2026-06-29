import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist

struct EditActionCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Perform an edit menu action on the current first responder",
        discussion: """
            Triggers copy, paste, cut, select, selectAll, or delete on the element \
            that currently has focus.

            Examples:
              buttonheist edit_action --action copy
              buttonheist edit_action --action paste
              buttonheist edit_action --action delete
              buttonheist edit_action --action selectAll
            """
    )

    @Option(name: .long, help: "Edit action: \(Self.catalogAllowedValuesDescription(for: .action))")
    var action: String

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    func validate() throws {
        _ = try Self.canonicalAction(action)
    }

    @ButtonHeistActor
    mutating func run() async throws {
        let editAction = try Self.canonicalAction(action)
        var request = CLIRequestParameters()
        request.set(.action, editAction)

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: Self.fenceCommand,
            arguments: Self.fenceArguments(request),
            statusMessage: "Sending \(action)..."
        )
    }

    private static func canonicalAction(_ action: String) throws -> String {
        guard let editAction = Self.catalogCanonicalStringValue(action, for: .action) else {
            throw ValidationError("Unknown edit action: \(action). Valid: \(Self.catalogAllowedValuesDescription(for: .action))")
        }
        return editAction
    }
}
