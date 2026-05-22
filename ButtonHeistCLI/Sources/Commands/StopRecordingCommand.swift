import ArgumentParser
import ButtonHeist

struct StopRecordingCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Stop an in-progress screen recording"
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var outputFormat: OutputOptions

    @Option(name: .shortAndLong, help: "Output file path (default: generated artifact path)")
    var output: String?

    @Flag(name: .long, help: "Include base64 MP4 data in JSON output")
    var inlineData = false

    @Flag(name: .long, help: "Include the full interaction log in JSON output")
    var includeInteractionLog = false

    @ButtonHeistActor
    func run() async throws {
        var request = Self.fenceRequest()
        if let output {
            request.set(.output, output)
        }
        if inlineData {
            request.set(.inlineData, true)
        }
        if includeInteractionLog {
            request.set(.includeInteractionLog, true)
        }

        try await CLIRunner.run(
            connection: connection,
            format: outputFormat.format,
            request: request,
            statusMessage: "Stopping recording..."
        )
    }
}
