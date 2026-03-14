import ArgumentParser
import ButtonHeist
import Foundation

@main
struct ButtonHeistApp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "buttonheist",
        abstract: "Inspect and interact with iOS app UI elements.",
        discussion: """
            Quick start — the five commands you need most:
              buttonheist list                              # Find devices
              buttonheist get_interface                     # Inspect UI hierarchy
              buttonheist activate --identifier "myButton"  # Tap a control
              buttonheist type --text "hello"               # Type text
              buttonheist screenshot                        # Capture screen

            Use `buttonheist session` for an interactive REPL with all commands.
            """,
        version: buttonHeistVersion,
        subcommands: [
            // Primary — what you need 90% of the time
            ListCommand.self,
            GetInterfaceCommand.self,
            ActivateCommand.self,
            TypeCommand.self,
            ScreenshotCommand.self,
            ScrollCommand.self,
            SessionCommand.self,

            // Navigation
            ScrollToVisibleCommand.self,
            ScrollToEdgeCommand.self,

            // Accessibility & text editing
            ActionCommand.self,
            EditCommand.self,
            DismissKeyboardCommand.self,

            // Gestures
            TouchCommand.self,

            // Recording & diagnostics
            RecordCommand.self,
            StopRecordingCommand.self,
            WaitForIdleCommand.self,
        ]
    )
}

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case human
    case json

    static var auto: OutputFormat {
        isatty(STDIN_FILENO) != 0 ? .human : .json
    }
}
