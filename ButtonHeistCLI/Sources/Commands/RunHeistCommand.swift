import ArgumentParser
import ButtonHeist
import Foundation

struct RunHeistCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Execute a canonical Button Heist plan from a JSON payload",
        discussion: """
            Reads a canonical heist plan object either inline via --plan or
            from a JSON file via --plan-from-file. The top-level object fields
            are sent as the run_heist command arguments.

            Examples:
              buttonheist run_heist --plan-from-file plan.json
              buttonheist run_heist --plan '{"version":1,"steps":[{"type":"warn","warn":{"message":"Check login state"}}]}'
            """
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "Inline canonical heist plan JSON object")
    var plan: String?

    @Option(name: .long, help: "Path to a JSON file containing a canonical heist plan object")
    var planFromFile: String?

    @ButtonHeistActor
    mutating func run() async throws {
        let request = try Self.planArguments(inline: plan, fromFile: planFromFile)
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: Self.fenceCommand,
            arguments: Self.fenceArguments(request),
            statusMessage: "Running heist..."
        )
    }

    static func planArguments(inline: String?, fromFile path: String?) throws -> CLIRequestParameters {
        let fields = try loadJSONObject(
            inline: inline,
            fromFile: path,
            optionName: "plan"
        )
        var request: CLIRequestParameters = [:]
        for (field, value) in fields {
            guard let key = FenceParameterKey(rawValue: field) else {
                throw ValidationError("plan contains an invalid empty field name")
            }
            request.set(key, value)
        }
        return request
    }
}
