import ArgumentParser
import Foundation
import ButtonHeist

struct ScreenshotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get_screen",
        abstract: "Capture a screenshot from the connected device"
    )

    @Option(name: .shortAndLong, help: "Output file path (default: stdout as raw PNG)")
    var output: String?

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .long, help: "Connection timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    func run() async throws {
        var request: [String: Any] = ["command": TheFence.Command.getScreen.rawValue]
        if let outputPath = output {
            // When saving to file, TheFence handles the write and returns .screenshot
            request["output"] = outputPath
            try await CLIRunner.run(
                connection: connection,
                format: .human,
                request: request,
                statusMessage: "Requesting screenshot..."
            )
        } else {
            // When writing to stdout, we need the raw PNG data
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
