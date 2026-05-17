import ArgumentParser
import ButtonHeist

struct StopRecordingCommand: AsyncParsableCommand, CLICommandContract {
    static let fenceCommand = TheFence.Command.stopRecording

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Stop an in-progress screen recording"
    )

    @OptionGroup var connection: ConnectionOptions

    @ButtonHeistActor
    func run() async throws {
        let request = Self.fenceRequest()

        try await CLIRunner.run(
            connection: connection,
            format: .human,
            request: request,
            statusMessage: "Stopping recording..."
        )
    }
}
