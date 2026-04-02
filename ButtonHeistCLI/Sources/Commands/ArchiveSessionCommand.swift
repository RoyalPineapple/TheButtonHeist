import ArgumentParser
import ButtonHeist
import Foundation

struct ArchiveSessionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "archive-session",
        abstract: "Close and archive the current session into a .tar.gz file"
    )

    @Flag(name: .long, help: "Delete the session directory after archiving")
    var deleteSource = false

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .auto

    @ButtonHeistActor
    func run() async throws {
        let request: [String: Any] = [
            "command": TheFence.Command.archiveSession.rawValue,
            "delete_source": deleteSource,
        ]
        try await CLIRunner.run(
            connection: connection,
            format: format,
            request: request
        )
    }
}
