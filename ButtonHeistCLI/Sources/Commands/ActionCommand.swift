import ArgumentParser
import ButtonHeist

struct ActionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "action",
        abstract: "Perform accessibility actions on UI elements",
        discussion: """
            Specialized accessibility actions. For tapping buttons and controls, \
            use `buttonheist activate` instead.

            Action types:
              increment / decrement  — Adjust sliders, steppers, pickers
              custom                 — Trigger a named custom action
              edit                   — Clipboard operations (copy, paste, cut, select, select_all)
              dismiss_keyboard       — Resign first responder

            Examples:
              buttonheist action --type increment --identifier volumeSlider
              buttonheist action --type decrement --identifier volumeSlider
              buttonheist action --type custom --identifier myCell --custom-action "Delete"
              buttonheist action --type edit --edit-action copy
              buttonheist action --type dismiss_keyboard
            """
    )

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .long, help: "Action type: increment, decrement, custom, edit, dismiss_keyboard")
    var type: String

    @Option(name: .long, help: "Custom action name (for type 'custom')")
    var customAction: String?

    @Option(name: .long, help: "Edit action: copy, paste, cut, select, select_all (for type 'edit')")
    var editAction: String?

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        let connector = DeviceConnector(deviceFilter: connection.device, token: connection.token, quiet: connection.quiet)
        try await connector.connect()
        defer { connector.disconnect() }

        let message: ClientMessage
        let verb: String

        switch type.lowercased() {
        case "increment":
            let target = try element.requireTarget()
            message = .increment(target)
            verb = "Increment"
        case "decrement":
            let target = try element.requireTarget()
            message = .decrement(target)
            verb = "Decrement"
        case "custom":
            let target = try element.requireTarget()
            guard let actionName = customAction else {
                throw ValidationError("--custom-action required for type 'custom'")
            }
            message = .performCustomAction(CustomActionTarget(
                elementTarget: target,
                actionName: actionName
            ))
            verb = "Custom action"
        case "edit":
            guard let editStr = editAction else {
                throw ValidationError("--edit-action required for type 'edit'. Valid: copy, paste, cut, select, select_all")
            }
            let normalizedStr = editStr.lowercased().replacingOccurrences(of: "_", with: "")
            guard let action = EditAction.allCases.first(where: { $0.rawValue.lowercased().replacingOccurrences(of: "_", with: "") == normalizedStr }) else {
                throw ValidationError("Unknown edit action: \(editStr). Valid: copy, paste, cut, select, select_all")
            }
            message = .editAction(EditActionTarget(action: action))
            verb = action.rawValue
        case "dismiss_keyboard", "dismisskeyboard":
            message = .resignFirstResponder
            verb = "Dismiss keyboard"
        default:
            throw ValidationError(
                "Unknown action type: \(type). Valid: increment, decrement, custom, edit, dismiss_keyboard"
            )
        }

        if !connection.quiet {
            logStatus("Sending \(verb.lowercased())...")
        }

        connector.send(message)

        let result = try await connector.waitForActionResult(timeout: timeout)
        outputActionResult(result, format: output.format, quiet: connection.quiet, verb: verb)
    }
}
