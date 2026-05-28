import ArgumentParser
import ButtonHeist
import Foundation

struct SessionLogCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Show the current session log snapshot and stats"
    )

    @OptionGroup var connection: ConnectionOptions

    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    func run() async throws {
        let request: CLIRequestParameters = [:]
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            operation: try Self.fenceOperation(request)
        )
    }
}
