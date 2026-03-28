import ArgumentParser
import ButtonHeist

struct TouchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "touch",
        abstract: "Simulate touch gestures on the connected iOS device",
        discussion: """
            Low-level touch gestures. For tapping buttons and controls, prefer \
            `buttonheist activate` which uses accessibility-first interaction.

            Examples:
              buttonheist touch one_finger_tap --x 100 --y 200
              buttonheist touch long_press --identifier "myButton" --duration 1.0
              buttonheist touch swipe --identifier "list" --direction up
              buttonheist touch drag --from-x 100 --from-y 200 --to-x 300 --to-y 200
              buttonheist touch pinch --identifier "mapView" --scale 2.0
              buttonheist touch rotate --x 200 --y 300 --angle 1.57
              buttonheist touch two_finger_tap --identifier "zoomControl"
            """,
        subcommands: [
            TapSubcommand.self,
            LongPressSubcommand.self,
            SwipeSubcommand.self,
            DragSubcommand.self,
            PinchSubcommand.self,
            RotateSubcommand.self,
            TwoFingerTapSubcommand.self,
        ]
    )
}

// MARK: - Tap

struct TapSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "one_finger_tap",
        abstract: "Raw synthetic tap at coordinates or element center",
        discussion: """
            Performs a direct synthetic tap without accessibility semantics. \
            For interacting with buttons, links, and controls, prefer \
            `buttonheist activate` which tries accessibilityActivate() first \
            and is more reliable across different UI frameworks.

            Use one_finger_tap when you need precise coordinate-based taps \
            or when accessibility activation is not appropriate (e.g., tapping \
            a specific point on a canvas or map).
            """
    )

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .long, help: "X coordinate")
    var x: Double?

    @Option(name: .long, help: "Y coordinate")
    var y: Double?

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        guard element.actionTarget != nil || (x != nil && y != nil) else {
            throw ValidationError("Must specify --identifier, --index, or --x/--y coordinates")
        }

        let message: ClientMessage
        if let target = element.actionTarget {
            message = .touchTap(TouchTapTarget(elementTarget: target))
        } else {
            message = .touchTap(TouchTapTarget(pointX: x, pointY: y))
        }

        try await sendTouchGesture(message: message, connection: connection, timeout: timeout, format: output.format)
    }
}

// MARK: - Long Press

struct LongPressSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "long_press", abstract: "Long press at a point or element")

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .long, help: "X coordinate")
    var x: Double?

    @Option(name: .long, help: "Y coordinate")
    var y: Double?

    @Option(name: .long, help: "Press duration in seconds (default 0.5)")
    var duration: Double = 0.5

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        guard element.actionTarget != nil || (x != nil && y != nil) else {
            throw ValidationError("Must specify --identifier, --index, or --x/--y coordinates")
        }

        let message: ClientMessage
        if let target = element.actionTarget {
            message = .touchLongPress(LongPressTarget(elementTarget: target, duration: duration))
        } else {
            message = .touchLongPress(LongPressTarget(pointX: x, pointY: y, duration: duration))
        }

        try await sendTouchGesture(message: message, connection: connection, timeout: timeout, format: output.format)
    }
}

// MARK: - Swipe

struct SwipeSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "swipe", abstract: "Swipe between two points or in a direction")

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .customLong("start-x"), help: "Unit-point start X (0-1 relative to element frame)")
    var startUnitX: Double?

    @Option(name: .customLong("start-y"), help: "Unit-point start Y (0-1 relative to element frame)")
    var startUnitY: Double?

    @Option(name: .customLong("end-x"), help: "Unit-point end X (0-1 relative to element frame)")
    var endUnitX: Double?

    @Option(name: .customLong("end-y"), help: "Unit-point end Y (0-1 relative to element frame)")
    var endUnitY: Double?

    @Option(name: .customLong("from-x"), help: "Absolute start X coordinate")
    var fromX: Double?

    @Option(name: .customLong("from-y"), help: "Absolute start Y coordinate")
    var fromY: Double?

    @Option(name: .customLong("to-x"), help: "Absolute end X coordinate")
    var toX: Double?

    @Option(name: .customLong("to-y"), help: "Absolute end Y coordinate")
    var toY: Double?

    @Option(name: .long, help: "Swipe direction: up, down, left, right")
    var direction: String?

    @Option(name: .long, help: "Duration in seconds (default 0.15)")
    var duration: Double?

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        let hasUnitStart = startUnitX != nil && startUnitY != nil
        let hasUnitEnd = endUnitX != nil && endUnitY != nil

        if hasUnitStart != hasUnitEnd {
            throw ValidationError("Unit-point swipe requires both --start-x/--start-y and --end-x/--end-y")
        }

        let unitStart: UnitPoint?
        let unitEnd: UnitPoint?

        if let sx = startUnitX, let sy = startUnitY, let ex = endUnitX, let ey = endUnitY {
            guard element.actionTarget != nil else {
                throw ValidationError("Unit-point swipe requires an element target (--identifier, --heist-id, or --index)")
            }
            unitStart = UnitPoint(x: sx, y: sy)
            unitEnd = UnitPoint(x: ex, y: ey)
        } else {
            unitStart = nil
            unitEnd = nil

            guard element.actionTarget != nil || (fromX != nil && fromY != nil) else {
                throw ValidationError("Must specify element target, --from-x/--from-y, or --start-x/--start-y unit points")
            }
            guard (toX != nil && toY != nil) || direction != nil else {
                throw ValidationError("Must specify --to-x/--to-y, --direction, or --end-x/--end-y unit points")
            }
        }

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
            elementTarget: element.actionTarget,
            startX: fromX, startY: fromY,
            endX: toX, endY: toY,
            direction: swipeDirection,
            duration: duration,
            start: unitStart, end: unitEnd
        ))

        try await sendTouchGesture(message: message, connection: connection, timeout: timeout, format: output.format)
    }
}

// MARK: - Drag

struct DragSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "drag", abstract: "Drag from one point to another")

    @OptionGroup var element: ElementTargetOptions

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
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        guard element.actionTarget != nil || (fromX != nil && fromY != nil) else {
            throw ValidationError("Must specify --identifier, --index, or --from-x/--from-y coordinates")
        }

        let message = ClientMessage.touchDrag(DragTarget(
            elementTarget: element.actionTarget,
            startX: fromX, startY: fromY,
            endX: toX, endY: toY,
            duration: duration
        ))

        try await sendTouchGesture(message: message, connection: connection, timeout: timeout, format: output.format)
    }
}

// MARK: - Pinch

struct PinchSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "pinch", abstract: "Pinch/zoom at a point or element")

    @OptionGroup var element: ElementTargetOptions

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
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        guard element.actionTarget != nil || (x != nil && y != nil) else {
            throw ValidationError("Must specify --identifier, --index, or --x/--y coordinates")
        }

        let message: ClientMessage
        if let target = element.actionTarget {
            message = .touchPinch(PinchTarget(elementTarget: target, scale: scale, spread: spread, duration: duration))
        } else {
            message = .touchPinch(PinchTarget(centerX: x, centerY: y, scale: scale, spread: spread, duration: duration))
        }

        try await sendTouchGesture(message: message, connection: connection, timeout: timeout, format: output.format)
    }
}

// MARK: - Rotate

struct RotateSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "rotate", abstract: "Rotate at a point or element")

    @OptionGroup var element: ElementTargetOptions

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
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        guard element.actionTarget != nil || (x != nil && y != nil) else {
            throw ValidationError("Must specify --identifier, --index, or --x/--y coordinates")
        }

        let message: ClientMessage
        if let target = element.actionTarget {
            message = .touchRotate(RotateTarget(elementTarget: target, angle: angle, radius: radius, duration: duration))
        } else {
            message = .touchRotate(RotateTarget(centerX: x, centerY: y, angle: angle, radius: radius, duration: duration))
        }

        try await sendTouchGesture(message: message, connection: connection, timeout: timeout, format: output.format)
    }
}

// MARK: - Two-Finger Tap

struct TwoFingerTapSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "two_finger_tap", abstract: "Tap with two fingers at a point or element")

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .long, help: "Center X coordinate")
    var x: Double?

    @Option(name: .long, help: "Center Y coordinate")
    var y: Double?

    @Option(name: .long, help: "Distance between fingers in points (default 40)")
    var spread: Double?

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @ButtonHeistActor
    mutating func run() async throws {
        guard element.actionTarget != nil || (x != nil && y != nil) else {
            throw ValidationError("Must specify --identifier, --index, or --x/--y coordinates")
        }

        let message: ClientMessage
        if let target = element.actionTarget {
            message = .touchTwoFingerTap(TwoFingerTapTarget(elementTarget: target, spread: spread))
        } else {
            message = .touchTwoFingerTap(TwoFingerTapTarget(centerX: x, centerY: y, spread: spread))
        }

        try await sendTouchGesture(message: message, connection: connection, timeout: timeout, format: output.format)
    }
}

// MARK: - Shared Connection Helper

@ButtonHeistActor
private func sendTouchGesture(message: ClientMessage, connection: ConnectionOptions,
                              timeout: Double, format: OutputFormat?) async throws {
    let config = EnvironmentConfig.resolve(deviceFilter: connection.device, token: connection.token)
    let connector = DeviceConnector(deviceFilter: config.deviceFilter, token: config.token, driverId: config.driverId, quiet: connection.quiet)
    try await connector.connect()
    defer { connector.disconnect() }

    if !connection.quiet {
        logStatus("Sending gesture...")
    }

    connector.send(message)

    let result = try await connector.waitForActionResult(timeout: timeout)
    outputActionResult(result, format: format, quiet: connection.quiet, verb: "Gesture")
}
