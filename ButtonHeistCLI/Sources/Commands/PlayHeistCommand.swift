import ArgumentParser
import ButtonHeist
import Foundation

struct PlayHeistCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "play-heist",
        abstract: "Play back a recorded .heist file"
    )

    @Option(name: .shortAndLong, help: "Input .heist file path")
    var input: String

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .auto

    @ButtonHeistActor
    func run() async throws {
        let request: [String: Any] = [
            "command": TheFence.Command.playHeist.rawValue,
            "input": input,
        ]
        try await CLIRunner.run(
            connection: connection,
            format: format,
            request: request
        )
    }
}
