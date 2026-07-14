import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist
import ThePlans

struct RotorCommand: ConnectedOneShotCLICommand {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Move through an accessibility rotor",
        discussion: """
            Moves one step through one of an element's accessibility rotors. Defaults to next. \
            Use get_interface to inspect an element's rotors first, then pass --rotor or \
            --rotor-index. The server holds the rotor cursor while in rotor mode: the first call \
            enters at the first item, and repeating the command on the same element cycles from \
            there. Any other interaction exits rotor mode and drops the cursor.

            Examples:
              buttonheist rotor form --rotor Errors
              buttonheist rotor -l "Validation Results" --rotor-index 0
              buttonheist rotor form --rotor Errors --direction previous
            """
    )

    @OptionGroup var element: AccessibilityTargetOptions
    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions
    @OptionGroup var timeoutOption: TimeoutOption

    @Option(name: .long, help: "Rotor name from get_interface")
    var rotor: String?

    @Option(name: .customLong("rotor-index"), help: "Zero-based rotor index")
    var rotorIndex: Int?

    @Option(
        name: .shortAndLong,
        help: "Direction: \(Self.catalogAllowedValuesDescription(for: FenceParameters.rotorDirection))"
    )
    var direction: String = Self.catalogDefaultArgument(for: FenceParameters.rotorDirection)

    var runnerStatusMessage: String? { "Moving rotor..." }

    func requestArguments() throws -> TheFence.CommandArgumentEnvelope {
        let target = try element.requireTarget()
        if let rotorIndex, rotorIndex < 0 {
            throw ValidationError("rotor-index must be non-negative")
        }
        guard let rotorDirection = Self.catalogCanonicalValue(direction, for: FenceParameters.rotorDirection) else {
            throw ValidationError("Invalid direction '\(direction)'. Valid: \(Self.catalogAllowedValuesDescription(for: FenceParameters.rotorDirection))")
        }

        return Self.fenceArguments(
            target: target,
            CommandArgumentEnvelopeBuilder.value(FenceParameters.rotorDirection, rotorDirection),
            CommandArgumentEnvelopeBuilder.optional(.rotor, rotor),
            CommandArgumentEnvelopeBuilder.optional(.rotorIndex, rotorIndex),
            CommandArgumentEnvelopeBuilder.value(.timeout, timeoutOption.timeout)
        )
    }
}
