import ArgumentParser
import Foundation

@main
struct ButtonHeist: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "buttonheist",
        abstract: "Inspect and interact with iOS app UI elements.",
        discussion: """
            Connects to an iOS app and displays the UI element hierarchy. Useful for
            testing, debugging, and automation of SwiftUI/UIKit apps.

            Examples:
              buttonheist list                          # Show available devices
              buttonheist watch --once                  # Single snapshot, then exit
              buttonheist --device a1b2 watch --once    # Target a specific instance
              buttonheist action --identifier "myButton"
              buttonheist touch tap --x 100 --y 200
            """,
        version: "2.1.0",
        subcommands: [ListCommand.self, WatchCommand.self, ActionCommand.self,
                       TouchCommand.self, TypeCommand.self, ScreenshotCommand.self,
                       RecordCommand.self, StopRecordingCommand.self, SessionCommand.self,
                       CopyCommand.self, PasteCommand.self, CutCommand.self,
                       SelectCommand.self, SelectAllCommand.self,
                       DismissKeyboardCommand.self],
        defaultSubcommand: WatchCommand.self
    )
}

// MARK: - Watch Command

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

    @Flag(name: .long, help: "Force-takeover session from another driver")
    var force: Bool = false

    @Option(name: .shortAndLong, help: "Timeout in seconds waiting for device (0 = no timeout)")
    var timeout: Int = 0

    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false

    @Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @Option(name: .long, help: "Direct host address (skip Bonjour discovery)")
    var host: String?

    @Option(name: .long, help: "Direct port number (skip Bonjour discovery)")
    var port: UInt16?

    @MainActor
    mutating func run() async throws {
        let options = CLIOptions(
            format: format ?? .auto,
            once: once,
            quiet: quiet,
            force: force,
            timeout: timeout,
            verbose: verbose,
            device: device,
            host: host,
            port: port
        )

        let runner = CLIRunner(options: options)
        try await runner.run()
    }
}

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case human
    case json

    static var auto: OutputFormat {
        isatty(STDIN_FILENO) != 0 ? .human : .json
    }
}

struct CLIOptions {
    let format: OutputFormat
    let once: Bool
    let quiet: Bool
    let force: Bool
    let timeout: Int
    let verbose: Bool
    let device: String?
    let host: String?
    let port: UInt16?
}
