import ArgumentParser
import ButtonHeist
import Foundation

@main
struct ButtonHeistApp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "buttonheist",
        abstract: "Inspect and interact with iOS app UI elements.",
        discussion: """
            Connects to an iOS app and provides commands for inspecting the UI element
            hierarchy, performing actions, and automating SwiftUI/UIKit apps.

            Examples:
              buttonheist activate --identifier "myButton"  # Activate element
              buttonheist list                              # Show available devices
              buttonheist session                           # Interactive session
              buttonheist touch one_finger_tap --x 100 --y 200  # Low-level tap
            """,
        version: buttonHeistVersion,
        subcommands: [ActivateCommand.self, ListCommand.self, ActionCommand.self,
                       ScrollCommand.self, ScrollToVisibleCommand.self, ScrollToEdgeCommand.self,
                       TouchCommand.self, TypeCommand.self, ScreenshotCommand.self,
                       GetInterfaceCommand.self, WaitForIdleCommand.self,
                       SessionCommand.self,
                       RecordCommand.self, StopRecordingCommand.self,
                       CopyCommand.self, PasteCommand.self, CutCommand.self,
                       SelectCommand.self, SelectAllCommand.self,
                       DismissKeyboardCommand.self]
    )
}

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case human
    case json

    static var auto: OutputFormat {
        isatty(STDIN_FILENO) != 0 ? .human : .json
    }
}
