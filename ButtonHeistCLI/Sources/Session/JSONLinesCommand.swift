import ArgumentParser
import Foundation
import ButtonHeist

enum JSONLinesDefaults {
    static let connectionTimeout: Double = 30.0
    static let idleTimeout: Double = 60.0
    static let outputFormat: OutputFormat = .json
}

struct JSONLinesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "json_lines",
        abstract: "Read canonical JSON commands from stdin",
        discussion: """
            Maintains a single connection and accepts canonical JSON commands on stdin.
            JSON output mode accepts one JSON object per line (e.g. {"command":"one_finger_tap"}).
            Output is JSON by default; pass --format human only for interactive inspection.
            Machine JSON is preflighted before decoding with PublicJSONInputLimits.maxRequestBytes,
            PublicJSONInputLimits.maxNestingDepth, and PublicJSONInputLimits.maxTotalObjectKeys.

            Examples:
              buttonheist json_lines
              buttonheist json_lines --device a1b2
              echo '{"command":"get_interface"}' | buttonheist json_lines
              echo '{"command":"activate","target":{"label":"Sign In","traits":["button"]}}' | buttonheist json_lines
            """
    )

    @Option(name: .long, help: "Target device by name, ID prefix, or index from 'list'")
    var device: String?

    @Option(name: .shortAndLong, help: "Connection timeout in seconds (default: \(Int(JSONLinesDefaults.connectionTimeout)))")
    var timeout: Double = JSONLinesDefaults.connectionTimeout

    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "Auth token from a previous connection")
    var token: String?

    @Option(name: .long, help: "Idle timeout in seconds - exit if no command received (0 = disabled, default: \(Int(JSONLinesDefaults.idleTimeout)))")
    var idleTimeout: Double = JSONLinesDefaults.idleTimeout

    @ButtonHeistActor
    mutating func run() async throws {
        let effectiveFormat = output.format ?? JSONLinesDefaults.outputFormat
        let config = try EnvironmentConfig.resolve(
            deviceFilter: device,
            token: token,
            sessionTimeout: idleTimeout,
            connectionTimeout: timeout
        )
        let session = JSONLinesSession(config: config, format: effectiveFormat)
        try await session.run()
    }
}
