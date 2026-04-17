import ArgumentParser
import ButtonHeist
import Foundation

struct StartHeistCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start_heist",
        abstract: "Start recording a heist playback (.heist file)"
    )

    @Option(name: .long, help: "Bundle ID of the app being recorded")
    var app: String = Defaults.demoAppBundleID

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .auto

    @ButtonHeistActor
    func run() async throws {
        let request: [String: Any] = [
            "command": TheFence.Command.startHeist.rawValue,
            "app": app,
        ]
        try await CLIRunner.run(
            connection: connection,
            format: format,
            request: request
        )
    }
}
