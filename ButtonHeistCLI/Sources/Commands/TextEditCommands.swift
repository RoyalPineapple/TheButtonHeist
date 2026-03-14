import ArgumentParser
import ButtonHeist
import TheScore

struct EditCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Text editing via the responder chain (copy, paste, cut, select, select_all)",
        discussion: """
            Sends standard edit actions through the iOS responder chain.

            Examples:
              buttonheist edit copy
              buttonheist edit paste
              buttonheist edit select_all
            """,
        subcommands: [
            CopySubcommand.self,
            PasteSubcommand.self,
            CutSubcommand.self,
            SelectSubcommand.self,
            SelectAllSubcommand.self,
        ]
    )
}

// MARK: - Subcommands

struct CopySubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "copy", abstract: "Copy selected text")
    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions
    @Option(name: .shortAndLong, help: "Timeout in seconds") var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        try await sendEditAction(.copy, connection: connection, timeout: timeout, format: output.format)
    }
}

struct PasteSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "paste", abstract: "Paste clipboard text")
    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions
    @Option(name: .shortAndLong, help: "Timeout in seconds") var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        try await sendEditAction(.paste, connection: connection, timeout: timeout, format: output.format)
    }
}

struct CutSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "cut", abstract: "Cut selected text")
    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions
    @Option(name: .shortAndLong, help: "Timeout in seconds") var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        try await sendEditAction(.cut, connection: connection, timeout: timeout, format: output.format)
    }
}

struct SelectSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "select", abstract: "Select text at insertion point")
    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions
    @Option(name: .shortAndLong, help: "Timeout in seconds") var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        try await sendEditAction(.select, connection: connection, timeout: timeout, format: output.format)
    }
}

struct SelectAllSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "select_all", abstract: "Select all text")
    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions
    @Option(name: .shortAndLong, help: "Timeout in seconds") var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        try await sendEditAction(.selectAll, connection: connection, timeout: timeout, format: output.format)
    }
}

// MARK: - Shared Helper

@ButtonHeistActor
private func sendEditAction(
    _ action: EditAction,
    connection: ConnectionOptions,
    timeout: Double,
    format: OutputFormat?
) async throws {
    let connector = DeviceConnector(deviceFilter: connection.device, token: connection.token, quiet: connection.quiet)
    try await connector.connect()
    defer { connector.disconnect() }
    let client = connector.client

    if !connection.quiet { logStatus("Sending \(action.rawValue)...") }
    client.send(.editAction(EditActionTarget(action: action)))
    let result = try await client.waitForActionResult(timeout: timeout)
    outputActionResult(result, format: format, quiet: connection.quiet, verb: action.rawValue)
}
