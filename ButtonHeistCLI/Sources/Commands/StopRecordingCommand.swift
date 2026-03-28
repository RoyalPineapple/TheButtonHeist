import ArgumentParser
import ButtonHeist

struct StopRecordingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop_recording",
        abstract: "Stop an in-progress screen recording"
    )

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .long, help: "Connection timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    func run() async throws {
        let config = EnvironmentConfig.resolve(deviceFilter: connection.device, token: connection.token)
        let connector = DeviceConnector(
            deviceFilter: config.deviceFilter, token: config.token, driverId: config.driverId,
            quiet: connection.quiet
        )
        try await connector.connect()
        defer { connector.disconnect() }

        if !connection.quiet { logStatus("Stopping recording...") }
        connector.send(.stopRecording)

        // Brief yield so the WebSocket frame flushes before we disconnect.
        try? await Task.sleep(nanoseconds: 50_000_000)

        if !connection.quiet { logStatus("Stop signal sent") }
    }
}
