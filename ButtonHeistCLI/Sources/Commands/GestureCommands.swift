import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist
import ThePlans

struct CLIPointArgument: Equatable {
    let x: Double
    let y: Double

    static func required(x: Double?, y: Double?, label: String) throws -> Self {
        guard let x, let y else {
            throw ValidationError("Must specify \(label) x/y coordinates together")
        }
        return Self(x: x, y: y)
    }

    var object: CLIRequestObject {
        CommandArgumentWriter.object(
            CommandArgumentWriter.value(.x, x),
            CommandArgumentWriter.value(.y, y)
        )
    }

    var value: HeistValue {
        object.heistValue
    }
}

struct CLIGesturePayload: Equatable {
    let key: FenceParameterKey
    let object: CLIRequestObject

    static func element(_ target: ElementTarget) -> Self {
        Self(key: .element, object: CLIRequestBuilder.targetObject(target))
    }

    static func point(_ point: CLIPointArgument) -> Self {
        Self(key: .point, object: point.object)
    }

    static func elementUnitPoints(
        element: ElementTarget,
        start: CLIPointArgument,
        end: CLIPointArgument
    ) -> Self {
        Self(
            key: .elementUnitPoints,
            object: CommandArgumentWriter.object(
                CommandArgumentWriter.value(.element, CLIRequestBuilder.targetValue(element)),
                CommandArgumentWriter.value(.start, start.value),
                CommandArgumentWriter.value(.end, end.value)
            )
        )
    }

    static func elementDirection(element: ElementTarget, direction: String) -> Self {
        Self(
            key: .elementDirection,
            object: CommandArgumentWriter.object(
                CommandArgumentWriter.value(.element, CLIRequestBuilder.targetValue(element)),
                CommandArgumentWriter.value(.direction, direction)
            )
        )
    }

    static func pointDirection(start: CLIPointArgument, direction: String) -> Self {
        Self(
            key: .pointDirection,
            object: CommandArgumentWriter.object(
                CommandArgumentWriter.value(.start, start.value),
                CommandArgumentWriter.value(.direction, direction)
            )
        )
    }

    static func pointToPoint(start: CLIPointArgument, end: CLIPointArgument) -> Self {
        Self(
            key: .pointToPoint,
            object: CommandArgumentWriter.object(
                CommandArgumentWriter.value(.start, start.value),
                CommandArgumentWriter.value(.end, end.value)
            )
        )
    }

    static func elementToPoint(element: ElementTarget, end: CLIPointArgument) -> Self {
        Self(
            key: .elementToPoint,
            object: CommandArgumentWriter.object(
                CommandArgumentWriter.value(.element, CLIRequestBuilder.targetValue(element)),
                CommandArgumentWriter.value(.end, end.value)
            )
        )
    }
}

extension GestureCLICommandContract {
    static func gestureRequest(
        parameters: CLIRequestParameters = CLIRequestParameters(),
        _ payloads: CLIGesturePayload...
    ) throws -> TheFence.CommandArgumentEnvelope {
        fenceArguments(parameters.adding(payloads.map { payload in
            CommandArgumentWriter.value(payload.key, payload.object)
        }))
    }

    static func elementObject(_ target: ElementTarget) -> CLIRequestObject {
        CLIRequestBuilder.targetObject(target)
    }

    @ButtonHeistActor
    static func sendGesture(
        _ arguments: TheFence.CommandArgumentEnvelope,
        connection: ConnectionOptions,
        output: OutputOptions
    ) async throws {
        try await CLIRunner.run(
            connection: connection,
            format: output.format,
            command: fenceCommand,
            arguments: arguments,
            statusMessage: "Sending gesture..."
        )
    }
}

// MARK: - Tap

struct TapSubcommand: AsyncParsableCommand, GestureCLICommandContract {
    static let configuration = CommandConfiguration(
        commandName: Self.cliCommandName,
        abstract: "Explicit mechanical/spatial one-finger tap",
        discussion: """
            Performs an explicit mechanical/spatial gesture. Element-targeted \
            gestures use the element inflation path: resolve, reveal, acquire fresh accessibility \
            geometry, then dispatch the gesture. Coordinate gestures are \
            explicit viewport actions.

            Use one_finger_tap when the product intent is a spatial gesture \
            itself, for example a specific point on a canvas or map.
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
            throw ValidationError("Must specify --identifier, -l, or --x/--y coordinates")
        }

        let request: TheFence.CommandArgumentEnvelope
        if let target = try element.parsedTarget() {
            request = try Self.gestureRequest(.element(target))
        } else {
            request = try Self.gestureRequest(.point(CLIPointArgument.required(x: x, y: y, label: "--x/--y")))
        }
        try await Self.sendGesture(request, connection: connection, output: output)
    }
}

// MARK: - Long Press

struct LongPressSubcommand: AsyncParsableCommand, GestureCLICommandContract {
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
            throw ValidationError("Must specify --identifier, -l, or --x/--y coordinates")
        }

        let request: TheFence.CommandArgumentEnvelope
        let parameters = CommandArgumentWriter.parameters(
            CommandArgumentWriter.value(.duration, duration)
        )
        if let target = try element.parsedTarget() {
            request = try Self.gestureRequest(
                parameters: parameters,
                .element(target)
            )
        } else {
            request = try Self.gestureRequest(
                parameters: parameters,
                .point(CLIPointArgument.required(x: x, y: y, label: "--x/--y"))
            )
        }
        try await Self.sendGesture(request, connection: connection, output: output)
    }
}

// MARK: - Swipe

struct SwipeSubcommand: AsyncParsableCommand, GestureCLICommandContract {
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

    @Option(name: .shortAndLong, help: "Swipe direction: \(Self.catalogAllowedValuesDescription(for: .direction))")
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
                throw ValidationError("Unit-point swipe requires a semantic target (--identifier or -l)")
            }
            guard direction == nil, fromX == nil, fromY == nil, toX == nil, toY == nil else {
                throw ValidationError("Unit-point swipe cannot mix with direction or absolute coordinates")
            }
        } else {
            guard (try element.hasTarget) || (fromX != nil && fromY != nil) else {
                throw ValidationError("Must specify --identifier, -l, --from-x/--from-y, or --start-x/--start-y unit points")
            }
            if try element.hasTarget {
                guard direction != nil, fromX == nil, fromY == nil, toX == nil, toY == nil else {
                    throw ValidationError("Element swipe requires only --direction, or use unit-point start/end")
                }
            } else {
                guard (toX != nil && toY != nil) || direction != nil else {
                    throw ValidationError("Point swipe requires --to-x/--to-y or --direction")
                }
            }
        }

        let swipeDirection: String?
        if let dir = direction {
            guard let parsedDirection = Self.catalogCanonicalStringValue(dir, for: .direction) else {
                throw ValidationError("Invalid direction: \(dir). Valid: \(Self.catalogAllowedValuesDescription(for: .direction))")
            }
            swipeDirection = parsedDirection
        } else {
            swipeDirection = nil
        }

        let parameters = CommandArgumentWriter.parameters(
            CommandArgumentWriter.optional(.duration, duration)
        )
        let request: TheFence.CommandArgumentEnvelope
        if let startUnitX, let startUnitY, let endUnitX, let endUnitY {
            let target = try element.requireTarget()
            request = try Self.gestureRequest(
                parameters: parameters,
                .elementUnitPoints(
                    element: target,
                    start: CLIPointArgument(x: startUnitX, y: startUnitY),
                    end: CLIPointArgument(x: endUnitX, y: endUnitY)
                )
            )
        } else if let target = try element.parsedTarget() {
            guard let swipeDirection else {
                throw ValidationError("Element swipe requires --direction")
            }
            request = try Self.gestureRequest(
                parameters: parameters,
                .elementDirection(element: target, direction: swipeDirection)
            )
        } else if let swipeDirection {
            request = try Self.gestureRequest(
                parameters: parameters,
                .pointDirection(
                    start: CLIPointArgument.required(x: fromX, y: fromY, label: "--from-x/--from-y"),
                    direction: swipeDirection
                )
            )
        } else {
            request = try Self.gestureRequest(
                parameters: parameters,
                .pointToPoint(
                    start: CLIPointArgument.required(x: fromX, y: fromY, label: "--from-x/--from-y"),
                    end: CLIPointArgument.required(x: toX, y: toY, label: "--to-x/--to-y")
                )
            )
        }
        try await Self.sendGesture(request, connection: connection, output: output)
    }
}

// MARK: - Drag

struct DragSubcommand: AsyncParsableCommand, GestureCLICommandContract {
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
            throw ValidationError("Must specify --identifier, -l, or --from-x/--from-y coordinates")
        }

        let parameters = CommandArgumentWriter.parameters(
            CommandArgumentWriter.optional(.duration, duration)
        )
        let request: TheFence.CommandArgumentEnvelope
        if let target = try element.parsedTarget() {
            guard fromX == nil, fromY == nil else {
                throw ValidationError("Element drag cannot mix with --from-x/--from-y coordinates")
            }
            request = try Self.gestureRequest(
                parameters: parameters,
                .elementToPoint(
                    element: target,
                    end: CLIPointArgument(x: toX, y: toY)
                )
            )
        } else {
            request = try Self.gestureRequest(
                parameters: parameters,
                .pointToPoint(
                    start: CLIPointArgument.required(x: fromX, y: fromY, label: "--from-x/--from-y"),
                    end: CLIPointArgument(x: toX, y: toY)
                )
            )
        }
        try await Self.sendGesture(request, connection: connection, output: output)
    }
}
