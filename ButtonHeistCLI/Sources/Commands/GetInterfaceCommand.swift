import ArgumentParser
import Foundation
import ButtonHeist

struct GetInterfaceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get_interface",
        abstract: "Get the current UI element hierarchy from the connected device"
    )

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        let config = EnvironmentConfig.resolve(deviceFilter: connection.device, token: connection.token)
        let connector = DeviceConnector(deviceFilter: config.deviceFilter, token: config.token, driverId: config.driverId, quiet: connection.quiet)
        try await connector.connect()
        defer { connector.disconnect() }

        if !connection.quiet {
            logStatus("Requesting interface...")
        }

        connector.requestInterface()
        let interface = try await connector.waitForInterface(timeout: timeout)

        switch format ?? .auto {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(interface)
            writeOutput(String(data: data, encoding: .utf8) ?? "{}")
        case .compact:
            writeOutput(FenceResponse.compactInterface(interface))
        case .human:
            writeOutput("Elements (\(interface.elements.count)):")
            for element in interface.elements {
                var parts: [String] = ["[\(element.order)]"]
                if let label = element.label { parts.append(label) }
                if let identifier = element.identifier { parts.append("id:\(identifier)") }
                if let value = element.value { parts.append("value:\(value)") }
                parts.append("(\(element.traits.joined(separator: ", ")))")
                writeOutput("  " + parts.joined(separator: "  "))
            }
        }
    }
}
