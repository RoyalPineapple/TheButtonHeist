import ArgumentParser
import Foundation
import ButtonHeist

struct ScreenshotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Capture a screenshot from the connected device"
    )

    @Option(name: .shortAndLong, help: "Output file path (default: stdout as raw PNG)")
    var output: String?

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .long, help: "Connection timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    func run() async throws {
        let connector = DeviceConnector(deviceFilter: connection.device, token: connection.token, quiet: connection.quiet)
        try await connector.connect()
        defer { connector.disconnect() }

        if !connection.quiet {
            logStatus("Requesting screenshot...")
        }

        connector.send(.requestScreen)

        let payload = try await connector.waitForScreen(timeout: timeout)

        guard let pngData = Data(base64Encoded: payload.pngData) else {
            throw ValidationError("Failed to decode screenshot data")
        }

        if let outputPath = output {
            let url = URL(fileURLWithPath: outputPath)
            try pngData.write(to: url)
            if !connection.quiet {
                logStatus("Screenshot saved to: \(outputPath)")
            }
        } else {
            // Write raw PNG to stdout for piping
            FileHandle.standardOutput.write(pngData)
        }
    }
}
