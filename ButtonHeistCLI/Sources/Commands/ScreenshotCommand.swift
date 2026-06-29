import ArgumentParser
import Foundation
@_spi(ButtonHeistTooling) import ButtonHeist

struct ScreenshotCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Capture a screenshot from the connected device"
    )

    @Option(name: .shortAndLong, help: "Output file path (default: generated artifact path)")
    var output: String?

    @Flag(name: .long, help: "Write raw PNG bytes to stdout")
    var inline = false

    @OptionGroup var connection: ConnectionOptions

    func validate() throws {
        if inline && output != nil {
            throw ValidationError("--inline cannot be used with --output")
        }
    }

    @ButtonHeistActor
    func run() async throws {
        var request = CLIRequestParameters()
        if let outputPath = output {
            request.set(.output, outputPath)
        }
        if inline {
            request.set(.inlineData, true)
        }

        let commandResultMapper: CLIRunner.CommandResultMapper?
        if inline {
            commandResultMapper = Self.inlineCommandResult(for:)
        } else {
            commandResultMapper = nil
        }
        try await CLIRunner.run(
            connection: connection,
            format: .human,
            command: Self.fenceCommand,
            arguments: Self.fenceArguments(request),
            statusMessage: "Requesting screenshot...",
            result: commandResultMapper
        )
    }

    static func inlineCommandResult(for response: FenceResponse) throws -> CLIRunner.CommandResult {
        guard case .screenshotData(let payload, _) = response else {
            return .response(CLIRunner.FormattedResponse(response: response, format: .human))
        }
        guard let data = Data(base64Encoded: payload.pngData) else {
            throw ValidationError("Failed to decode screenshot data")
        }
        return .binary(data)
    }
}
