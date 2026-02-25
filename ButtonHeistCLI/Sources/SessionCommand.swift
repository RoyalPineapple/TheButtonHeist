import ArgumentParser
import Foundation
import ButtonHeist

struct SessionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "Start a persistent REPL session with an iOS device",
        discussion: """
            Maintains a single connection and accepts JSON commands on stdin.
            Responses are written to stdout — human-readable by default when
            interactive, compact JSON when piped.

            Examples:
              buttonheist session
              buttonheist session --device a1b2
              echo '{"command":"get_interface"}' | buttonheist session
              buttonheist session --format json <<EOF
              {"command":"tap","identifier":"myButton"}
              {"command":"get_interface"}
              {"command":"quit"}
              EOF
            """
    )

    @Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @Option(name: .long, help: "Direct host address (skip Bonjour discovery)")
    var host: String?

    @Option(name: .long, help: "Direct port number (skip Bonjour discovery)")
    var port: UInt16?

    @Option(name: .shortAndLong, help: "Connection timeout in seconds")
    var timeout: Double = 30.0

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @MainActor
    mutating func run() async throws {
        let effectiveFormat = format ?? .auto
        let runner = SessionRunner(deviceFilter: device, host: host, port: port,
                                   connectionTimeout: timeout, format: effectiveFormat)
        try await runner.run()
    }
}
