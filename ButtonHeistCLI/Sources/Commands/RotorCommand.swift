import ArgumentParser
import ButtonHeist

struct RotorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: TheFence.Command.rotor.rawValue,
        abstract: "Move through an accessibility rotor",
        discussion: """
            Moves one step through one of an element's accessibility rotors. Defaults to next. \
            Use get_interface to inspect an element's rotors first, then pass --rotor or \
            --rotor-index. Pass --current-heist-id from the previous result to continue through \
            object results. For text-range results, pass --current-heist-id plus the returned \
            start and end offsets.

            Examples:
              buttonheist rotor form --rotor Errors
              buttonheist rotor -l "Validation Results" --rotor-index 0
              buttonheist rotor form --rotor Errors --direction previous --current-heist-id field_email
              buttonheist rotor notes --rotor Mentions --current-heist-id notes --current-text-start-offset 10 --current-text-end-offset 16
            """
    )

    @OptionGroup var element: ElementTargetOptions
    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions
    @OptionGroup var timeoutOption: TimeoutOption

    @Option(name: .long, help: "Rotor name from get_interface")
    var rotor: String?

    @Option(name: .customLong("rotor-index"), help: "Zero-based rotor index")
    var rotorIndex: Int?

    @Option(name: .shortAndLong, help: "Direction: next or previous (default: next)")
    var direction: String = RotorDirection.next.rawValue

    @Option(name: .customLong("current-heist-id"), help: "Current rotor item heistId for continuing next/previous")
    var currentHeistId: String?

    @Option(name: .customLong("current-text-start-offset"), help: "Current text-range start offset for continuing text-range rotors")
    var currentTextStartOffset: Int?

    @Option(name: .customLong("current-text-end-offset"), help: "Current text-range end offset for continuing text-range rotors")
    var currentTextEndOffset: Int?

    @ButtonHeistActor
    mutating func run() async throws {
        _ = try element.requireTarget()
        if let rotorIndex, rotorIndex < 0 {
            throw ValidationError("rotor-index must be non-negative")
        }
        guard RotorDirection(rawValue: direction.lowercased()) != nil else {
            throw ValidationError("Invalid direction '\(direction)'. Valid: \(RotorDirection.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        if (currentTextStartOffset == nil) != (currentTextEndOffset == nil) {
            throw ValidationError("current-text-start-offset and current-text-end-offset must be provided together")
        }
        if let start = currentTextStartOffset, let end = currentTextEndOffset {
            guard currentHeistId != nil else {
                throw ValidationError("current-heist-id is required when continuing from a text range")
            }
            guard start >= 0, end >= start else {
                throw ValidationError("current text range offsets must be non-negative with end >= start")
            }
        }

        var request: [String: Any] = [
            "command": TheFence.Command.rotor.rawValue,
            "direction": direction.lowercased(),
        ]
        if let rotor { request["rotor"] = rotor }
        if let rotorIndex { request["rotorIndex"] = rotorIndex }
        if let currentHeistId { request["currentHeistId"] = currentHeistId }
        if let currentTextStartOffset { request["currentTextStartOffset"] = currentTextStartOffset }
        if let currentTextEndOffset { request["currentTextEndOffset"] = currentTextEndOffset }

        try element.applyTo(&request)
        request["timeout"] = timeoutOption.timeout

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Moving rotor..."
        )
    }
}
