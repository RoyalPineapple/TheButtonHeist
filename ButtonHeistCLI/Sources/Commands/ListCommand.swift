import ArgumentParser
import Foundation
import ButtonHeist

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available iOS devices running TheInsideJob"
    )

    @Option(name: .shortAndLong, help: "Discovery timeout in seconds")
    var timeout: Double = 3.0

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @ButtonHeistActor
    mutating func run() async throws {
        let client = TheMastermind()
        logStatus("Discovering devices...")
        let discovered = await client.discoverReachableDevices(timeout: timeout)

        if discovered.isEmpty {
            logStatus("No devices found.")
            return
        }

        switch format ?? .auto {
        case .json:
            outputJSON(discovered)
        case .human:
            outputHuman(discovered)
        }
    }

    private func outputJSON(_ devices: [DiscoveredDevice]) {
        struct DeviceInfo: Encodable {
            let name: String
            let appName: String
            let deviceName: String
            let connectionType: String
            let shortId: String?
            let simulatorUDID: String?
        }
        let infos = devices.map {
            DeviceInfo(name: $0.name, appName: $0.appName,
                       deviceName: $0.deviceName,
                       connectionType: $0.connectionType.rawValue,
                       shortId: $0.shortId,
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
            let typeLabel: String
            switch device.connectionType {
            case .simulator: typeLabel = "sim"
            case .usb: typeLabel = "usb"
            case .network: typeLabel = "network"
            }
            writeOutput("  [\(index)] \(id)  \(app)  (\(dev))  [\(typeLabel)]")
            if let udid = device.simulatorUDID {
                writeOutput("       Simulator: \(udid)")
            }
        }
        writeOutput("")
        writeOutput("Use --device <id|name|udid> to target a specific instance.")
    }
}
