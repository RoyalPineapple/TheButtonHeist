import ArgumentParser
import ButtonHeist

struct WaitForChangeCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Wait for the UI to change, optionally matching an expectation"
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Maximum wait time in seconds (default: 30, max: 30)")
    var timeout: Double = 30.0

    @Option(name: .shortAndLong, help: "Expected change shorthand or JSON object-form expectation")
    var expect: String?

    @ButtonHeistActor
    mutating func run() async throws {
        var request = Self.fenceRequest([.timeout: .double(timeout)])
        if let expect {
            request.set(.expect, try ExpectationArgumentParser.parse(expect))
        }
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Waiting for change..."
        )
    }
}
