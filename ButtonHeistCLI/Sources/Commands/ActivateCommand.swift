import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist

struct ActivateCommand: ConnectedOneShotCLICommand {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Perform primary accessibility activation on a semantic UI element",
        discussion: """
            This is the primary way to interact with UI elements. It uses the \
            element inflation path: resolves the element, reveals it when \
            needed, acquires fresh accessibility geometry, then dispatches the \
            primary accessibility activation policy.

            Pass --action to invoke a named action instead of the default \
            activation: "increment", "decrement", or any custom action from \
            the element's actions array.

            For explicit mechanical or spatial gestures, use the gesture \
            commands such as `buttonheist one_finger_tap`.

            Examples:
              buttonheist activate -l "Log In"
              buttonheist activate -l "Sign In" --identifier loginButton
              buttonheist activate -l "Submit" --traits button
              buttonheist activate -l "Volume" --action increment
              buttonheist activate -l "Inbox" --action "Delete"
            """
    )

    @OptionGroup var element: AccessibilityTargetOptions
    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions
    @OptionGroup var timeoutOption: TimeoutOption

    @Option(name: .long, help: "Named action: increment, decrement, or a custom action name from the element's actions array")
    var action: String?

    var runnerStatusMessage: String? {
        action.map { "Sending \($0)..." } ?? "Activating element..."
    }

    func requestArguments() throws -> TheFence.CommandArgumentEnvelope {
        let target = try element.requireTarget()
        return Self.fenceArguments(
            target: target,
            CommandArgumentEnvelopeBuilder.optional(.action, action),
            CommandArgumentEnvelopeBuilder.value(.timeout, timeoutOption.timeout)
        )
    }
}
