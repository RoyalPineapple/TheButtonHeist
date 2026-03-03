import ArgumentParser
import Foundation
import ButtonHeist

struct StopRecordingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop-recording",
        abstract: "Stop an in-progress screen recording"
    )

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .long, help: "Connection timeout in seconds")
    var timeout: Double = 10.0

    @MainActor
    func run() async throws {
        let connector = DeviceConnector(
            deviceFilter: connection.device, token: connection.token,
            quiet: connection.quiet, force: connection.force
        )
        try await connector.connect()
        defer { connector.disconnect() }
        let client = connector.client

        if !connection.quiet { logStatus("Stopping recording...") }
        client.send(.stopRecording)

        // Wait briefly for the server to acknowledge — the recording payload
        // is broadcast to all clients, so the original `record` process
        // (running in background) receives it and writes the file.
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        if !connection.quiet { logStatus("Stop signal sent") }
    }
}
