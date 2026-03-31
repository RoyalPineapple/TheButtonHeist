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
              buttonheist activate btn_login
              buttonheist activate -l "Sign In" -id loginButton
              buttonheist activate -l "Submit" --traits button
            """
    )

    @OptionGroup var element: ElementTargetOptions
    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        _ = try element.requireTarget()
        var request: [String: Any] = ["command": TheFence.Command.activate.rawValue]
        try element.applyTo(&request)
        request["timeout"] = timeout
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Activating element..."
        )
    }
}
