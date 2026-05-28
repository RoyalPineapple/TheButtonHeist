import ArgumentParser
import ButtonHeist
import Foundation

struct StopHeistCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Stop recording and save the heist playback"
    )

    @Option(name: [.customShort("o"), .customLong("output")], help: "Output file path for the .heist file")
    var outputPath: String

    @OptionGroup var connection: ConnectionOptions

    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    func run() async throws {
        let request: CLIRequestParameters = [.output: .string(outputPath)]
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            operation: try Self.fenceOperation(request)
        )
    }
}
