import ArgumentParser
import ButtonHeist

struct WaitForIdleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wait_for_idle",
        abstract: "Wait for UI animations to settle before reading state or performing actions"
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Maximum wait time in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        let request: [String: Any] = [
            "command": TheFence.Command.waitForIdle.rawValue,
            "timeout": timeout,
        ]
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Waiting for idle..."
        )
    }
}
