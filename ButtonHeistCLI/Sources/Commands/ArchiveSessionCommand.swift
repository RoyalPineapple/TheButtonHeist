import ArgumentParser
import ButtonHeist
import Foundation

struct ArchiveSessionCommand: AsyncParsableCommand, CLICommandContract {
    static let fenceCommand = TheFence.Command.archiveSession

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Close and archive the current session into a .tar.gz file"
    )

    @Flag(name: .long, help: "Delete the session directory after archiving")
    var deleteSource = false

    @OptionGroup var connection: ConnectionOptions

    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    func run() async throws {
        let request = Self.fenceRequest(["delete_source": deleteSource])
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request
        )
    }
}
