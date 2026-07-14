import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist
import ThePlans

struct EditActionCommand: ConnectedOneShotCLICommand {
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

    @Option(name: .long, help: "Edit action: \(Self.catalogAllowedValuesDescription(for: FenceParameters.editAction))")
    var action: String

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    func validate() throws {
        _ = try Self.canonicalAction(action)
    }

    var runnerStatusMessage: String? { "Sending \(action)..." }

    func requestArguments() throws -> TheFence.CommandArgumentEnvelope {
        let editAction = try Self.canonicalAction(action)
        return Self.fenceArguments(
            CommandArgumentEnvelopeBuilder.value(FenceParameters.editAction, editAction)
        )
    }

    private static func canonicalAction(_ action: String) throws -> EditAction {
        guard let editAction = Self.catalogCanonicalValue(action, for: FenceParameters.editAction) else {
            throw ValidationError("Unknown edit action: \(action). Valid: \(Self.catalogAllowedValuesDescription(for: FenceParameters.editAction))")
        }
        return editAction
    }
}
