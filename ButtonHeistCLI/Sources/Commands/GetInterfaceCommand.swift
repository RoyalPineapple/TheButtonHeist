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

    @OptionGroup var subtree: AccessibilityTargetOptions

    @OptionGroup var discoveryLimits: InterfaceDiscoveryLimitOptions

    @ButtonHeistActor
    mutating func run() async throws {
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: Self.fenceCommand,
            arguments: try requestArguments(),
            statusMessage: "Reading interface..."
        )
    }

    func requestArguments() throws -> TheFence.CommandArgumentEnvelope {
        let subtreeValue = try subtree.parsedTarget().map(CLIRequestBuilder.targetValue)
        return Self.fenceArguments(
            discoveryLimits.parameters.adding(
                CommandArgumentWriter.optional(.subtree, subtreeValue)
            )
        )
    }
}

struct InterfaceDiscoveryLimitOptions: ParsableArguments {
    @Option(name: .long, help: "Maximum page-scroll attempts per scroll container during interface discovery.")
    var maxScrollsPerContainer: Int?

    @Option(name: .long, help: "Maximum total page-scroll attempts during interface discovery.")
    var maxScrollsPerDiscovery: Int?

    var parameters: CLIRequestFields {
        CommandArgumentWriter.parameters(
            CommandArgumentWriter.optional(.maxScrollsPerContainer, maxScrollsPerContainer),
            CommandArgumentWriter.optional(.maxScrollsPerDiscovery, maxScrollsPerDiscovery)
        )
    }
}
