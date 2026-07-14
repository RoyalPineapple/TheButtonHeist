import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist

struct DismissKeyboardCommand: ConnectedOneShotCLICommand {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Dismiss the software keyboard by resigning first responder"
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    var runnerStatusMessage: String? { "Dismissing keyboard..." }
}
