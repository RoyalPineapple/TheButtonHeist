import ArgumentParser
import ButtonHeist
import Foundation

struct StartHeistCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Start recording deterministic heist steps"
    )

    @Option(name: .long, help: "Bundle ID of the app being recorded")
    var app: String = Defaults.demoAppBundleID

    @OptionGroup var connection: ConnectionOptions

    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    func run() async throws {
        let request: CLIRequestParameters = [.app: .string(app)]
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: Self.fenceCommand,
            arguments: Self.fenceArguments(request)
        )
    }
}
