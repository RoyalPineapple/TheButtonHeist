import ArgumentParser
import ButtonHeist
import Foundation

struct DrawBezierCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: TheFence.Command.drawBezier.rawValue,
        abstract: "Trace cubic bezier segments sampled to a polyline",
        discussion: """
            Reads a segment array (`[{ "cp1X": …, "cp1Y": …, "cp2X": …, "cp2Y": …,
            "endX": …, "endY": … }, …]`) either inline via --segments or from a
            JSON file. The start point is supplied separately via --start-x /
            --start-y.

            Examples:
              buttonheist draw_bezier --start-x 100 --start-y 200 --segments-from-file curves.json
              buttonheist draw_bezier --start-x 0 --start-y 0 \\
                --segments '[{"cp1X":50,"cp1Y":0,"cp2X":100,"cp2Y":100,"endX":150,"endY":50}]' \\
                --duration 0.75
            """
    )

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "Starting X coordinate")
    var startX: Double

    @Option(name: .long, help: "Starting Y coordinate")
    var startY: Double

    @Option(name: .long, help: "Inline JSON array of cubic bezier segments")
    var segments: String?

    @Option(name: .long, help: "Path to a JSON file containing the segment array")
    var segmentsFromFile: String?

    @Option(name: .long, help: "Samples per segment (default: 20)")
    var samplesPerSegment: Int?

    @Option(name: .long, help: "Total duration in seconds (mutually exclusive with --velocity)")
    var duration: Double?

    @Option(name: .long, help: "Speed in points-per-second (mutually exclusive with --duration)")
    var velocity: Double?

    @ButtonHeistActor
    mutating func run() async throws {
        let array = try loadJSONArray(inline: segments, fromFile: segmentsFromFile, optionName: "segments")
        var request: [String: Any] = [
            "command": TheFence.Command.drawBezier.rawValue,
            "startX": startX,
            "startY": startY,
            "segments": array,
        ]
        if let samplesPerSegment { request["samplesPerSegment"] = samplesPerSegment }
        if let duration { request["duration"] = duration }
        if let velocity { request["velocity"] = velocity }
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Drawing bezier path..."
        )
    }
}
