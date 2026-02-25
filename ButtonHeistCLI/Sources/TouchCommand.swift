import ArgumentParser
import Foundation
import Darwin
import ButtonHeist

struct TouchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "touch",
        abstract: "Simulate touch gestures on the connected iOS device",
        discussion: """
            Send touch gestures to the connected iOS app.

            Examples:
              buttonheist touch tap --identifier "myButton"
              buttonheist touch tap --x 100 --y 200
              buttonheist touch longpress --identifier "myButton" --duration 1.0
              buttonheist touch swipe --identifier "list" --direction up
              buttonheist touch swipe --from-x 200 --from-y 400 --to-x 200 --to-y 100
              buttonheist touch drag --from-x 100 --from-y 200 --to-x 300 --to-y 200
              buttonheist touch pinch --identifier "mapView" --scale 2.0
              buttonheist touch rotate --x 200 --y 300 --angle 1.57
              buttonheist touch two-finger-tap --identifier "zoomControl"
              buttonheist touch draw-path --points "100,400 200,300 300,400"
              buttonheist touch draw-bezier --bezier-file curve.json
            """,
        subcommands: [
            TapSubcommand.self,
            LongPressSubcommand.self,
            SwipeSubcommand.self,
            DragSubcommand.self,
            PinchSubcommand.self,
            RotateSubcommand.self,
            TwoFingerTapSubcommand.self,
            DrawPathSubcommand.self,
            DrawBezierSubcommand.self,
        ]
    )
}

// MARK: - Tap

struct TapSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "tap", abstract: "Tap at a point or element")

    @Option(name: .long, help: "Element identifier")
    var identifier: String?

    @Option(name: .long, help: "Element index")
    var index: Int?

    @Option(name: .long, help: "X coordinate")
    var x: Double?

    @Option(name: .long, help: "Y coordinate")
    var y: Double?

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @MainActor
    mutating func run() async throws {
        guard identifier != nil || index != nil || (x != nil && y != nil) else {
            throw ValidationError("Must specify --identifier, --index, or --x/--y coordinates")
        }

        let message: ClientMessage
        if identifier != nil || index != nil {
            let target = ActionTarget(identifier: identifier, order: index)
            message = .touchTap(TouchTapTarget(elementTarget: target))
        } else {
            message = .touchTap(TouchTapTarget(pointX: x, pointY: y))
        }

        try await sendTouchGesture(message: message, connection: connection, timeout: timeout, format: format)
    }
}

// MARK: - Long Press

struct LongPressSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "longpress", abstract: "Long press at a point or element")

    @Option(name: .long, help: "Element identifier")
    var identifier: String?

    @Option(name: .long, help: "Element index")
    var index: Int?

    @Option(name: .long, help: "X coordinate")
    var x: Double?

    @Option(name: .long, help: "Y coordinate")
    var y: Double?

    @Option(name: .long, help: "Press duration in seconds (default 0.5)")
    var duration: Double = 0.5

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @MainActor
    mutating func run() async throws {
        guard identifier != nil || index != nil || (x != nil && y != nil) else {
            throw ValidationError("Must specify --identifier, --index, or --x/--y coordinates")
        }

        let message: ClientMessage
        if identifier != nil || index != nil {
            let target = ActionTarget(identifier: identifier, order: index)
            message = .touchLongPress(LongPressTarget(elementTarget: target, duration: duration))
        } else {
            message = .touchLongPress(LongPressTarget(pointX: x, pointY: y, duration: duration))
        }

        try await sendTouchGesture(message: message, connection: connection, timeout: timeout, format: format)
    }
}

// MARK: - Swipe

struct SwipeSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "swipe", abstract: "Swipe between two points or in a direction")

    @Option(name: .long, help: "Element identifier for start point")
    var identifier: String?

    @Option(name: .long, help: "Element index for start point")
    var index: Int?

    @Option(name: .customLong("from-x"), help: "Start X coordinate")
    var fromX: Double?

    @Option(name: .customLong("from-y"), help: "Start Y coordinate")
    var fromY: Double?

    @Option(name: .customLong("to-x"), help: "End X coordinate")
    var toX: Double?

    @Option(name: .customLong("to-y"), help: "End Y coordinate")
    var toY: Double?

    @Option(name: .long, help: "Swipe direction: up, down, left, right")
    var direction: String?

    @Option(name: .long, help: "Swipe distance in points (default 200)")
    var distance: Double?

    @Option(name: .long, help: "Duration in seconds (default 0.15)")
    var duration: Double?

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @MainActor
    mutating func run() async throws {
        guard identifier != nil || index != nil || (fromX != nil && fromY != nil) else {
            throw ValidationError("Must specify --identifier, --index, or --from-x/--from-y coordinates")
        }
        guard (toX != nil && toY != nil) || direction != nil else {
            throw ValidationError("Must specify --to-x/--to-y or --direction")
        }

        let elementTarget: ActionTarget? = (identifier != nil || index != nil)
            ? ActionTarget(identifier: identifier, order: index) : nil

        let swipeDirection: SwipeDirection?
        if let dir = direction {
            guard let d = SwipeDirection(rawValue: dir.lowercased()) else {
                throw ValidationError("Invalid direction: \(dir). Valid: up, down, left, right")
            }
            swipeDirection = d
        } else {
            swipeDirection = nil
        }

        let message = ClientMessage.touchSwipe(SwipeTarget(
            elementTarget: elementTarget,
            startX: fromX, startY: fromY,
            endX: toX, endY: toY,
            direction: swipeDirection, distance: distance,
            duration: duration
        ))

        try await sendTouchGesture(message: message, connection: connection, timeout: timeout, format: format)
    }
}

// MARK: - Drag

struct DragSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "drag", abstract: "Drag from one point to another")

    @Option(name: .long, help: "Element identifier for start point")
    var identifier: String?

    @Option(name: .long, help: "Element index for start point")
    var index: Int?

    @Option(name: .customLong("from-x"), help: "Start X coordinate")
    var fromX: Double?

    @Option(name: .customLong("from-y"), help: "Start Y coordinate")
    var fromY: Double?

    @Option(name: .customLong("to-x"), help: "End X coordinate")
    var toX: Double

    @Option(name: .customLong("to-y"), help: "End Y coordinate")
    var toY: Double

    @Option(name: .long, help: "Duration in seconds (default 0.5)")
    var duration: Double?

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @MainActor
    mutating func run() async throws {
        guard identifier != nil || index != nil || (fromX != nil && fromY != nil) else {
            throw ValidationError("Must specify --identifier, --index, or --from-x/--from-y coordinates")
        }

        let elementTarget: ActionTarget? = (identifier != nil || index != nil)
            ? ActionTarget(identifier: identifier, order: index) : nil

        let message = ClientMessage.touchDrag(DragTarget(
            elementTarget: elementTarget,
            startX: fromX, startY: fromY,
            endX: toX, endY: toY,
            duration: duration
        ))

        try await sendTouchGesture(message: message, connection: connection, timeout: timeout, format: format)
    }
}

// MARK: - Pinch

struct PinchSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "pinch", abstract: "Pinch/zoom at a point or element")

    @Option(name: .long, help: "Element identifier")
    var identifier: String?

    @Option(name: .long, help: "Element index")
    var index: Int?

    @Option(name: .long, help: "Center X coordinate")
    var x: Double?

    @Option(name: .long, help: "Center Y coordinate")
    var y: Double?

    @Option(name: .long, help: "Scale factor (>1 zoom in, <1 zoom out)")
    var scale: Double

    @Option(name: .long, help: "Initial finger spread from center in points (default 100)")
    var spread: Double?

    @Option(name: .long, help: "Duration in seconds (default 0.5)")
    var duration: Double?

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @MainActor
    mutating func run() async throws {
        guard identifier != nil || index != nil || (x != nil && y != nil) else {
            throw ValidationError("Must specify --identifier, --index, or --x/--y coordinates")
        }

        let message: ClientMessage
        if identifier != nil || index != nil {
            let target = ActionTarget(identifier: identifier, order: index)
            message = .touchPinch(PinchTarget(elementTarget: target, scale: scale, spread: spread, duration: duration))
        } else {
            message = .touchPinch(PinchTarget(centerX: x, centerY: y, scale: scale, spread: spread, duration: duration))
        }

        try await sendTouchGesture(message: message, connection: connection, timeout: timeout, format: format)
    }
}

// MARK: - Rotate

struct RotateSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "rotate", abstract: "Rotate at a point or element")

    @Option(name: .long, help: "Element identifier")
    var identifier: String?

    @Option(name: .long, help: "Element index")
    var index: Int?

    @Option(name: .long, help: "Center X coordinate")
    var x: Double?

    @Option(name: .long, help: "Center Y coordinate")
    var y: Double?

    @Option(name: .long, help: "Rotation angle in radians")
    var angle: Double

    @Option(name: .long, help: "Distance from center to each finger in points (default 100)")
    var radius: Double?

    @Option(name: .long, help: "Duration in seconds (default 0.5)")
    var duration: Double?

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @MainActor
    mutating func run() async throws {
        guard identifier != nil || index != nil || (x != nil && y != nil) else {
            throw ValidationError("Must specify --identifier, --index, or --x/--y coordinates")
        }

        let message: ClientMessage
        if identifier != nil || index != nil {
            let target = ActionTarget(identifier: identifier, order: index)
            message = .touchRotate(RotateTarget(elementTarget: target, angle: angle, radius: radius, duration: duration))
        } else {
            message = .touchRotate(RotateTarget(centerX: x, centerY: y, angle: angle, radius: radius, duration: duration))
        }

        try await sendTouchGesture(message: message, connection: connection, timeout: timeout, format: format)
    }
}

// MARK: - Two-Finger Tap

struct TwoFingerTapSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "two-finger-tap", abstract: "Tap with two fingers at a point or element")

    @Option(name: .long, help: "Element identifier")
    var identifier: String?

    @Option(name: .long, help: "Element index")
    var index: Int?

    @Option(name: .long, help: "Center X coordinate")
    var x: Double?

    @Option(name: .long, help: "Center Y coordinate")
    var y: Double?

    @Option(name: .long, help: "Distance between fingers in points (default 40)")
    var spread: Double?

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @MainActor
    mutating func run() async throws {
        guard identifier != nil || index != nil || (x != nil && y != nil) else {
            throw ValidationError("Must specify --identifier, --index, or --x/--y coordinates")
        }

        let message: ClientMessage
        if identifier != nil || index != nil {
            let target = ActionTarget(identifier: identifier, order: index)
            message = .touchTwoFingerTap(TwoFingerTapTarget(elementTarget: target, spread: spread))
        } else {
            message = .touchTwoFingerTap(TwoFingerTapTarget(centerX: x, centerY: y, spread: spread))
        }

        try await sendTouchGesture(message: message, connection: connection, timeout: timeout, format: format)
    }
}

// MARK: - Draw Path

struct DrawPathSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "draw-path",
        abstract: "Draw along a path of points",
        discussion: """
            Trace a finger through a sequence of waypoints.

            Examples:
              buttonheist touch draw-path --points "100,200 150,250 200,300"
              buttonheist touch draw-path --path-file shape.json
              buttonheist touch draw-path --points "100,400 200,300 300,400" --velocity 500
            """
    )

    @Option(name: .long, help: "Inline points as 'x1,y1 x2,y2 ...'")
    var points: String?

    @Option(name: .customLong("path-file"), help: "JSON file with array of {x, y} objects")
    var pathFile: String?

    @Option(name: .long, help: "Total duration in seconds")
    var duration: Double?

    @Option(name: .long, help: "Speed in points per second")
    var velocity: Double?

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 30.0

    @MainActor
    mutating func run() async throws {
        let pathPoints: [PathPoint]

        if let pointsStr = points {
            pathPoints = try parseInlinePoints(pointsStr)
        } else if let file = pathFile {
            pathPoints = try loadPathFile(file)
        } else {
            throw ValidationError("Must specify --points or --path-file")
        }

        guard pathPoints.count >= 2 else {
            throw ValidationError("Path requires at least 2 points")
        }

        let message = ClientMessage.touchDrawPath(DrawPathTarget(
            points: pathPoints,
            duration: duration,
            velocity: velocity
        ))

        try await sendTouchGesture(message: message, connection: connection, timeout: timeout, format: format)
    }

    private func parseInlinePoints(_ str: String) throws -> [PathPoint] {
        let pairs = str.split(separator: " ")
        return try pairs.map { pair in
            let coords = pair.split(separator: ",")
            guard coords.count == 2,
                  let x = Double(coords[0]),
                  let y = Double(coords[1]) else {
                throw ValidationError("Invalid point format '\(pair)'. Expected 'x,y'")
            }
            return PathPoint(x: x, y: y)
        }
    }

    private func loadPathFile(_ path: String) throws -> [PathPoint] {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([PathPoint].self, from: data)
    }
}

// MARK: - Draw Bezier

struct DrawBezierSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "draw-bezier",
        abstract: "Draw along a cubic bezier curve",
        discussion: """
            Trace a finger along cubic bezier curve segments. The curve is sampled
            to a polyline server-side before execution.

            The bezier file is a JSON object:
            {
              "startX": 100, "startY": 400,
              "segments": [
                {"cp1X": 100, "cp1Y": 200, "cp2X": 300, "cp2Y": 200, "endX": 300, "endY": 400}
              ]
            }

            Examples:
              buttonheist touch draw-bezier --bezier-file curve.json
              buttonheist touch draw-bezier --bezier-file curve.json --samples 40 --velocity 300
            """
    )

    @Option(name: .customLong("bezier-file"), help: "JSON file with bezier path definition")
    var bezierFile: String

    @Option(name: .long, help: "Samples per bezier segment (default 20)")
    var samples: Int?

    @Option(name: .long, help: "Total duration in seconds")
    var duration: Double?

    @Option(name: .long, help: "Speed in points per second")
    var velocity: Double?

    @OptionGroup var connection: ConnectionOptions

    @Option(name: .shortAndLong, help: "Output format: human, json (default: human when interactive, json when piped)")
    var format: OutputFormat?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 30.0

    @MainActor
    mutating func run() async throws {
        let url = URL(fileURLWithPath: bezierFile)
        let data = try Data(contentsOf: url)
        let target = try JSONDecoder().decode(DrawBezierTarget.self, from: data)

        guard !target.segments.isEmpty else {
            throw ValidationError("Bezier path requires at least 1 segment")
        }

        let message = ClientMessage.touchDrawBezier(DrawBezierTarget(
            startX: target.startX, startY: target.startY,
            segments: target.segments,
            samplesPerSegment: samples ?? target.samplesPerSegment,
            duration: duration ?? target.duration,
            velocity: velocity ?? target.velocity
        ))

        try await sendTouchGesture(message: message, connection: connection, timeout: timeout, format: format)
    }
}

// MARK: - Shared Connection Helper

@MainActor
private func sendTouchGesture(message: ClientMessage, connection: ConnectionOptions,
                              timeout: Double, format: OutputFormat?) async throws {
    let connector = DeviceConnector(deviceFilter: connection.device, host: connection.host,
                                    port: connection.port, quiet: connection.quiet)
    try await connector.connect()
    defer { connector.disconnect() }
    let client = connector.client

    if !connection.quiet {
        logStatus("Sending gesture...")
    }

    client.send(message)

    let result = try await client.waitForActionResult(timeout: timeout)
    outputActionResult(result, format: format, quiet: connection.quiet, verb: "Gesture")
}
