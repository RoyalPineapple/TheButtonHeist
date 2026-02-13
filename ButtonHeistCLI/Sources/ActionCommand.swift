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

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

    @Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    mutating func run() async throws {
        guard identifier != nil || index != nil else {
            throw ValidationError("Must specify --identifier or --index")
        }

        let connector = DeviceConnector(deviceFilter: device, quiet: quiet)
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

        if !quiet {
            logStatus("Sending action...")
        }

        client.send(message)

        // Wait for result
        let result = try await client.waitForActionResult(timeout: timeout)

        if result.success {
            if !quiet {
                logStatus("Action succeeded (method: \(result.method.rawValue))")
            }
            writeOutput("success")
        } else {
            let errorMessage = result.message ?? result.method.rawValue
            if !quiet {
                logStatus("Action failed: \(errorMessage)")
            }
            writeOutput("failed: \(errorMessage)")
            Darwin.exit(1)
        }
    }
}
