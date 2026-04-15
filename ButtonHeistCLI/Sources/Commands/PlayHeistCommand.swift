import ArgumentParser
import ButtonHeist
import Foundation
import TheScore

struct PlayHeistCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "play_heist",
        abstract: "Play back a recorded .heist file"
    )

    @Option(name: .shortAndLong, help: "Input .heist file path")
    var input: String

    @Option(name: .long, help: "Write JUnit XML report to this path")
    var junit: String?

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .auto

    @ButtonHeistActor
    func run() async throws {
        let request: [String: Any] = [
            "command": TheFence.Command.playHeist.rawValue,
            "input": input,
        ]

        if let junitPath = junit {
            let (fence, response) = try await CLIRunner.execute(
                connection: connection,
                request: request
            )
            defer { fence.stop() }

            if case .heistPlayback(_, _, _, _, let report) = response, let report {
                let xml = report.junitXML()
                let url = URL(fileURLWithPath: junitPath)
                try xml.write(to: url, atomically: true, encoding: .utf8)
                logStatus("JUnit report written to \(junitPath)")
            }

            CLIRunner.outputResponse(response, format: format)
        } else {
            try await CLIRunner.run(
                connection: connection,
                format: format,
                request: request
            )
        }
    }
}
