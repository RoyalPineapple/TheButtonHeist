import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist

struct GetAnnouncementsCommand: ConnectedOneShotCLICommand {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Read the recent accessibility notification stream",
        discussion: """
            Read every captured announcement, elementChanged, valueChanged, and
            screenChanged notification — including events posted with no string
            payload, which carry no spoken text but are still real accessibility
            events. Spoken text is also projected separately.

            The response reports capture health, so an empty stream is
            distinguishable from a capture pipeline that failed to install or
            has nothing subscribed.

            Examples:
              buttonheist get_announcements
            """
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    var runnerStatusMessage: String? { "Reading announcements..." }
}
