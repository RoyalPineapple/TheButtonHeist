import ArgumentParser
import Foundation
@_spi(ButtonHeistTooling) import ButtonHeist

struct ListCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "List available iOS apps with Button Heist enabled"
    )

    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    mutating func run() async throws {
        // list_devices doesn't require a connection — TheFence skips auto-connect
        // for this command, so we call execute() without start().
        let config = try EnvironmentConfig.resolve()
        let fence = TheFence(configuration: config.fenceConfiguration)
        defer { fence.stop() }

        logStatus("Discovering devices...")
        let response = try await fence.execute(try fence.admit(
            command: Self.fenceCommand,
            arguments: Self.fenceArguments()
        ))
        CLIRunner.outputResponse(response, format: output.format ?? .auto)
    }
}
