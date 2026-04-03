import ArgumentParser
import ButtonHeist
import Foundation

struct StartScriptCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start-script",
        abstract: "Start recording a playback script (.heist file)"
    )

    @Option(name: .long, help: "Bundle ID of the app being recorded")
    var app: String = "com.buttonheist.testapp"

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .auto

    @ButtonHeistActor
    func run() async throws {
        let request: [String: Any] = [
            "command": TheFence.Command.startScript.rawValue,
            "app": app,
        ]
        try await CLIRunner.run(
            connection: connection,
            format: format,
            request: request
        )
    }
}
