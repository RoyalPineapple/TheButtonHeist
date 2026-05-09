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

        // stop_recording via TheFence sends the stop signal and waits for the
        // recording payload. Since we have no output path, it returns .recordingData.
        // For the standalone stop command, we just need to confirm the stop was sent.
        try await CLIRunner.run(
            connection: connection,
            format: .human,
            request: request,
            statusMessage: "Stopping recording..."
        )
    }
}
