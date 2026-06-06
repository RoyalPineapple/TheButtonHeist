import ArgumentParser
import ButtonHeist
import Foundation

struct StopHeistCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Stop heist composition and save a generated heist artifact"
    )

    @Option(name: [.customShort("o"), .customLong("output")], help: "Output path for the generated .heist package")
    var outputPath: String

    @Option(name: .customLong("swift-output"), help: "Output path for a generated Swift DSL authoring draft")
    var swiftOutputPath: String?

    @Option(name: .customLong("sample-parameter"), help: "String parameter name for exact sample rewrite")
    var sampleParameter: String?

    @Option(name: .customLong("sample-value"), help: "Recorded sample value to rewrite exactly")
    var sampleValue: String?

    @OptionGroup var connection: ConnectionOptions

    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    func run() async throws {
        let request = Self.requestParameters(
            outputPath: outputPath,
            swiftOutputPath: swiftOutputPath,
            sampleParameter: sampleParameter,
            sampleValue: sampleValue
        )
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: Self.fenceCommand,
            arguments: Self.fenceArguments(request)
        )
    }

    static func requestParameters(
        outputPath: String,
        swiftOutputPath: String? = nil,
        sampleParameter: String? = nil,
        sampleValue: String? = nil
    ) -> CLIRequestParameters {
        var request: CLIRequestParameters = [.output: .string(outputPath)]
        if let swiftOutputPath {
            request[.swiftOutput] = .string(swiftOutputPath)
        }
        if let sampleParameter {
            request[.sampleParameter] = .string(sampleParameter)
        }
        if let sampleValue {
            request[.sampleValue] = .string(sampleValue)
        }
        return request
    }
}
