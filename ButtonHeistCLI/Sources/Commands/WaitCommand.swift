import ArgumentParser
import ButtonHeist
import Foundation

struct WaitCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Wait until an accessibility predicate is satisfied",
        discussion: """
            Waits until an accessibility predicate becomes true. `--present`/`--absent` \
            poll the current interface for an element matching the supplied element \
            fields; `--changed` rides settled UI transitions. Uses settle-event \
            polling, not busy-waiting. Timeout is capped at 30 seconds.

            Examples:
              buttonheist wait --present -l "Welcome"
              buttonheist wait --absent -l "Loading" -t 5
              buttonheist wait --changed screen_changed
              buttonheist wait --predicate '{"type":"present","element":{"label":"Done"}}'
            """
    )

    @OptionGroup var element: ElementTargetOptions

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Maximum wait time in seconds (default: 10, max: 30)")
    var timeout: Double = 10.0

    @Flag(name: .long, help: "Wait for an element matching the element fields to be present")
    var present: Bool = false

    @Flag(name: .long, help: "Wait for an element matching the element fields to be absent")
    var absent: Bool = false

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Wait for a change: a discriminator (screen_changed, elements_changed, "
                + "element_updated)"
        )
    )
    var changed: String?

    @Option(name: .long, help: "Full predicate as a JSON object (overrides --present/--absent/--changed)")
    var predicate: String?

    func validate() throws {
        guard timeout > 0 && timeout <= 30 else {
            throw ValidationError("timeout must be greater than 0 and at most 30 seconds, got \(timeout)")
        }
        let modes = [present, absent, changed != nil, predicate != nil].filter { $0 }.count
        guard modes == 1 else {
            throw ValidationError("Specify exactly one of --present, --absent, --changed, or --predicate")
        }
    }

    @ButtonHeistActor
    mutating func run() async throws {
        let predicateValue = try resolvedPredicateValue()
        let request: CLIRequestParameters = [
            .timeout: .double(timeout),
            .predicate: predicateValue,
        ]
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: Self.fenceCommand,
            arguments: Self.fenceArguments(request),
            statusMessage: "Waiting for predicate..."
        )
    }

    private func resolvedPredicateValue() throws -> HeistValue {
        if let predicate {
            return try TheFence.parseExpectationArgument(predicate)
        }
        let accessibilityPredicate = try buildPredicate()
        return try Self.heistValue(from: accessibilityPredicate)
    }

    private func buildPredicate() throws -> AccessibilityPredicate {
        if present || absent {
            guard let elementPredicate = try element.parsedMatcher() else {
                throw ValidationError("--present/--absent require element fields (e.g. -l, --identifier)")
            }
            return present ? .state(.present(elementPredicate)) : .state(.absent(elementPredicate))
        }
        guard let changed else {
            throw ValidationError("Specify exactly one of --present, --absent, --changed, or --predicate")
        }
        switch changed {
        case "screen_changed":
            return .changed(.screen())
        case "elements_changed":
            return .changed(.elements)
        case "element_updated":
            return .changed(.updated(ElementUpdatePredicate(element: try element.parsedMatcher())))
        default:
            throw ValidationError(
                "Unknown --changed value \"\(changed)\". Valid: "
                    + AccessibilityPredicate.wireTypeValues.joined(separator: ", ")
            )
        }
    }

    private static func heistValue(from predicate: AccessibilityPredicate) throws -> HeistValue {
        let data = try JSONEncoder().encode(predicate)
        return try JSONDecoder().decode(HeistValue.self, from: data)
    }
}
