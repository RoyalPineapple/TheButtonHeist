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
              buttonheist list                          # Show available devices
              buttonheist session                       # Interactive session
              buttonheist action --identifier "myButton"
              buttonheist touch tap --x 100 --y 200
            """,
        version: buttonHeistVersion,
        subcommands: [ListCommand.self, ActionCommand.self,
                       TouchCommand.self, TypeCommand.self, ScreenshotCommand.self,
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
