import ArgumentParser
import Foundation
import Darwin
import ButtonHeist

struct TypeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type",
        abstract: "Type text into a field by tapping keyboard keys",
        discussion: """
            Type text character-by-character and/or delete characters.
            Returns the current text field value after the operation.

            Examples:
              buttonheist type --text "Hello" --identifier "nameField"
              buttonheist type --delete 3 --identifier "nameField"
              buttonheist type --delete 4 --text "orld" --identifier "nameField"
            """
    )

    @Option(name: .long, help: "Text to type")
    var text: String?

    @Option(name: .long, help: "Number of characters to delete before typing")
    var delete: Int?

    @Option(name: .long, help: "Element identifier to target (focuses field, reads value back)")
    var identifier: String?

    @Option(name: .long, help: "Element index to target")
    var index: Int?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 30.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

    @Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @MainActor
    mutating func run() async throws {
        guard text != nil || delete != nil else {
            throw ValidationError("Must specify --text, --delete, or both")
        }

        let elementTarget: ActionTarget? = (identifier != nil || index != nil)
            ? ActionTarget(identifier: identifier, order: index) : nil

        let message = ClientMessage.typeText(TypeTextTarget(
            text: text,
            deleteCount: delete,
            elementTarget: elementTarget
        ))

        let connector = DeviceConnector(deviceFilter: device, quiet: quiet)
        try await connector.connect()
        defer { connector.disconnect() }
        let client = connector.client

        if !quiet {
            logStatus("Sending type command...")
        }

        client.send(message)

        let result = try await client.waitForActionResult(timeout: timeout)

        if result.success {
            if !quiet {
                logStatus("Type succeeded (method: \(result.method.rawValue))")
            }
            writeOutput(result.value ?? "success")
        } else {
            let errorMessage = result.message ?? result.method.rawValue
            if !quiet {
                logStatus("Type failed: \(errorMessage)")
            }
            writeOutput("failed: \(errorMessage)")
            Darwin.exit(1)
        }
    }
}
