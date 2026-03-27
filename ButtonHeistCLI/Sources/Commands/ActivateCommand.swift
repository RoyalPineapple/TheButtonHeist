import ArgumentParser
import ButtonHeist

struct ActivateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activate",
        abstract: "Activate a UI element (primary interaction command)",
        discussion: """
            This is the primary way to interact with UI elements. It uses an \
            accessibility-first pattern: tries accessibilityActivate() (like \
            VoiceOver) first, then falls back to a synthetic tap at the \
            element's activation point.

            For raw coordinate-based taps without accessibility semantics, \
            use `buttonheist touch one_finger_tap` instead.

            Examples:
              buttonheist activate --identifier loginButton
              buttonheist activate --index 3
            """
    )

    @OptionGroup var element: ElementTargetOptions
    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        let target = try element.requireTarget()

        let connector = DeviceConnector(deviceFilter: connection.device, token: connection.token, quiet: connection.quiet)
        try await connector.connect()
        defer { connector.disconnect() }

        if !connection.quiet {
            logStatus("Activating element...")
        }

        connector.send(.activate(target))

        let result = try await connector.waitForActionResult(timeout: timeout)
        outputActionResult(result, format: output.format, quiet: connection.quiet, verb: "Activate")
    }
}
