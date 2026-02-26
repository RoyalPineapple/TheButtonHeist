import ArgumentParser
import Foundation
import ButtonHeist

struct RecordCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "record",
        abstract: "Record the screen of the connected device"
    )

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .shortAndLong, help: "Output file path (default: recording.mp4)")
    var output: String = "recording.mp4"

    @Option(name: .long, help: "Frames per second (1-15, default: 8)")
    var fps: Int = 8

    @Option(name: .long, help: "Resolution scale of native pixels (0.25-1.0, default: 1x point size)")
    var scale: Double?

    @Option(name: .long, help: "Inactivity timeout in seconds (default: 5)")
    var inactivityTimeout: Double = 5.0

    @Option(name: .long, help: "Max recording duration in seconds (default: 60)")
    var maxDuration: Double = 60.0

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

        if !connection.quiet { logStatus("Starting recording...") }

        let config = RecordingConfig(
            fps: fps,
            scale: scale,
            inactivityTimeout: inactivityTimeout,
            maxDuration: maxDuration
        )
        client.send(.startRecording(config))

        let payload = try await client.waitForRecording(timeout: maxDuration + 30)

        guard let videoData = Data(base64Encoded: payload.videoData) else {
            throw ValidationError("Failed to decode video data")
        }

        let url = URL(fileURLWithPath: output)
        try videoData.write(to: url)

        if !connection.quiet {
            logStatus("Recording saved: \(output)")
            logStatus("  Duration: \(String(format: "%.1f", payload.duration))s")
            logStatus("  Frames: \(payload.frameCount)")
            logStatus("  Resolution: \(payload.width)x\(payload.height)")
            logStatus("  Size: \(videoData.count / 1024)KB")
            logStatus("  Stop reason: \(payload.stopReason.rawValue)")
        }
    }
}
