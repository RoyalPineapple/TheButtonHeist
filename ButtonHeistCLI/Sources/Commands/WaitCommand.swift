import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist
import Foundation
import ThePlans

struct WaitCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Wait until an accessibility predicate is satisfied",
        discussion: """
            Waits until an accessibility predicate becomes true. `--exists`/`--missing` \
            poll the current interface for an element matching the supplied element \
            fields; `--change` rides settled UI transitions. Uses settle-event \
            polling, not busy-waiting. Timeout is capped at 30 seconds.

            Examples:
              buttonheist wait --exists -l "Welcome"
              buttonheist wait --missing -l "Loading" -t 5
              buttonheist wait --change screen
              buttonheist wait --predicate '{"type":"exists","element":{"label":"Done"}}'
            """
    )

    @OptionGroup var predicateInput: WaitPredicateInput

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Maximum wait time in seconds (default: 10, max: 30)")
    var timeout: Double = 10.0

    func validate() throws {
        guard timeout > 0 && timeout <= 30 else {
            throw ValidationError("timeout must be greater than 0 and at most 30 seconds, got \(timeout)")
        }
    }

    @ButtonHeistActor
    mutating func run() async throws {
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: Self.fenceCommand,
            arguments: try requestArguments(),
            statusMessage: "Waiting for predicate..."
        )
    }

    func requestArguments() throws -> TheFence.CommandArgumentEnvelope {
        Self.fenceArguments(
            CommandArgumentWriter.value(.timeout, timeout),
            CommandArgumentWriter.value(.predicate, try predicateInput.predicateValue())
        )
    }
}

enum WaitChangeKind: String, CaseIterable, ExpressibleByArgument {
    case screen
    case elements
    case updated

    static var allowedValuesDescription: String {
        allCases.map(\.rawValue).joined(separator: ", ")
    }
}

struct WaitPredicateInput: ParsableArguments {
    @OptionGroup var element: ElementTargetOptions

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
            return .accessibilityPredicate(try change.predicate(element: element))
        case (nil, nil, .some(let predicate)):
            return .rawPredicate(predicate)
        case (nil, nil, nil):
            throw ValidationError("Specify exactly one of --exists, --missing, --change, or --predicate")
        default:
            throw ValidationError("Specify exactly one of --exists, --missing, --change, or --predicate")
        }
    }

    private static func heistValue(from predicate: AccessibilityPredicate) throws -> HeistValue {
        let data = try JSONEncoder().encode(predicate)
        return try JSONDecoder().decode(HeistValue.self, from: data)
    }
}

private enum WaitPredicateSource {
    case accessibilityPredicate(AccessibilityPredicate)
    case rawPredicate(String)
}

enum WaitPresenceKind: String, EnumerableFlag {
    case exists
    case missing

    func predicate(element: ElementTargetOptions) throws -> AccessibilityPredicate {
        guard let elementPredicate = try element.parsedMatcher() else {
            throw ValidationError("--exists/--missing require element fields (e.g. -l, --identifier)")
        }
        switch self {
        case .exists:
            return .state(.exists(elementPredicate))
        case .missing:
            return .state(.missing(elementPredicate))
        }
    }
}

private extension WaitChangeKind {
    func predicate(element: ElementTargetOptions) throws -> AccessibilityPredicate {
        switch self {
        case .screen:
            return .change(.screenChanged)
        case .elements:
            return .change(.elements())
        case .updated:
            return .change(.elements(.updatedElement(ElementUpdatePredicate(element: try element.parsedMatcher()))))
        }
    }
}
