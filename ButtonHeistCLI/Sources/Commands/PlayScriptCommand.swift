import ArgumentParser
import ButtonHeist
import Foundation

struct PlayScriptCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "play-script",
        abstract: "Play back a recorded .heist script"
    )

    @Option(name: .shortAndLong, help: "Input .heist file path")
    var input: String

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .auto

    @ButtonHeistActor
    func run() async throws {
        let request: [String: Any] = [
            "command": TheFence.Command.playScript.rawValue,
            "input": input,
        ]
        try await CLIRunner.run(
            connection: connection,
            format: format,
            request: request
        )
    }
}
