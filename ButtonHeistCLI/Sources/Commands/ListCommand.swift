import ArgumentParser
import Foundation
import ButtonHeist

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: TheFence.Command.listDevices.rawValue,
        abstract: "List available iOS apps with Button Heist enabled"
    )

    @Option(name: .shortAndLong, help: "Discovery timeout in seconds")
    var timeout: Double = 3.0

    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    mutating func run() async throws {
        // list_devices doesn't require a connection — TheFence skips auto-connect
        // for this command, so we call execute() without start().
        let config = EnvironmentConfig.resolve()
        let fence = TheFence(configuration: config.fenceConfiguration)
        defer { fence.stop() }

        logStatus("Discovering devices...")
        let request: [String: Any] = [
            "command": TheFence.Command.listDevices.rawValue,
        ]
        let response = try await fence.execute(request: request)
        CLIRunner.outputResponse(response, format: output.format ?? .auto)
    }
}
