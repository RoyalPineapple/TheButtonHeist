import ArgumentParser
import Foundation
import ButtonHeist

enum SessionDefaults {
    static let connectionTimeout: Double = 30.0
    static let sessionTimeout: Double = 60.0
    static let timeoutCheckInterval: Double = 5.0
}

struct SessionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "Start a persistent REPL session with an iOS device",
        discussion: """
            Maintains a single connection and accepts commands on stdin.
            Interactive mode accepts plain-text commands (e.g. 'tap myButton').
            JSON input is always accepted (e.g. {"command":"one_finger_tap"}).
            Output is human-readable by default, compact JSON when piped.

            Examples:
              buttonheist session
              buttonheist session --device a1b2
              echo '{"command":"get_interface"}' | buttonheist session --format json
              echo 'tap myButton' | buttonheist session --format json
            """
    )

    @Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @Option(name: .shortAndLong, help: "Connection timeout in seconds (default: \(Int(SessionDefaults.connectionTimeout)))")
    var timeout: Double = SessionDefaults.connectionTimeout

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .long, help: "Auth token from a previous connection")
    var token: String?

    @Option(name: .long, help: "Idle timeout in seconds — exit if no command received (0 = disabled, default: \(Int(SessionDefaults.sessionTimeout)))")
    var sessionTimeout: Double = SessionDefaults.sessionTimeout

    @ButtonHeistActor
    mutating func run() async throws {
        let effectiveFormat = format ?? .auto
        let config = EnvironmentConfig.resolve(
            deviceFilter: device,
            token: token,
            sessionTimeout: sessionTimeout,
            connectionTimeout: timeout
        )
        let repl = ReplSession(config: config, format: effectiveFormat)
        try await repl.run()
    }
}
