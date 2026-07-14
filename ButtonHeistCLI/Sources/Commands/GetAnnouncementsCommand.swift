import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist

struct GetAnnouncementsCommand: ConnectedOneShotCLICommand {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Read recent accessibility announcements",
        discussion: """
            Read recent spoken accessibility text captured from announcement,
            elementChanged, or screenChanged notifications.

            Examples:
              buttonheist get_announcements
            """
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    var runnerStatusMessage: String? { "Reading announcements..." }
}
