import ArgumentParser
import Foundation

struct WatchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Watch UI elements in real-time"
    )

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Flag(name: .shortAndLong, help: "Single snapshot then exit (default: watch mode)")
    var once: Bool = false

    @Option(name: .shortAndLong, help: "Timeout in seconds waiting for device (0 = no timeout)")
    var timeout: Int = 0

    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false

    @MainActor
    mutating func run() async throws {
        let options = CLIOptions(
            format: format ?? .auto,
            once: once,
            quiet: connection.quiet,
            timeout: timeout,
            verbose: verbose,
            device: connection.device,
            force: connection.force,
            token: connection.token
        )

        let runner = CLIRunner(options: options)
        try await runner.run()
    }
}
