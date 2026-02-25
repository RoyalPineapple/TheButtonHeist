import ArgumentParser
import Foundation

struct WatchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Watch UI elements in real-time"
    )

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Flag(name: .shortAndLong, help: "Single snapshot then exit (default: watch mode)")
    var once: Bool = false

    @Flag(name: .shortAndLong, help: "Suppress status messages (only output data)")
    var quiet: Bool = false

    @Option(name: .shortAndLong, help: "Timeout in seconds waiting for device (0 = no timeout)")
    var timeout: Int = 0

    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false

    @Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @Flag(name: .long, help: "Force-takeover session from another driver")
    var force: Bool = false

    @Option(name: .long, help: "Auth token from a previous connection")
    var token: String?

    @MainActor
    mutating func run() async throws {
        let options = CLIOptions(
            format: format ?? .auto,
            once: once,
            quiet: quiet,
            timeout: timeout,
            verbose: verbose,
            device: device,
            force: force,
            token: token
        )

        let runner = CLIRunner(options: options)
        try await runner.run()
    }
}
