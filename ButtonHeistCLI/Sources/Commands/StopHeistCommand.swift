import ArgumentParser
import ButtonHeist
import Foundation

struct StopHeistCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop-heist",
        abstract: "Stop recording and save the heist playback"
    )

    @Option(name: .shortAndLong, help: "Output file path for the .heist file")
    var output: String

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .auto

    @ButtonHeistActor
    func run() async throws {
        let request: [String: Any] = [
            "command": TheFence.Command.stopHeist.rawValue,
            "output": output,
        ]
        try await CLIRunner.run(
            connection: connection,
            format: format,
            request: request
        )
    }
}
