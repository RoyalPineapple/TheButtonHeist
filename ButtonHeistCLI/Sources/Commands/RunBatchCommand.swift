import ArgumentParser
import ButtonHeist
import Foundation

struct RunBatchCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Execute a batch of Button Heist steps from a JSON payload",
        discussion: """
            Reads a steps array (`[{ "command": "activate", "heistId": "…" }, …]`)
            either inline via --steps or from a JSON file. Each step is a full
            Button Heist request dictionary as produced by get_interface / session
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
        let batchSteps = try Self.serializedBatchSteps(inline: steps, fromFile: stepsFromFile)

        var request = Self.fenceRequest([.steps: .array(batchSteps.map(\.value))])
        if let policy {
            guard let parsedPolicy = Self.catalogCanonicalStringValue(policy, for: .policy, caseInsensitive: false) else {
                throw ValidationError("Invalid policy '\(policy)'. Valid: \(Self.catalogAllowedValuesDescription(for: .policy))")
            }
            request.set(.policy, .string(parsedPolicy))
        }
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Running batch..."
        )
    }

    static func serializedBatchSteps(inline: String?, fromFile path: String?) throws -> [SerializedBatchStep] {
        try loadJSONArray(
            inline: inline,
            fromFile: path,
            optionName: "steps"
        ).enumerated().map { index, value in
            try SerializedBatchStep(value: value, index: index)
        }
    }
}

struct SerializedBatchStep {
    let value: HeistValue

    init(value: HeistValue, index: Int) throws {
        guard case .object = value else {
            throw ValidationError("steps[\(index)] must be a JSON object")
        }
        self.value = value
    }
}
