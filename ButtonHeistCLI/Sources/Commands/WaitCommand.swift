import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist
import ThePlans
import TheScore

struct WaitCommand: ConnectedOneShotCLICommand {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Wait until an accessibility predicate is satisfied",
        discussion: """
            Waits until an accessibility predicate becomes true. `--exists`/`--missing` \
            poll the current interface for an element matching the supplied element \
            fields; `--change` rides settled UI transitions. Uses settle-event \
            polling, not busy-waiting. Explicit timeouts use the configured \
            Button Heist wait limit.

            Examples:
              buttonheist wait --exists -l "Welcome"
              buttonheist wait --missing -l "Loading" -t 5
              buttonheist wait --change screen
              buttonheist wait --predicate '{"type":"no_change"}'
            """
    )

    @OptionGroup var predicateInput: WaitPredicateInput

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(
        name: .shortAndLong,
        help: "Maximum wait time in seconds (default: \(Int(CLITimeoutDefaults.wait)), max: \(WaitTimeout.maximumSeconds))"
    )
    var timeout: Double = CLITimeoutDefaults.wait

    func validate() throws {
        do {
            _ = try WaitTimeout(validatingSeconds: timeout)
        } catch {
            throw ValidationError(String(describing: error))
        }
    }

    var runnerStatusMessage: String? { "Waiting for predicate..." }

    func requestArguments() throws -> TheFence.CommandArgumentEnvelope {
        Self.fenceArguments(
            CommandArgumentEnvelopeBuilder.value(.timeout, timeout),
            CommandArgumentEnvelopeBuilder.value(.predicate, try predicateInput.predicateValue())
        )
    }
}

enum WaitChangeKind: String, CaseIterable, ExpressibleByArgument {
    case screen
    case elements

    static var allowedValuesDescription: String {
        allCases.map(\.rawValue).joined(separator: ", ")
    }
}

struct WaitPredicateInput: ParsableArguments {
    @OptionGroup var element: AccessibilityTargetOptions

    @Flag(
        exclusivity: .exclusive,
        help: "Wait for an element matching the element fields to exist or be missing"
    )
    var presence: WaitPresenceKind?

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Wait for a change: \(WaitChangeKind.allowedValuesDescription)"
        )
    )
    var change: WaitChangeKind?

    @Option(name: .long, help: "Full predicate as a JSON object")
    var predicate: String?

    mutating func validate() throws {
        _ = try predicateSource()
    }

    func predicateValue() throws -> HeistValue {
        switch try predicateSource() {
        case .rawPredicate(let predicate):
            return try TheFence.parseExpectationArgument(predicate)
        case .accessibilityPredicate(let accessibilityPredicate):
            return try Self.heistValue(from: accessibilityPredicate)
        }
    }

    private func predicateSource() throws -> WaitPredicateSource {
        switch (presence, change, predicate) {
        case (.some(let presence), nil, nil):
            return .accessibilityPredicate(try presence.predicate(element: element))
        case (nil, .some(let change), nil):
            return .accessibilityPredicate(change.predicate())
        case (nil, nil, .some(let predicate)):
            return .rawPredicate(predicate)
        case (nil, nil, nil):
            throw ValidationError("Specify exactly one of --exists, --missing, --change, or --predicate")
        default:
            throw ValidationError("Specify exactly one of --exists, --missing, --change, or --predicate")
        }
    }

    private static func heistValue(from predicate: AccessibilityPredicate) throws -> HeistValue {
        try TheFence.HeistValuePayloadEncoder.encode(predicate)
    }
}

private enum WaitPredicateSource {
    case accessibilityPredicate(AccessibilityPredicate)
    case rawPredicate(String)
}

enum WaitPresenceKind: String, EnumerableFlag {
    case exists
    case missing

    func predicate(element: AccessibilityTargetOptions) throws -> AccessibilityPredicate {
        guard let target = try element.parsedTarget() else {
            throw ValidationError("--exists/--missing require element fields (e.g. -l, --identifier)")
        }
        switch self {
        case .exists:
            return .exists(target)
        case .missing:
            return .missing(target)
        }
    }
}

private extension WaitChangeKind {
    func predicate() -> AccessibilityPredicate {
        switch self {
        case .screen:
            return .changed(.screen())
        case .elements:
            return .changed(.elements())
        }
    }
}
