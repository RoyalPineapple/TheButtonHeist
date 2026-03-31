import ArgumentParser
import ButtonHeist

struct ActionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "action",
        abstract: "Perform accessibility actions on UI elements",
        discussion: """
            Smart dispatch: increment and decrement are recognized as built-in \
            actions, copy/paste/cut/select/select_all as edit actions, \
            dismiss_keyboard as a system action, and everything else is treated \
            as a custom action name.

            Use --custom to force custom action interpretation when the name \
            collides with a built-in (e.g. action --custom "increment").

            Examples:
              buttonheist action increment btn_slider
              buttonheist action decrement btn_slider
              buttonheist action "Delete" btn_cell
              buttonheist action copy
              buttonheist action dismiss_keyboard
              buttonheist action --custom "increment" btn_element
            """
    )

    @Argument(help: "Action: increment, decrement, copy, paste, cut, select, select_all, dismiss_keyboard, or custom action name")
    var action: String

    @Option(name: .long, help: "Force custom action interpretation (when name collides with a built-in)")
    var custom: String?

    @OptionGroup var element: ElementTargetOptions
    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        let command: String
        var request: [String: Any]
        let verb: String

        if let customName = custom {
            _ = try element.requireTarget()
            command = TheFence.Command.performCustomAction.rawValue
            request = ["command": command, "action": customName]
            try element.applyTo(&request)
            verb = "Custom action"
        } else {
            switch action.lowercased() {
            case "increment":
                _ = try element.requireTarget()
                command = TheFence.Command.increment.rawValue
                request = ["command": command]
                try element.applyTo(&request)
                verb = "Increment"
            case "decrement":
                _ = try element.requireTarget()
                command = TheFence.Command.decrement.rawValue
                request = ["command": command]
                try element.applyTo(&request)
                verb = "Decrement"
            case "dismiss_keyboard", "dismisskeyboard", "dismiss":
                command = TheFence.Command.dismissKeyboard.rawValue
                request = ["command": command]
                verb = "Dismiss keyboard"
            case "copy", "paste", "cut", "select", "select_all", "selectall":
                let normalizedAction = action.lowercased().replacingOccurrences(of: "_", with: "")
                guard let editAction = EditAction.allCases.first(where: {
                    $0.rawValue.lowercased().replacingOccurrences(of: "_", with: "") == normalizedAction
                }) else {
                    throw ValidationError("Unknown edit action: \(action). Valid: copy, paste, cut, select, select_all")
                }
                command = TheFence.Command.editAction.rawValue
                request = ["command": command, "action": editAction.rawValue]
                verb = editAction.rawValue
            default:
                _ = try element.requireTarget()
                command = TheFence.Command.performCustomAction.rawValue
                request = ["command": command, "action": action]
                try element.applyTo(&request)
                verb = "Custom action"
            }
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
