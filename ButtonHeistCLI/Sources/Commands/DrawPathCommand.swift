import ArgumentParser
import ButtonHeist
import Foundation

struct DrawPathCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: TheFence.Command.drawPath.rawValue,
        abstract: "Trace a polyline gesture through JSON-specified waypoints",
        discussion: """
            Reads a waypoint array (`[{ "x": …, "y": … }, …]`) either inline
            via --points or from a JSON file. Either duration or velocity
            may be supplied — the two are mutually exclusive.

            Examples:
              buttonheist draw_path --points-from-file path.json
              buttonheist draw_path --points '[{"x":100,"y":200},{"x":150,"y":260}]' --duration 0.5
              buttonheist draw_path --points-from-file path.json --velocity 800
            """
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "Inline JSON array of {x, y} waypoints")
    var points: String?

    @Option(name: .long, help: "Path to a JSON file containing the waypoint array")
    var pointsFromFile: String?

    @Option(name: .long, help: "Total duration in seconds (mutually exclusive with --velocity)")
    var duration: Double?

    @Option(name: .long, help: "Speed in points-per-second (mutually exclusive with --duration)")
    var velocity: Double?

    @ButtonHeistActor
    mutating func run() async throws {
        let array = try loadJSONArray(inline: points, fromFile: pointsFromFile, optionName: "points")
        var request: [String: Any] = [
            "command": TheFence.Command.drawPath.rawValue,
            "points": array,
        ]
        if let duration { request["duration"] = duration }
        if let velocity { request["velocity"] = velocity }
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Drawing path..."
        )
    }
}
