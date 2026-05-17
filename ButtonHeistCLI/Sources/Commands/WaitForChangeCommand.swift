import ArgumentParser
import ButtonHeist

struct WaitForChangeCommand: AsyncParsableCommand, CLICommandContract {
    static let fenceCommand = TheFence.Command.waitForChange

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Wait for the UI to change, optionally matching an expectation"
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Maximum wait time in seconds (default: 10, max: 30)")
    var timeout: Double = 10.0

    @Option(name: .shortAndLong, help: "Expected change shorthand or JSON object-form expectation")
    var expect: String?

    @ButtonHeistActor
    mutating func run() async throws {
        var request = Self.fenceRequest(["timeout": timeout])
        if let expect {
            request["expect"] = try ExpectationArgumentParser.parse(expect)
        }
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Waiting for change..."
        )
    }
}
