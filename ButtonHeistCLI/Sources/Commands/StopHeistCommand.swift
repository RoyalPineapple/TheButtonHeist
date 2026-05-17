import ArgumentParser
import ButtonHeist
import Foundation

struct StopHeistCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: TheFence.Command.stopHeist.rawValue,
        abstract: "Stop recording and save the heist playback"
    )

    @Option(name: [.customShort("o"), .customLong("output")], help: "Output file path for the .heist file")
    var outputPath: String

    @OptionGroup var connection: ConnectionOptions

    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    func run() async throws {
        let request: [String: Any] = [
            "command": TheFence.Command.stopHeist.rawValue,
            "output": outputPath,
        ]
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request
        )
    }
}
