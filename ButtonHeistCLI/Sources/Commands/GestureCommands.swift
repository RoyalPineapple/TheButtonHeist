import ArgumentParser
import ButtonHeist

// MARK: - Tap

struct TapSubcommand: AsyncParsableCommand, GestureCLICommandContract {
    static let gestureType = GestureType.oneFingerTap

    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
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

    @ButtonHeistActor
    mutating func run() async throws {
        guard (try element.hasTarget) || (x != nil && y != nil) else {
            throw ValidationError("Must specify a heistId, -id, or --x/--y coordinates")
        }

        var request = Self.fenceRequest()
        try element.applyTo(&request)
        if let x { request.set(.x, x) }
        if let y { request.set(.y, y) }

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Sending gesture..."
        )
    }
}

// MARK: - Long Press

struct LongPressSubcommand: AsyncParsableCommand, GestureCLICommandContract {
    static let gestureType = GestureType.longPress

    static let configuration = CommandConfiguration(commandName: Self.cliCommandName, abstract: "Long press at a point or element")

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .long, help: "X coordinate")
    var x: Double?

    @Option(name: .long, help: "Y coordinate")
    var y: Double?

    @Option(name: .long, help: "Press duration in seconds (default 0.5)")
    var duration: Double = 0.5

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    mutating func run() async throws {
        guard (try element.hasTarget) || (x != nil && y != nil) else {
            throw ValidationError("Must specify a heistId, -id, or --x/--y coordinates")
        }

        var request = Self.fenceRequest([.duration: .double(duration)])
        try element.applyTo(&request)
        if let x { request.set(.x, x) }
        if let y { request.set(.y, y) }

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Sending gesture..."
        )
    }
}

// MARK: - Swipe

struct SwipeSubcommand: AsyncParsableCommand, GestureCLICommandContract {
    static let gestureType = GestureType.swipe

    static let configuration = CommandConfiguration(commandName: Self.cliCommandName, abstract: "Swipe between two points or in a direction")

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

    @Option(name: .shortAndLong, help: "Swipe direction: up, down, left, right")
    var direction: String?

    @Option(name: .long, help: "Duration in seconds (default 0.15)")
    var duration: Double?

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    mutating func run() async throws {
        let hasUnitStart = startUnitX != nil && startUnitY != nil
        let hasUnitEnd = endUnitX != nil && endUnitY != nil

        if hasUnitStart != hasUnitEnd {
            throw ValidationError("Unit-point swipe requires both --start-x/--start-y and --end-x/--end-y")
        }

        if hasUnitStart {
            guard try element.hasTarget else {
                throw ValidationError("Unit-point swipe requires an element target (heistId, -id, or -l)")
            }
        } else {
            guard (try element.hasTarget) || (fromX != nil && fromY != nil) else {
                throw ValidationError("Must specify a heistId, -id, --from-x/--from-y, or --start-x/--start-y unit points")
            }
            guard (toX != nil && toY != nil) || direction != nil else {
                throw ValidationError("Must specify --to-x/--to-y, --direction, or --end-x/--end-y unit points")
            }
        }

        let swipeDirection: SwipeDirection?
        if let dir = direction {
            guard let parsedDirection = SwipeDirection(rawValue: dir.lowercased()) else {
                throw ValidationError("Invalid direction: \(dir). Valid: \(SwipeDirection.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            swipeDirection = parsedDirection
        } else {
            swipeDirection = nil
        }

        var request = Self.fenceRequest()
        try element.applyTo(&request)
        if let fromX { request.set(.startX, fromX) }
        if let fromY { request.set(.startY, fromY) }
        if let toX { request.set(.endX, toX) }
        if let toY { request.set(.endY, toY) }
        if let swipeDirection { request.set(.direction, swipeDirection.rawValue) }
        if let duration { request.set(.duration, duration) }
        if let startUnitX, let startUnitY {
            request.set(.start, .object([
                FenceParameterKey.x.rawValue: .double(startUnitX),
                FenceParameterKey.y.rawValue: .double(startUnitY),
            ]))
        }
        if let endUnitX, let endUnitY {
            request.set(.end, .object([
                FenceParameterKey.x.rawValue: .double(endUnitX),
                FenceParameterKey.y.rawValue: .double(endUnitY),
            ]))
        }

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Sending gesture..."
        )
    }
}

// MARK: - Drag

struct DragSubcommand: AsyncParsableCommand, GestureCLICommandContract {
    static let gestureType = GestureType.drag

    static let configuration = CommandConfiguration(commandName: Self.cliCommandName, abstract: "Drag from one point to another")

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

    @ButtonHeistActor
    mutating func run() async throws {
        guard (try element.hasTarget) || (fromX != nil && fromY != nil) else {
            throw ValidationError("Must specify a heistId, -id, or --from-x/--from-y coordinates")
        }

        var request = Self.fenceRequest([
            .endX: .double(toX),
            .endY: .double(toY),
        ])
        try element.applyTo(&request)
        if let fromX { request.set(.startX, fromX) }
        if let fromY { request.set(.startY, fromY) }
        if let duration { request.set(.duration, duration) }

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Sending gesture..."
        )
    }
}

// MARK: - Pinch

struct PinchSubcommand: AsyncParsableCommand, GestureCLICommandContract {
    static let gestureType = GestureType.pinch

    static let configuration = CommandConfiguration(commandName: Self.cliCommandName, abstract: "Pinch/zoom at a point or element")

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .long, help: "Center X coordinate")
    var centerX: Double?

    @Option(name: .long, help: "Center Y coordinate")
    var centerY: Double?

    @Option(name: .long, help: "Scale factor (>1 zoom in, <1 zoom out)")
    var scale: Double

    @Option(name: .long, help: "Initial finger spread from center in points (default 100)")
    var spread: Double?

    @Option(name: .long, help: "Duration in seconds (default 0.5)")
    var duration: Double?

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    mutating func run() async throws {
        guard (try element.hasTarget) || (centerX != nil && centerY != nil) else {
            throw ValidationError("Must specify a heistId, -id, or --center-x/--center-y coordinates")
        }

        var request = Self.fenceRequest([.scale: .double(scale)])
        try element.applyTo(&request)
        if let centerX { request.set(.centerX, centerX) }
        if let centerY { request.set(.centerY, centerY) }
        if let spread { request.set(.spread, spread) }
        if let duration { request.set(.duration, duration) }

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Sending gesture..."
        )
    }
}

// MARK: - Rotate

struct RotateSubcommand: AsyncParsableCommand, GestureCLICommandContract {
    static let gestureType = GestureType.rotate

    static let configuration = CommandConfiguration(commandName: Self.cliCommandName, abstract: "Rotate at a point or element")

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .long, help: "Center X coordinate")
    var centerX: Double?

    @Option(name: .long, help: "Center Y coordinate")
    var centerY: Double?

    @Option(name: .long, help: "Rotation angle in radians")
    var angle: Double

    @Option(name: .long, help: "Distance from center to each finger in points (default 100)")
    var radius: Double?

    @Option(name: .long, help: "Duration in seconds (default 0.5)")
    var duration: Double?

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    mutating func run() async throws {
        guard (try element.hasTarget) || (centerX != nil && centerY != nil) else {
            throw ValidationError("Must specify a heistId, -id, or --center-x/--center-y coordinates")
        }

        var request = Self.fenceRequest([.angle: .double(angle)])
        try element.applyTo(&request)
        if let centerX { request.set(.centerX, centerX) }
        if let centerY { request.set(.centerY, centerY) }
        if let radius { request.set(.radius, radius) }
        if let duration { request.set(.duration, duration) }

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Sending gesture..."
        )
    }
}

// MARK: - Two-Finger Tap

struct TwoFingerTapSubcommand: AsyncParsableCommand, GestureCLICommandContract {
    static let gestureType = GestureType.twoFingerTap

    static let configuration = CommandConfiguration(commandName: Self.cliCommandName, abstract: "Tap with two fingers at a point or element")

    @OptionGroup var element: ElementTargetOptions

    @Option(name: .long, help: "Center X coordinate")
    var centerX: Double?

    @Option(name: .long, help: "Center Y coordinate")
    var centerY: Double?

    @Option(name: .long, help: "Distance between fingers in points (default 40)")
    var spread: Double?

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    @ButtonHeistActor
    mutating func run() async throws {
        guard (try element.hasTarget) || (centerX != nil && centerY != nil) else {
            throw ValidationError("Must specify a heistId, -id, or --center-x/--center-y coordinates")
        }

        var request = Self.fenceRequest()
        try element.applyTo(&request)
        if let centerX { request.set(.centerX, centerX) }
        if let centerY { request.set(.centerY, centerY) }
        if let spread { request.set(.spread, spread) }

        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            request: request,
            statusMessage: "Sending gesture..."
        )
    }
}
