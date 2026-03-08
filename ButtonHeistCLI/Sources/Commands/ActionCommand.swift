import ArgumentParser
import Foundation
import Darwin
import ButtonHeist

struct ActionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "action",
        abstract: "Perform accessibility actions (increment, decrement, custom)",
        discussion: """
            For activating elements (buttons, links, controls), use \
            `buttonheist activate` instead — it's simpler and more discoverable.

            This command handles accessibility action types:
              buttonheist action --type increment --identifier volumeSlider
              buttonheist action --type decrement --identifier volumeSlider
              buttonheist action --type custom --identifier myCell --custom-action "Delete"
            """
    )

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .long, help: "Action type: activate, increment, decrement, custom")
    var type: String = "activate"

    @Option(name: .long, help: "Custom action name (when type is 'custom')")
    var customAction: String?

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @MainActor
    mutating func run() async throws {
        let target = try element.requireTarget()

        let connector = DeviceConnector(deviceFilter: connection.device, token: connection.token, quiet: connection.quiet, force: connection.force)
        try await connector.connect()
        defer { connector.disconnect() }
        let client = connector.client

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
        outputActionResult(result, format: output.format, quiet: connection.quiet, verb: "Action")
    }
}
