import ArgumentParser
import ButtonHeist

struct ActivateCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Activate a UI element (primary interaction command)",
        discussion: """
            This is the primary way to interact with UI elements. It uses an \
            semantic actionability path: resolves the element, reveals it when \
            needed, acquires fresh accessibility geometry, then dispatches the \
            primary activation policy.

            Pass --action to invoke a named action instead of the default \
            activation: "increment", "decrement", or any custom action from \
            the element's actions array.

            For explicit coordinate-based taps, \
            use `buttonheist one_finger_tap` instead.

            Examples:
              buttonheist activate btn_login
              buttonheist activate -l "Sign In" --identifier loginButton
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
        let target = try element.requireTarget()

        var request: CLIRequestParameters = [:]
        if let action {
            request.set(.action, action)
        }

        request.set(.timeout, timeoutOption.timeout)

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            operation: try Self.fenceOperation(request, target: target),
            statusMessage: action.map { "Sending \($0)..." } ?? "Activating element..."
        )
    }
}
