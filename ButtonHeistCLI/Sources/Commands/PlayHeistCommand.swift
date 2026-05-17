import ArgumentParser
import ButtonHeist
import Foundation
import TheScore

struct PlayHeistCommand: AsyncParsableCommand, CLICommandContract {
    static let fenceCommand = TheFence.Command.playHeist

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Play back a recorded .heist file"
    )

    @Option(name: .shortAndLong, help: "Input .heist file path")
    var input: String

    @Option(name: .long, help: "Write JUnit XML report to this path")
    var junit: String?

    @OptionGroup var connection: ConnectionOptions

    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    func run() async throws {
        let request = Self.fenceRequest(["input": input])

        if let junitPath = junit {
            let (fence, response) = try await CLIRunner.execute(
                connection: connection,
                request: request
            )
            defer { fence.stop() }

            if case .heistPlayback(_, _, _, _, .some(let report)) = response {
                let xml = report.junitXML()
                let url = URL(fileURLWithPath: junitPath)
                try xml.write(to: url, atomically: true, encoding: .utf8)
                logStatus("JUnit report written to \(junitPath)")
            } else {
                logStatus("Warning: --junit requested but playback did not produce a report")
            }

            CLIRunner.outputResponse(response, format: output.format ?? .auto)
        } else {
            try await CLIRunner.run(
                connection: connection,
                format: output.format,
                request: request
            )
        }
    }
}
