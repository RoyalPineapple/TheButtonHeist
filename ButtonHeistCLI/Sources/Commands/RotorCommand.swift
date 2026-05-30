import ArgumentParser
import ButtonHeist

struct RotorCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Move through an accessibility rotor",
        discussion: """
            Moves one step through one of an element's accessibility rotors. Defaults to next. \
            Use get_interface to inspect an element's rotors first, then pass --rotor or \
            --rotor-index. Pass --continuation as a JSON object from the previous result when \
            another rotor step is available.

            Examples:
              buttonheist rotor form --rotor Errors
              buttonheist rotor -l "Validation Results" --rotor-index 0
              buttonheist rotor form --rotor Errors --direction previous --continuation '{"heistId":"field_email"}'
              buttonheist rotor notes --rotor Mentions --continuation '{"heistId":"notes","textRange":{"startOffset":10,"endOffset":16}}'
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

    @Option(
        name: .shortAndLong,
        help: "Direction: \(Self.catalogAllowedValuesDescription(for: .direction))"
    )
    var direction: String = Self.catalogDefaultString(for: .direction)

    @Option(name: .long, help: "Rotor continuation JSON object from a previous rotor result")
    var continuation: String?

    @Option(name: .customLong("continuation-from-file"), help: "Path to a rotor continuation JSON object")
    var continuationFile: String?

    @ButtonHeistActor
    mutating func run() async throws {
        let target = try element.requireTarget()
        if let rotorIndex, rotorIndex < 0 {
            throw ValidationError("rotor-index must be non-negative")
        }
        guard let rotorDirection = Self.catalogCanonicalStringValue(direction, for: .direction) else {
            throw ValidationError("Invalid direction '\(direction)'. Valid: \(Self.catalogAllowedValuesDescription(for: .direction))")
        }

        var request: CLIRequestParameters = [.direction: .string(rotorDirection)]
        if let rotor { request.set(.rotor, rotor) }
        if let rotorIndex { request.set(.rotorIndex, rotorIndex) }
        if let continuationObject = try loadJSONObject(
            inline: continuation,
            fromFile: continuationFile,
            optionName: "continuation"
        ) {
            request.set(.continuation, .object(continuationObject))
        }

        request.set(.timeout, timeoutOption.timeout)

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: Self.fenceCommand,
            arguments: Self.fenceArguments(request, target: target),
            statusMessage: "Moving rotor..."
        )
    }
}
