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

    @Option(name: .long, help: "Connection timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

    @Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @MainActor
    func run() async throws {
        let connector = DeviceConnector(deviceFilter: device, quiet: quiet)
        try await connector.connect()
        defer { connector.disconnect() }
        let client = connector.client

        if !quiet {
            logStatus("Requesting screenshot...")
        }

        client.send(.requestScreen)

        let payload = try await client.waitForScreen(timeout: timeout)

        guard let pngData = Data(base64Encoded: payload.pngData) else {
            throw ValidationError("Failed to decode screenshot data")
        }

        if let outputPath = output {
            let url = URL(fileURLWithPath: outputPath)
            try pngData.write(to: url)
            if !quiet {
                logStatus("Screenshot saved to: \(outputPath)")
            }
        } else {
            // Write raw PNG to stdout for piping
            FileHandle.standardOutput.write(pngData)
        }
    }
}
