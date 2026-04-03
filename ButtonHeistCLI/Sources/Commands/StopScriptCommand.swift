import ArgumentParser
import ButtonHeist
import Foundation

struct StopScriptCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop-script",
        abstract: "Stop recording and save the playback script"
    )

    @Option(name: .shortAndLong, help: "Output file path for the .heist script")
    var output: String

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .auto

    @ButtonHeistActor
    func run() async throws {
        let request: [String: Any] = [
            "command": TheFence.Command.stopScript.rawValue,
            "output": output,
        ]
        try await CLIRunner.run(
            connection: connection,
            format: format,
            request: request
        )
    }
}
