import ArgumentParser
import ButtonHeist
import Foundation

@main
struct ButtonHeistApp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "buttonheist",
        abstract: "Inspect and interact with iOS app UI elements.",
        discussion: """
            Common starter flow:
              buttonheist list_devices                      # Find devices
              buttonheist get_interface                     # Inspect UI hierarchy
              buttonheist activate --heist-id myButton      # Tap a control
              buttonheist type_text "hello"                 # Type text
              buttonheist get_screen                        # Capture screen

            Use `buttonheist session` for a persistent JSON command session, or read the generated command reference for the full command contract.
            """,
        version: buttonHeistVersion,
        subcommands: CLICommandAdapterCatalog.subcommands
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
