import ArgumentParser
import Foundation

@main
struct Accra: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "accra",
        abstract: "Inspect and interact with iOS app accessibility hierarchy.",
        discussion: """
            Connects to an iOS app running AccraHost and displays the accessibility
            element hierarchy. Useful for accessibility testing, debugging, and
            automation of SwiftUI/UIKit apps.

            Examples:
              accra                     # Interactive watch mode
              accra watch --once        # Single snapshot, then exit
              accra action --identifier "myButton"   # Activate an element
              accra action --type tap --x 100 --y 200  # Tap coordinates
            """,
        version: "2.0.0",
        subcommands: [WatchCommand.self, ActionCommand.self],
        defaultSubcommand: WatchCommand.self
    )
}

// MARK: - Watch Command

struct WatchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Watch accessibility hierarchy in real-time"
    )

    @Option(name: .shortAndLong, help: "Output format: human, json")
    var format: OutputFormat = .human

    @Flag(name: .shortAndLong, help: "Single snapshot then exit (default: watch mode)")
    var once: Bool = false

    @Flag(name: .shortAndLong, help: "Suppress status messages (only output data)")
    var quiet: Bool = false

    @Option(name: .shortAndLong, help: "Timeout in seconds waiting for device (0 = no timeout)")
    var timeout: Int = 0

    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false

    @MainActor
    mutating func run() async throws {
        let options = CLIOptions(
            format: format,
            once: once,
            quiet: quiet,
            timeout: timeout,
            verbose: verbose
        )

        let runner = CLIRunner(options: options)
        try await runner.run()
    }
}

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case human
    case json
}

struct CLIOptions {
    let format: OutputFormat
    let once: Bool
    let quiet: Bool
    let timeout: Int
    let verbose: Bool
}
