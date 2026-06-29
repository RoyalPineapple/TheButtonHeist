import ArgumentParser
import Foundation
@_spi(ButtonHeistTooling) import ButtonHeist

struct GetInterfaceCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Read the app accessibility hierarchy from the connected device"
    )

    @OptionGroup var connection: ConnectionOptions

    @OptionGroup var output: OutputOptions

    @OptionGroup var discoveryLimits: InterfaceDiscoveryLimitOptions

    @ButtonHeistActor
    mutating func run() async throws {
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: Self.fenceCommand,
            arguments: Self.fenceArguments(discoveryLimits.parameters),
            statusMessage: "Reading interface..."
        )
    }
}

struct InterfaceDiscoveryLimitOptions: ParsableArguments {
    @Option(name: .long, help: "Maximum page-scroll attempts per scroll container during interface discovery.")
    var maxScrollsPerContainer: Int?

    @Option(name: .long, help: "Maximum total page-scroll attempts during interface discovery.")
    var maxScrollsPerDiscovery: Int?

    var parameters: CLIRequestParameters {
        var parameters = CLIRequestParameters()
        if let maxScrollsPerContainer {
            parameters.set(.maxScrollsPerContainer, maxScrollsPerContainer)
        }
        if let maxScrollsPerDiscovery {
            parameters.set(.maxScrollsPerDiscovery, maxScrollsPerDiscovery)
        }
        return parameters
    }
}
