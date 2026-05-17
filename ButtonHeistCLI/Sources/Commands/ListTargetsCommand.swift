import ArgumentParser
import ButtonHeist

struct ListTargetsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: TheFence.Command.listTargets.rawValue,
        abstract: "List device targets defined in .buttonheist.json",
        discussion: """
            Returns every named target from the resolved .buttonheist.json
            config along with the default target, or an empty list if no
            config was found.

            Examples:
              buttonheist list_targets
              buttonheist list_targets --format json
            """
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    mutating func run() async throws {
        let request: [String: Any] = [
            "command": TheFence.Command.listTargets.rawValue,
        ]
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request
        )
    }
}
