import ArgumentParser
import Foundation
import Darwin
import ButtonHeist

struct ScrollCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll",
        abstract: "Scroll a scroll view by one page",
        discussion: """
            Scrolls the nearest scroll view ancestor of a target element by
            approximately one page in the given direction via direct content
            offset manipulation.

            Examples:
              buttonheist scroll --identifier "buttonheist.longList.item-5" --direction up
              buttonheist scroll --index 3 --direction down
              buttonheist scroll --identifier "myElement" --direction next
            """
    )

    @Option(name: .long, help: "Element identifier (scroll bubbles up to nearest scroll view)")
    var identifier: String?

    @Option(name: .long, help: "Element index")
    var index: Int?

    @Option(name: .long, help: "Scroll direction: up, down, left, right, next, previous")
    var direction: String

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

        guard let scrollDirection = ScrollDirection(rawValue: direction.lowercased()) else {
            throw ValidationError("Invalid direction '\(direction)'. Valid: up, down, left, right, next, previous")
        }

        let connector = DeviceConnector(deviceFilter: connection.device, token: connection.token, quiet: connection.quiet, force: connection.force)
        try await connector.connect()
        defer { connector.disconnect() }
        let client = connector.client

        let target = ActionTarget(identifier: identifier, order: index)
        let message = ClientMessage.scroll(ScrollTarget(elementTarget: target, direction: scrollDirection))

        if !connection.quiet {
            logStatus("Sending scroll...")
        }

        client.send(message)

        let result = try await client.waitForActionResult(timeout: timeout)
        outputActionResult(result, format: format, quiet: connection.quiet, verb: "Scroll")
    }
}
