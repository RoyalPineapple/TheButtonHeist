import ArgumentParser
import Foundation
import ButtonHeist

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available iOS devices running InsideJob"
    )

    @Option(name: .shortAndLong, help: "Discovery timeout in seconds")
    var timeout: Double = 3.0

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @MainActor
    mutating func run() async throws {
        let client = TheMastermind()
        logStatus("Discovering devices...")
        client.startDiscovery()

        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

        client.stopDiscovery()

        let devices = client.discoveredDevices

        if devices.isEmpty {
            logStatus("No devices found.")
            return
        }

        switch format ?? .auto {
        case .json:
            outputJSON(devices)
        case .human:
            outputHuman(devices)
        }
    }

    private func outputJSON(_ devices: [DiscoveredDevice]) {
        struct DeviceInfo: Encodable {
            let name: String
            let appName: String
            let deviceName: String
            let shortId: String?
            let simulatorUDID: String?
        }
        let infos = devices.map {
            DeviceInfo(name: $0.name, appName: $0.appName,
                       deviceName: $0.deviceName, shortId: $0.shortId,
                       simulatorUDID: $0.simulatorUDID)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(infos),
           let json = String(data: data, encoding: .utf8) {
            writeOutput(json)
        }
    }

    private func outputHuman(_ devices: [DiscoveredDevice]) {
        writeOutput("Found \(devices.count) device(s):\n")
        for (index, device) in devices.enumerated() {
            let id = device.shortId ?? "----"
            let app = device.appName
            let dev = device.deviceName
            writeOutput("  [\(index)] \(id)  \(app)  (\(dev))")
            if let udid = device.simulatorUDID {
                writeOutput("       Simulator: \(udid)")
            }
        }
        writeOutput("")
        writeOutput("Use --device <id|name|udid> to target a specific instance.")
    }
}
