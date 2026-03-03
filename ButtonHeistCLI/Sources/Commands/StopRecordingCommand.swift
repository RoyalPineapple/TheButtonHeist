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

        // Brief yield so the WebSocket frame flushes before we disconnect.
        try? await Task.sleep(nanoseconds: 50_000_000)

        if !connection.quiet { logStatus("Stop signal sent") }
    }
}
