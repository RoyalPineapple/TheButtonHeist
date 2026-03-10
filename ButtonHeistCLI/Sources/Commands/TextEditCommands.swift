import ArgumentParser
import ButtonHeist

// MARK: - Copy

struct CopyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "copy",
        abstract: "Copy selected text via the responder chain"
    )

    @OptionGroup var connection: ConnectionOptions

    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        try await sendEditAction("copy", connection: connection, timeout: timeout, format: output.format)
    }
}

// MARK: - Paste

struct PasteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "paste",
        abstract: "Paste clipboard text via the responder chain"
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        try await sendEditAction("paste", connection: connection, timeout: timeout, format: output.format)
    }
}

// MARK: - Cut

struct CutCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cut",
        abstract: "Cut selected text via the responder chain"
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        try await sendEditAction("cut", connection: connection, timeout: timeout, format: output.format)
    }
}

// MARK: - Select

struct SelectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "select",
        abstract: "Select text at insertion point via the responder chain"
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        try await sendEditAction("select", connection: connection, timeout: timeout, format: output.format)
    }
}

// MARK: - Select All

struct SelectAllCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "select-all",
        abstract: "Select all text via the responder chain"
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        try await sendEditAction("selectAll", connection: connection, timeout: timeout, format: output.format)
    }
}

// MARK: - Shared Helper

@ButtonHeistActor
private func sendEditAction(
    _ action: String,
    connection: ConnectionOptions,
    timeout: Double,
    format: OutputFormat?
) async throws {
    let connector = DeviceConnector(deviceFilter: connection.device, token: connection.token, quiet: connection.quiet)
    try await connector.connect()
    defer { connector.disconnect() }
    let client = connector.client

    if !connection.quiet { logStatus("Sending \(action)...") }
    client.send(.editAction(EditActionTarget(action: action)))
    let result = try await client.waitForActionResult(timeout: timeout)
    outputActionResult(result, format: format, quiet: connection.quiet, verb: action)
}
