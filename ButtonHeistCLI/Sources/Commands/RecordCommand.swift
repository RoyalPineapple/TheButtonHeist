import ArgumentParser
import Foundation
import ButtonHeist

struct RecordCommand: AsyncParsableCommand, CLICommandContract {
    static let fenceCommand = TheFence.Command.startRecording

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
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

    @Option(name: .long, help: "Save interaction log as JSON to this path")
    var actionLog: String?

    func validate() throws {
        guard fps >= 1 && fps <= 15 else {
            throw ValidationError("fps must be between 1 and 15, got \(fps)")
        }
        if let scale {
            guard scale >= 0.25 && scale <= 1.0 else {
                throw ValidationError("scale must be between 0.25 and 1.0, got \(scale)")
            }
        }
    }

    @ButtonHeistActor
    func run() async throws {
        let fence = try await CLIRunner.connect(
            connection: connection,
            statusMessage: "Starting recording..."
        )
        defer { fence.stop() }

        let config = RecordingConfig(
            fps: fps,
            scale: scale,
            inactivityTimeout: inactivityTimeout,
            maxDuration: maxDuration
        )

        // recordToCompletion owns start+wait+cleanup atomically: a Ctrl-C
        // (CancellationError) propagates a stop_recording to the iOS device,
        // so the recording never strands without a drainer.
        let payload = try await fence.recordToCompletion(
            config: config,
            timeout: maxDuration + 30
        )

        guard let videoData = Data(base64Encoded: payload.videoData) else {
            throw ValidationError("Failed to decode video data")
        }
        let url = URL(fileURLWithPath: output)
        try videoData.write(to: url)
        saveActionLog(payload: payload)
        if !connection.quiet {
            logRecordingStats(path: output, payload: payload)
        }
    }

    private func saveActionLog(payload: RecordingPayload) {
        guard let actionLogPath = actionLog,
              let log = payload.interactionLog, !log.isEmpty else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let logData = try encoder.encode(log)
            try logData.write(to: URL(fileURLWithPath: actionLogPath))
            if !connection.quiet {
                logStatus("  Action log saved: \(actionLogPath) (\(log.count) events)")
            }
        } catch {
            logStatus("  Failed to save action log: \(error.displayMessage)")
        }
    }

    private func logRecordingStats(path: String, payload: RecordingPayload) {
        let interactions = payload.interactionLog.map { ", interactions: \($0.count)" } ?? ""
        let duration = String(format: "%.1f", payload.duration)
        let resolution = "\(payload.width)x\(payload.height)"
        let stop = payload.stopReason.rawValue
        logStatus(
            "Recording saved: \(path) (duration: \(duration)s, frames: \(payload.frameCount), resolution: \(resolution), stop: \(stop)\(interactions))"
        )
    }
}
