import ArgumentParser
import ButtonHeist
import Foundation

struct RunBatchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run_batch",
        abstract: "Execute a batch of TheFence steps from a JSON payload",
        discussion: """
            Reads a steps array (`[{ "command": "activate", "heistId": "…" }, …]`)
            either inline via --steps or from a JSON file. Each step is a full
            TheFence request dictionary as produced by get_interface / session
            JSON mode.

            Policy controls batch behavior on step failure: stop_on_error
            (default) halts on the first failure; continue_on_error runs the
            full list and reports per-step results.

            Examples:
              buttonheist run_batch --steps-from-file steps.json
              buttonheist run_batch --steps-from-file steps.json --policy continue_on_error
              buttonheist run_batch --steps '[{"command":"activate","heistId":"btn-OK"}]'
            """
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "Inline JSON array of step dictionaries")
    var steps: String?

    @Option(name: .long, help: "Path to a JSON file containing the steps array")
    var stepsFromFile: String?

    @Option(name: .long, help: "Batch policy: stop_on_error (default) or continue_on_error")
    var policy: String?

    @ButtonHeistActor
    mutating func run() async throws {
        let array = try loadJSONArray(inline: steps, fromFile: stepsFromFile, optionName: "steps")
        var request: [String: Any] = [
            "command": TheFence.Command.runBatch.rawValue,
            "steps": array,
        ]
        if let policy { request["policy"] = policy }
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Running batch..."
        )
    }
}
