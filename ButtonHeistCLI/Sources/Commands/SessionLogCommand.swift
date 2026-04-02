import ArgumentParser
import ButtonHeist
import Foundation

struct SessionLogCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session-log",
        abstract: "Show the current session manifest and stats"
    )

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .auto

    @ButtonHeistActor
    func run() async throws {
        let request: [String: Any] = ["command": TheFence.Command.getSessionLog.rawValue]
        try await CLIRunner.run(
            connection: connection,
            format: format,
            request: request
        )
    }
}
