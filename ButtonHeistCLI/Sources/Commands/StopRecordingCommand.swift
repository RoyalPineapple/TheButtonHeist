import ArgumentParser
import ButtonHeist

struct StopRecordingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop_recording",
        abstract: "Stop an in-progress screen recording"
    )

    @OptionGroup var connection: ConnectionOptions

    @ButtonHeistActor
    func run() async throws {
        let request: [String: Any] = [
            "command": TheFence.Command.stopRecording.rawValue,
        ]

        try await CLIRunner.run(
            connection: connection,
            format: .human,
            request: request,
            statusMessage: "Stopping recording..."
        )
    }
}
