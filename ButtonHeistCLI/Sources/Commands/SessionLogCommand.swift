import ArgumentParser
import ButtonHeist
import Foundation

struct SessionLogCommand: AsyncParsableCommand, CLICommandContract {
    static let fenceCommand = TheFence.Command.getSessionLog

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Show the current session manifest and stats"
    )

    @OptionGroup var connection: ConnectionOptions

    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    func run() async throws {
        let request = Self.fenceRequest()
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request
        )
    }
}
