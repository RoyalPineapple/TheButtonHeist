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

        let client = HeistClient()

        if !quiet {
            logStatus("Searching for iOS devices...")
        }

        client.startDiscovery()

        let discoveryTimeout: UInt64 = 5_000_000_000
        let startTime = DispatchTime.now()
        while client.discoveredDevices.isEmpty {
            if DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds > discoveryTimeout {
                throw ValidationError("No devices found within timeout")
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        guard let device = client.discoveredDevices.first else {
            throw ValidationError("No devices found")
        }

        if !quiet {
            logStatus("Found device: \(device.name)")
            logStatus("Connecting...")
        }

        var connected = false
        var connectionError: Error?

        client.onConnected = { _ in connected = true }
        client.onDisconnected = { error in connectionError = error }

        client.connect(to: device)

        let connectionTimeout: UInt64 = 5_000_000_000
        let connectionStart = DispatchTime.now()
        while !connected && connectionError == nil {
            if DispatchTime.now().uptimeNanoseconds - connectionStart.uptimeNanoseconds > connectionTimeout {
                throw ValidationError("Connection timed out")
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        if let error = connectionError {
            throw ValidationError("Connection failed: \(error.localizedDescription)")
        }

        if !quiet {
            logStatus("Connected")
        }

        defer {
            client.disconnect()
            client.stopDiscovery()
        }

        if !quiet {
            logStatus("Sending type command...")
        }

        client.send(message)

        let result = try await client.waitForActionResult(timeout: timeout)

        if result.success {
            if !quiet {
                logStatus("Type succeeded (method: \(result.method.rawValue))")
            }
            // Output the field value if available, otherwise "success"
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
