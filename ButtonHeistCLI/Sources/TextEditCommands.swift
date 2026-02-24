import ArgumentParser
import Foundation
import Darwin
import ButtonHeist

// MARK: - Copy

struct CopyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "copy",
        abstract: "Copy selected text via the responder chain"
    )

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

    @Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @Option(name: .long, help: "Direct host address (skip Bonjour discovery)")
    var host: String?

    @Option(name: .long, help: "Direct port number (skip Bonjour discovery)")
    var port: UInt16?

    @MainActor
    mutating func run() async throws {
        try await sendEditAction("copy", timeout: timeout, quiet: quiet, device: device, host: host, port: port, format: format)
    }
}

// MARK: - Paste

struct PasteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "paste",
        abstract: "Paste clipboard text via the responder chain"
    )

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

    @Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @Option(name: .long, help: "Direct host address (skip Bonjour discovery)")
    var host: String?

    @Option(name: .long, help: "Direct port number (skip Bonjour discovery)")
    var port: UInt16?

    @MainActor
    mutating func run() async throws {
        try await sendEditAction("paste", timeout: timeout, quiet: quiet, device: device, host: host, port: port, format: format)
    }
}

// MARK: - Cut

struct CutCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cut",
        abstract: "Cut selected text via the responder chain"
    )

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

    @Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @Option(name: .long, help: "Direct host address (skip Bonjour discovery)")
    var host: String?

    @Option(name: .long, help: "Direct port number (skip Bonjour discovery)")
    var port: UInt16?

    @MainActor
    mutating func run() async throws {
        try await sendEditAction("cut", timeout: timeout, quiet: quiet, device: device, host: host, port: port, format: format)
    }
}

// MARK: - Select

struct SelectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "select",
        abstract: "Select text at insertion point via the responder chain"
    )

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

    @Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @Option(name: .long, help: "Direct host address (skip Bonjour discovery)")
    var host: String?

    @Option(name: .long, help: "Direct port number (skip Bonjour discovery)")
    var port: UInt16?

    @MainActor
    mutating func run() async throws {
        try await sendEditAction("select", timeout: timeout, quiet: quiet, device: device, host: host, port: port, format: format)
    }
}

// MARK: - Select All

struct SelectAllCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "select-all",
        abstract: "Select all text via the responder chain"
    )

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

    @Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @Option(name: .long, help: "Direct host address (skip Bonjour discovery)")
    var host: String?

    @Option(name: .long, help: "Direct port number (skip Bonjour discovery)")
    var port: UInt16?

    @MainActor
    mutating func run() async throws {
        try await sendEditAction("selectAll", timeout: timeout, quiet: quiet, device: device, host: host, port: port, format: format)
    }
}

// MARK: - Shared Helper

@MainActor
private func sendEditAction(_ action: String, timeout: Double, quiet: Bool,
                             device: String?, host: String? = nil, port: UInt16? = nil,
                             format: OutputFormat? = nil) async throws {
    let connector = DeviceConnector(deviceFilter: device, host: host, port: port, quiet: quiet)
    try await connector.connect()
    defer { connector.disconnect() }
    let client = connector.client

    if !quiet { logStatus("Sending \(action)...") }
    client.send(.editAction(EditActionTarget(action: action)))
    let result = try await client.waitForActionResult(timeout: timeout)

    switch format ?? .auto {
    case .json:
        writeOutput(formatActionResultJSON(result))
        if !result.success { Darwin.exit(1) }
    case .human:
        if result.success {
            if !quiet { logStatus("\(action) succeeded") }
            writeOutput("success")
        } else {
            let msg = result.message ?? "failed"
            if !quiet { logStatus("\(action) failed: \(msg)") }
            writeOutput("failed: \(msg)")
            Darwin.exit(1)
        }
    }
}
