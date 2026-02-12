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

    @MainActor
    func run() async throws {
        let client = HeistClient()

        if !quiet {
            FileHandle.standardError.write(Data("Searching for iOS devices...\n".utf8))
        }

        client.startDiscovery()

        // Wait for device discovery
        var waitTime = 0.0
        while client.discoveredDevices.isEmpty && waitTime < 5.0 {
            try await Task.sleep(nanoseconds: 100_000_000)
            waitTime += 0.1
        }

        guard let device = client.discoveredDevices.first else {
            throw ValidationError("No devices found within timeout")
        }

        if !quiet {
            FileHandle.standardError.write(Data("Found device: \(device.name)\n".utf8))
            FileHandle.standardError.write(Data("Connecting...\n".utf8))
        }

        var connected = false
        client.onConnected = { _ in connected = true }
        client.connect(to: device)

        waitTime = 0.0
        while !connected && waitTime < 5.0 {
            try await Task.sleep(nanoseconds: 100_000_000)
            waitTime += 0.1
        }

        guard connected else {
            throw ValidationError("Connection timeout")
        }

        if !quiet {
            FileHandle.standardError.write(Data("Connected. Requesting screenshot...\n".utf8))
        }

        // Request screenshot
        client.send(.requestScreen)

        let payload = try await client.waitForScreen(timeout: timeout)

        guard let pngData = Data(base64Encoded: payload.pngData) else {
            throw ValidationError("Failed to decode screenshot data")
        }

        if let outputPath = output {
            let url = URL(fileURLWithPath: outputPath)
            try pngData.write(to: url)
            if !quiet {
                FileHandle.standardError.write(Data("Screenshot saved to: \(outputPath)\n".utf8))
            }
        } else {
            // Write raw PNG to stdout for piping
            FileHandle.standardOutput.write(pngData)
        }
    }
}
