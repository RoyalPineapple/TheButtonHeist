import ArgumentParser
import Foundation
import Darwin
import ButtonHeist

struct ActionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "action",
        abstract: "Perform an action on a UI element",
        discussion: """
            Send action commands to elements in the connected iOS app.

            Examples:
              buttonheist action --identifier "myButton"
              buttonheist action --index 5 --type increment
              buttonheist action --identifier "item" --type custom --custom-action "Delete"
            """
    )

    @Option(name: .long, help: "Element identifier")
    var identifier: String?

    @Option(name: .long, help: "Element index")
    var index: Int?

    @Option(name: .long, help: "Action type: activate, increment, decrement, custom")
    var type: String = "activate"

    @Option(name: .long, help: "Custom action name (when type is 'custom')")
    var customAction: String?

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

        let connector = DeviceConnector(deviceFilter: connection.device, host: connection.host, port: connection.port, quiet: connection.quiet, force: connection.force)
        try await connector.connect()
        defer { connector.disconnect() }
        let client = connector.client

        // Build target
        let target = ActionTarget(identifier: identifier, order: index)

        // Build and send message
        let message: ClientMessage
        switch type.lowercased() {
        case "activate":
            message = .activate(target)
        case "increment":
            message = .increment(target)
        case "decrement":
            message = .decrement(target)
        case "custom":
            guard let actionName = customAction else {
                throw ValidationError("--custom-action required for custom action type")
            }
            message = .performCustomAction(CustomActionTarget(
                elementTarget: target,
                actionName: actionName
            ))
        default:
            throw ValidationError("Unknown action type: \(type). Valid types: activate, increment, decrement, custom")
        }

        if !connection.quiet {
            logStatus("Sending action...")
        }

        client.send(message)

        let result = try await client.waitForActionResult(timeout: timeout)
        outputActionResult(result, format: format, quiet: connection.quiet, verb: "Action")
    }
}
