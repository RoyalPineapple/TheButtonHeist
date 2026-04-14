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

            Pass --action to invoke a named action instead of the default \
            activation: "increment", "decrement", or any custom action from \
            the element's actions array.

            For raw coordinate-based taps without accessibility semantics, \
            use `buttonheist one_finger_tap` instead.

            Examples:
              buttonheist activate btn_login
              buttonheist activate -l "Sign In" -id loginButton
              buttonheist activate -l "Submit" --traits button
              buttonheist activate btn_slider --action increment
              buttonheist activate btn_cell --action "Delete"
            """
    )

    @OptionGroup var element: ElementTargetOptions
    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @Option(name: .long, help: "Named action: increment, decrement, or a custom action name from the element's actions array")
    var action: String?

    @ButtonHeistActor
    mutating func run() async throws {
        _ = try element.requireTarget()

        let command: String
        var request: [String: Any]

        if let action {
            switch action.lowercased() {
            case "increment":
                command = TheFence.Command.increment.rawValue
                request = ["command": command]
            case "decrement":
                command = TheFence.Command.decrement.rawValue
                request = ["command": command]
            default:
                command = TheFence.Command.performCustomAction.rawValue
                request = ["command": command, "action": action]
            }
        } else {
            command = TheFence.Command.activate.rawValue
            request = ["command": command]
        }

        try element.applyTo(&request)
        request["timeout"] = timeout

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: action.map { "Sending \($0)..." } ?? "Activating element..."
        )
    }
}
