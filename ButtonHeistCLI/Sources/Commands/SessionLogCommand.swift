import ArgumentParser
import ButtonHeist
import Foundation

struct SessionLogCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get_session_log",
        abstract: "Show the current session manifest and stats"
    )

    @OptionGroup var connection: ConnectionOptions

    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    func run() async throws {
        let request: [String: Any] = ["command": TheFence.Command.getSessionLog.rawValue]
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request
        )
    }
}
