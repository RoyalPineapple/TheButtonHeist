import ArgumentParser
import ButtonHeist

struct WaitForCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wait_for",
        abstract: "Wait for an element matching a predicate to appear or disappear",
        discussion: """
            Waits for an element matching the given predicate to appear (or \
            disappear with --absent). Uses settle-event polling, not busy-waiting. \
            Timeout is capped at 30 seconds.

            Examples:
              buttonheist wait_for --label "Loading" --absent --timeout 5
              buttonheist wait_for --label "Welcome" --traits staticText
              buttonheist wait_for --identifier login_button
            """
    )

    @Option(name: .long, help: "Accessibility identifier")
    var identifier: String?

    @Option(name: .long, help: "Accessibility label")
    var label: String?

    @Option(name: .long, help: "Accessibility value")
    var value: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Required traits (all must match)")
    var traits: [String] = []

    @Option(name: .customLong("exclude-traits"), parsing: .upToNextOption, help: "Excluded traits (none may be present)")
    var excludeTraits: [String] = []

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Maximum wait time in seconds (default: 10, max: 30)")
    var timeout: Double = 10.0

    @Flag(name: .long, help: "Wait for element to NOT exist (disappear)")
    var absent: Bool = false

    @ButtonHeistActor
    mutating func run() async throws {
        let hasFields = identifier != nil || label != nil || value != nil
            || !traits.isEmpty || !excludeTraits.isEmpty
        guard hasFields else {
            throw ValidationError("Must specify at least one match field (--label, --identifier, --value, or --traits)")
        }

        let matcher = ElementMatcher(
            label: label,
            identifier: identifier,
            value: value,
            traits: traits.isEmpty ? nil : traits,
            excludeTraits: excludeTraits.isEmpty ? nil : excludeTraits
        )

        let connector = DeviceConnector(deviceFilter: connection.device, token: connection.token, quiet: connection.quiet)
        try await connector.connect()
        defer { connector.disconnect() }

        if !connection.quiet {
            let verb = absent ? "disappear" : "appear"
            logStatus("Waiting for element to \(verb)...")
        }

        let waitTarget = WaitForTarget(match: matcher, absent: absent ? true : nil, timeout: timeout)
        connector.send(.waitFor(waitTarget))
        let result = try await connector.waitForActionResult(timeout: min(timeout, 30) + 5)
        outputActionResult(result, format: output.format, quiet: connection.quiet, verb: "Wait for")
    }
}
