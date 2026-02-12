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

    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    mutating func run() async throws {
        guard identifier != nil || index != nil else {
            throw ValidationError("Must specify --identifier or --index")
        }

        let client = HeistClient()

        if !quiet {
            logStatus("Searching for iOS devices...")
        }

        // Start discovery
        client.startDiscovery()

        // Wait for device discovery with timeout
        let discoveryTimeout: UInt64 = 5_000_000_000 // 5 seconds
        let startTime = DispatchTime.now()
        while client.discoveredDevices.isEmpty {
            if DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds > discoveryTimeout {
                throw ValidationError("No devices found within timeout")
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        guard let device = client.discoveredDevices.first else {
            throw ValidationError("No devices found")
        }

        if !quiet {
            logStatus("Found device: \(device.name)")
            logStatus("Connecting...")
        }

        // Connect and wait for connection
        var connected = false
        var connectionError: Error?

        client.onConnected = { _ in
            connected = true
        }
        client.onDisconnected = { error in
            connectionError = error
        }

        client.connect(to: device)

        // Wait for connection
        let connectionTimeout: UInt64 = 5_000_000_000 // 5 seconds
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
