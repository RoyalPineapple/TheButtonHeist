import ArgumentParser
import Foundation
import ButtonHeist

struct ScreenshotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: TheFence.Command.getScreen.rawValue,
        abstract: "Capture a screenshot from the connected device"
    )

    @Option(name: .shortAndLong, help: "Output file path (default: stdout as raw PNG)")
    var output: String?

    @OptionGroup var connection: ConnectionOptions

    @ButtonHeistActor
    func run() async throws {
        var request: [String: Any] = ["command": TheFence.Command.getScreen.rawValue]
        if let outputPath = output {
            request["output"] = outputPath
            try await CLIRunner.run(
                connection: connection,
                format: .human,
                request: request,
                statusMessage: "Requesting screenshot..."
            )
        } else {
            let (fence, response) = try await CLIRunner.execute(
                connection: connection,
                request: request,
                statusMessage: "Requesting screenshot..."
            )
            defer { fence.stop() }

            if case .screenshotData(let pngData, _, _) = response {
                guard let data = Data(base64Encoded: pngData) else {
                    throw ValidationError("Failed to decode screenshot data")
                }
                FileHandle.standardOutput.write(data)
            } else {
                CLIRunner.outputResponse(response, format: .human)
            }
        }
    }
}
