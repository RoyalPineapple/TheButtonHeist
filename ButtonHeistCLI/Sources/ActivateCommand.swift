import ArgumentParser
import Foundation
import ButtonHeist

struct ActivateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activate",
        abstract: "Activate a UI element (primary interaction command)",
        discussion: """
            Uses the activation-first pattern: tries accessibilityActivate() \
            (like VoiceOver) first, then falls back to synthetic tap at the \
            element's activation point. This is the most reliable way to \
            interact with buttons, links, and controls.

            Examples:
              buttonheist activate --identifier loginButton
              buttonheist activate --index 3
            """
    )

    @Option(name: .long, help: "Element accessibility identifier")
    var identifier: String?

    @Option(name: .long, help: "Element traversal order index")
    var index: Int?

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @MainActor
    mutating func run() async throws {
        guard identifier != nil || index != nil else {
            throw ValidationError("Must specify --identifier or --index")
        }

        let connector = DeviceConnector(deviceFilter: connection.device, token: connection.token, quiet: connection.quiet, force: connection.force)
        try await connector.connect()
        defer { connector.disconnect() }
        let client = connector.client

        let target = ActionTarget(identifier: identifier, order: index)

        if !connection.quiet {
            logStatus("Activating element...")
        }

        client.send(.activate(target))

        let result = try await client.waitForActionResult(timeout: timeout)
        outputActionResult(result, format: format, quiet: connection.quiet, verb: "Activate")
    }
}
