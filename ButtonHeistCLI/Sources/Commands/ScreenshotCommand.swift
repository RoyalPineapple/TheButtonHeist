import ArgumentParser
import Foundation
import ButtonHeist

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
        var request: CLIRequestParameters = [:]
        if let outputPath = output {
            request.set(.output, outputPath)
        }
        if inline {
            request.set(.inlineData, true)
        }

        if output != nil || !inline {
            try await CLIRunner.run(
                connection: connection,
                format: .human,
                command: Self.fenceCommand,
                arguments: Self.fenceArguments(request),
                statusMessage: "Requesting screenshot..."
            )
        } else {
            let (fence, response) = try await CLIRunner.execute(
                connection: connection,
                command: Self.fenceCommand,
                arguments: Self.fenceArguments(request),
                statusMessage: "Requesting screenshot..."
            )
            defer { fence.stop() }

            if case .screenshotData(let payload, _) = response {
                guard let data = Data(base64Encoded: payload.pngData) else {
                    throw ValidationError("Failed to decode screenshot data")
                }
                FileHandle.standardOutput.write(data)
            } else {
                CLIRunner.outputResponse(response, format: .human)
            }
        }
    }
}
