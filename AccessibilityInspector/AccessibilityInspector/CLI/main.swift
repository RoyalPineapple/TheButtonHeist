import ArgumentParser
import Foundation

@main
struct A11yInspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "a11y-inspect",
        abstract: "Inspect iOS app accessibility hierarchy over the network.",
        discussion: """
            Connects to an iOS app running the AccessibilityBridge server and displays
            the accessibility element hierarchy. Useful for accessibility testing and
            debugging SwiftUI/UIKit apps.

            Examples:
              a11y-inspect                     # Interactive watch mode
              a11y-inspect --once              # Single snapshot, then exit
              a11y-inspect --format json       # JSON output for scripting
              a11y-inspect -q --once | jq .    # Quiet mode, pipe to jq
            """,
        version: "1.0.0"
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
