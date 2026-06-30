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

    @OptionGroup var element: ElementTargetOptions

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Maximum wait time in seconds (default: 10, max: 30)")
    var timeout: Double = 10.0

    @Flag(name: .long, help: "Wait for an element matching the element fields to exist")
    var exists: Bool = false

    @Flag(name: .long, help: "Wait for an element matching the element fields to be missing")
    var missing: Bool = false

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Wait for a change: a discriminator (screen, elements, updated)"
        )
    )
    var change: String?

    @Option(name: .long, help: "Full predicate as a JSON object (overrides --exists/--missing/--change)")
    var predicate: String?

    func validate() throws {
        guard timeout > 0 && timeout <= 30 else {
            throw ValidationError("timeout must be greater than 0 and at most 30 seconds, got \(timeout)")
        }
        let modes = [exists, missing, change != nil, predicate != nil].filter { $0 }.count
        guard modes == 1 else {
            throw ValidationError("Specify exactly one of --exists, --missing, --change, or --predicate")
        }
    }

    @ButtonHeistActor
    mutating func run() async throws {
        let predicateValue = try resolvedPredicateValue()
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: Self.fenceCommand,
            arguments: Self.fenceArguments(
                CommandArgumentWriter.value(.timeout, timeout),
                CommandArgumentWriter.value(.predicate, predicateValue)
            ),
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
        if exists || missing {
            guard let elementPredicate = try element.parsedMatcher() else {
                throw ValidationError("--exists/--missing require element fields (e.g. -l, --identifier)")
            }
            return exists ? .state(.exists(elementPredicate)) : .state(.missing(elementPredicate))
        }
        guard let change else {
            throw ValidationError("Specify exactly one of --exists, --missing, --change, or --predicate")
        }
        switch change {
        case "screen":
            return .change(.screen())
        case "elements":
            return .change(.elements())
        case "updated":
            return .change(.elements(.updatedElement(ElementUpdatePredicate(element: try element.parsedMatcher()))))
        default:
            throw ValidationError(
                "Unknown --change value \"\(change)\". Valid: screen, elements, updated"
            )
        }
    }

    private static func heistValue(from predicate: AccessibilityPredicate) throws -> HeistValue {
        let data = try JSONEncoder().encode(predicate)
        return try JSONDecoder().decode(HeistValue.self, from: data)
    }
}
