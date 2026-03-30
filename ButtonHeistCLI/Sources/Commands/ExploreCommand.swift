import ArgumentParser
import ButtonHeist

struct ExploreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "explore",
        abstract: "Discover every element on screen, including off-screen content in scroll views"
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    func run() async throws {
        let request: [String: Any] = ["command": TheFence.Command.explore.rawValue]
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Exploring screen..."
        )
    }
}
