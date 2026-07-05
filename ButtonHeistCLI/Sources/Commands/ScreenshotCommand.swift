import ArgumentParser
import Foundation
@_spi(ButtonHeistTooling) import ButtonHeist

struct ScreenshotCommand: AsyncParsableCommand, CLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Capture a screenshot from the connected device"
    )

    @OptionGroup var destination: ScreenshotDestinationInput

    @OptionGroup var connection: ConnectionOptions

    @ButtonHeistActor
    func run() async throws {
        let commandResultMapper: CLIRunner.CommandResultMapper?
        if destination.inline {
            commandResultMapper = Self.inlineCommandResult(for:)
        } else {
            commandResultMapper = nil
        }
        try await CLIRunner.run(
            connection: connection,
            format: .human,
            command: Self.fenceCommand,
            arguments: requestArguments(),
            statusMessage: "Requesting screenshot...",
            result: commandResultMapper
        )
    }

    func requestArguments() throws -> TheFence.CommandArgumentEnvelope {
        Self.fenceArguments(CommandArgumentWriter.parameters(try destination.argumentFields()))
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

struct ScreenshotDestinationInput: ParsableArguments {
    @Option(name: .shortAndLong, help: "Output file path (default: generated artifact path)")
    var output: String?

    @Flag(name: .long, help: "Write raw PNG bytes to stdout")
    var inline = false

    @Flag(name: .long, help: "Render accessibility markers and legend instead of the raw screenshot")
    var accessibility = false

    mutating func validate() throws {
        _ = try argumentFields()
    }

    func argumentFields() throws -> [CommandArgumentWriter.Field] {
        switch (inline, output) {
        case (true, nil):
            return [
                CommandArgumentWriter.value(.inlineData, true),
                CommandArgumentWriter.optional(.mode, accessibility ? ScreenCaptureMode.accessibility.rawValue : nil),
            ].compactMap { $0 }
        case (false, let output):
            return [
                CommandArgumentWriter.optional(.output, output),
                CommandArgumentWriter.optional(.mode, accessibility ? ScreenCaptureMode.accessibility.rawValue : nil),
            ].compactMap { $0 }
        case (true, .some):
            throw ValidationError("--inline cannot be used with --output")
        }
    }
}
