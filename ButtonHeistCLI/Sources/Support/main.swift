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
              buttonheist list_devices                      # Find devices
              buttonheist get_interface                     # Inspect UI hierarchy
              buttonheist activate --identifier "myButton"  # Tap a control
              buttonheist type_text "hello"                 # Type text
              buttonheist get_screen                        # Capture screen

            Use `buttonheist session` for an interactive REPL with all commands.
            """,
        version: buttonHeistVersion,
        subcommands: [
            // Primary — what you need 90% of the time
            ListCommand.self,
            GetInterfaceCommand.self,
            ActivateCommand.self,
            RotorCommand.self,
            TypeCommand.self,
            ScreenshotCommand.self,
            ScrollCommand.self,
            SwipeSubcommand.self,
            SessionCommand.self,
            ConnectCommand.self,

            // Navigation
            ScrollToVisibleCommand.self,
            ElementSearchCommand.self,
            ScrollToEdgeCommand.self,

            // Edit & keyboard
            EditActionCommand.self,
            DismissKeyboardCommand.self,

            // Gestures
            TapSubcommand.self,
            LongPressSubcommand.self,
            DragSubcommand.self,
            PinchSubcommand.self,
            RotateSubcommand.self,
            TwoFingerTapSubcommand.self,
            DrawPathCommand.self,
            DrawBezierCommand.self,

            // Pasteboard
            SetPasteboardCommand.self,
            GetPasteboardCommand.self,

            // Recording & diagnostics
            RecordCommand.self,
            StopRecordingCommand.self,
            WaitForChangeCommand.self,
            WaitForCommand.self,

            // Session management
            SessionLogCommand.self,
            ArchiveSessionCommand.self,
            GetSessionStateCommand.self,
            ListTargetsCommand.self,
            RunBatchCommand.self,

            // Heist recording & playback
            StartHeistCommand.self,
            StopHeistCommand.self,
            PlayHeistCommand.self,
        ]
    )
}

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case human
    case json
    case compact

    static var auto: OutputFormat {
        isatty(STDIN_FILENO) != 0 ? .human : .json
    }
}
