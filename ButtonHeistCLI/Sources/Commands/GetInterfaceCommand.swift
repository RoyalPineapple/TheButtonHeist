import ArgumentParser
import Foundation
import ButtonHeist

struct GetInterfaceCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Read the app accessibility hierarchy from the connected device"
    )

    @OptionGroup var connection: ConnectionOptions

    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    mutating func run() async throws {
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: Self.fenceRequest(),
            statusMessage: "Reading interface..."
        )
    }
}
