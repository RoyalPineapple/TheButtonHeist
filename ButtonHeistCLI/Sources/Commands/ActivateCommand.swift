import ArgumentParser
import ButtonHeist

struct ActivateCommand: AsyncParsableCommand, CLICommandContract {
    static var fenceCommand: TheFence.Command {
        TheFence.Command.activationAlias(forActionName: nil).command
    }

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
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
    @OptionGroup var timeoutOption: TimeoutOption

    @Option(name: .long, help: "Named action: increment, decrement, or a custom action name from the element's actions array")
    var action: String?

    @ButtonHeistActor
    mutating func run() async throws {
        _ = try element.requireTarget()

        let commandAlias = TheFence.Command.activationAlias(forActionName: action)
        var request = commandAlias.command.cliRequest(commandAlias.parameters)

        try element.applyTo(&request)
        request.set(.timeout, timeoutOption.timeout)

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: action.map { "Sending \($0)..." } ?? "Activating element..."
        )
    }
}
