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
        let command: String
        var request: [String: Any]
        let verb: String

        switch type.lowercased() {
        case "increment":
            _ = try element.requireTarget()
            command = TheFence.Command.increment.rawValue
            request = ["command": command]
            element.applyTo(&request)
            verb = "Increment"
        case "decrement":
            _ = try element.requireTarget()
            command = TheFence.Command.decrement.rawValue
            request = ["command": command]
            element.applyTo(&request)
            verb = "Decrement"
        case "custom":
            _ = try element.requireTarget()
            guard let actionName = customAction else {
                throw ValidationError("--custom-action required for type 'custom'")
            }
            command = TheFence.Command.performCustomAction.rawValue
            request = ["command": command, "action": actionName]
            element.applyTo(&request)
            verb = "Custom action"
        case "edit":
            guard let editStr = editAction else {
                throw ValidationError("--edit-action required for type 'edit'. Valid: copy, paste, cut, select, select_all")
            }
            let normalizedStr = editStr.lowercased().replacingOccurrences(of: "_", with: "")
            guard let action = EditAction.allCases.first(where: { $0.rawValue.lowercased().replacingOccurrences(of: "_", with: "") == normalizedStr }) else {
                throw ValidationError("Unknown edit action: \(editStr). Valid: copy, paste, cut, select, select_all")
            }
            command = TheFence.Command.editAction.rawValue
            request = ["command": command, "action": action.rawValue]
            verb = action.rawValue
        case "dismiss_keyboard", "dismisskeyboard":
            command = TheFence.Command.dismissKeyboard.rawValue
            request = ["command": command]
            verb = "Dismiss keyboard"
        default:
            throw ValidationError(
                "Unknown action type: \(type). Valid: increment, decrement, custom, edit, dismiss_keyboard"
            )
        }

        request["timeout"] = timeout

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Sending \(verb.lowercased())..."
        )
    }
}
