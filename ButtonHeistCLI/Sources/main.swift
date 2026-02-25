import ArgumentParser
import Foundation

@main
struct ButtonHeist: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "buttonheist",
        abstract: "Inspect and interact with iOS app UI elements.",
        discussion: """
            Connects to an iOS app and displays the UI element hierarchy. Useful for
            testing, debugging, and automation of SwiftUI/UIKit apps.

            Examples:
              buttonheist list                          # Show available devices
              buttonheist watch --once                  # Single snapshot, then exit
              buttonheist --device a1b2 watch --once    # Target a specific instance
              buttonheist action --identifier "myButton"
              buttonheist touch tap --x 100 --y 200
            """,
        version: "2.1.0",
        subcommands: [ListCommand.self, WatchCommand.self, ActionCommand.self,
                       TouchCommand.self, TypeCommand.self, ScreenshotCommand.self,
                       SessionCommand.self,
                       RecordCommand.self, StopRecordingCommand.self,
                       CopyCommand.self, PasteCommand.self, CutCommand.self,
                       SelectCommand.self, SelectAllCommand.self,
                       DismissKeyboardCommand.self],
        defaultSubcommand: WatchCommand.self
    )
}

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case human
    case json

    static var auto: OutputFormat {
        isatty(STDIN_FILENO) != 0 ? .human : .json
    }
}

struct CLIOptions {
    let format: OutputFormat
    let once: Bool
    let quiet: Bool
    let timeout: Int
    let verbose: Bool
    let device: String?
    let force: Bool
    let token: String?
}
