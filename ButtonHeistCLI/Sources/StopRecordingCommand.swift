import ArgumentParser
import Foundation
import ButtonHeist
import TheGoods

struct StopRecordingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop-recording",
        abstract: "Stop an in-progress screen recording"
    )

    @Option(name: .long, help: "Connection timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

    @Option(name: .long, help: "Target device by name, ID prefix, or index")
    var device: String?

    @MainActor
    func run() async throws {
        let connector = DeviceConnector(deviceFilter: device, quiet: quiet)
        try await connector.connect()
        defer { connector.disconnect() }
        let client = connector.client

        if !quiet { logStatus("Stopping recording...") }
        client.send(.stopRecording)

        // Wait briefly for the server to acknowledge — the recording payload
        // is broadcast to all clients, so the original `record` process
        // (running in background) receives it and writes the file.
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        if !quiet { logStatus("Stop signal sent") }
    }
}
