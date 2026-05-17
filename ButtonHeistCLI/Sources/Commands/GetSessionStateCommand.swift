import ArgumentParser
import ButtonHeist

struct GetSessionStateCommand: AsyncParsableCommand, CLICommandContract {
    static let fenceCommand = TheFence.Command.getSessionState

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Report the current connection + session state",
        discussion: """
            Returns connection status, connected device, recording state,
            configured timeouts, and the most recent action/latency. Useful
            in scripts that need to probe whether an agent is healthy before
            issuing commands.

            Examples:
              buttonheist get_session_state
              buttonheist get_session_state --format json
            """
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    mutating func run() async throws {
        let request = Self.fenceRequest()
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request
        )
    }
}
