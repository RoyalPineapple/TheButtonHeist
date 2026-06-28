import ArgumentParser
import ButtonHeist
import ThePlans

extension GestureCLICommandContract {
    static func gestureRequest(
        parameters: CLIRequestParameters = [:],
        objects: [(FenceParameterKey, [FenceParameterKey: HeistValue]?)] = []
    ) throws -> TheFence.CommandArgumentEnvelope {
        var merged = parameters
        for (key, value) in objects {
            if let value {
                merged[key] = .object(Dictionary(
                    value.map { ($0.key.rawValue, $0.value) },
                    uniquingKeysWith: { _, newest in newest }
                ))
            }
        }
        return fenceArguments(merged)
    }

    static func elementObject(_ target: ElementTarget) -> [FenceParameterKey: HeistValue] {
        Dictionary(
            CLIRequestBuilder.targetObject(target).compactMap { key, value in
                FenceParameterKey(rawValue: key).map { ($0, value) }
            },
            uniquingKeysWith: { _, newest in newest }
        )
    }

    static func pointObject(x: Double, y: Double) -> [FenceParameterKey: HeistValue] {
        [.x: .double(x), .y: .double(y)]
    }

    static func valueObject(_ object: [FenceParameterKey: HeistValue]) -> HeistValue {
        .object(Dictionary(
            object.map { ($0.key.rawValue, $0.value) },
            uniquingKeysWith: { _, newest in newest }
        ))
    }

    static func requiredPointObject(x: Double?, y: Double?, label: String) throws -> [FenceParameterKey: HeistValue] {
        guard let x, let y else {
            throw ValidationError("Must specify \(label) x/y coordinates together")
        }
        return pointObject(x: x, y: y)
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
            request = try Self.gestureRequest(objects: [(.element, Self.elementObject(target))])
        } else {
            request = try Self.gestureRequest(objects: [(.point, Self.requiredPointObject(x: x, y: y, label: "--x/--y"))])
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
        if let target = try element.parsedTarget() {
            request = try Self.gestureRequest(
                parameters: [.duration: .double(duration)],
                objects: [(.element, Self.elementObject(target))]
            )
        } else {
            request = try Self.gestureRequest(
                parameters: [.duration: .double(duration)],
                objects: [(.point, Self.requiredPointObject(x: x, y: y, label: "--x/--y"))]
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

        var parameters: CLIRequestParameters = [:]
        if let duration { parameters[.duration] = .double(duration) }
        let request: TheFence.CommandArgumentEnvelope
        if let startUnitX, let startUnitY, let endUnitX, let endUnitY {
            let target = try element.requireTarget()
            request = try Self.gestureRequest(
                parameters: parameters,
                objects: [
                    (.elementUnitPoints, [
                        .element: Self.valueObject(Self.elementObject(target)),
                        .start: Self.valueObject(Self.pointObject(x: startUnitX, y: startUnitY)),
                        .end: Self.valueObject(Self.pointObject(x: endUnitX, y: endUnitY)),
                    ]),
                ]
            )
        } else if let target = try element.parsedTarget() {
            guard let swipeDirection else {
                throw ValidationError("Element swipe requires --direction")
            }
            request = try Self.gestureRequest(
                parameters: parameters,
                objects: [
                    (.elementDirection, [
                        .element: Self.valueObject(Self.elementObject(target)),
                        .direction: .string(swipeDirection),
                    ]),
                ]
            )
        } else if let swipeDirection {
            request = try Self.gestureRequest(
                parameters: parameters,
                objects: [
                    (.pointDirection, [
                        .start: Self.valueObject(Self.requiredPointObject(x: fromX, y: fromY, label: "--from-x/--from-y")),
                        .direction: .string(swipeDirection),
                    ]),
                ]
            )
        } else {
            request = try Self.gestureRequest(
                parameters: parameters,
                objects: [
                    (.pointToPoint, [
                        .start: Self.valueObject(Self.requiredPointObject(x: fromX, y: fromY, label: "--from-x/--from-y")),
                        .end: Self.valueObject(Self.requiredPointObject(x: toX, y: toY, label: "--to-x/--to-y")),
                    ]),
                ]
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

        var parameters: CLIRequestParameters = [:]
        if let duration { parameters[.duration] = .double(duration) }
        let request: TheFence.CommandArgumentEnvelope
        if let target = try element.parsedTarget() {
            guard fromX == nil, fromY == nil else {
                throw ValidationError("Element drag cannot mix with --from-x/--from-y coordinates")
            }
            request = try Self.gestureRequest(
                parameters: parameters,
                objects: [
                    (.elementToPoint, [
                        .element: Self.valueObject(Self.elementObject(target)),
                        .end: Self.valueObject(Self.pointObject(x: toX, y: toY)),
                    ]),
                ]
            )
        } else {
            request = try Self.gestureRequest(
                parameters: parameters,
                objects: [
                    (.pointToPoint, [
                        .start: Self.valueObject(Self.requiredPointObject(x: fromX, y: fromY, label: "--from-x/--from-y")),
                        .end: Self.valueObject(Self.pointObject(x: toX, y: toY)),
                    ]),
                ]
            )
        }
        try await Self.sendGesture(request, connection: connection, output: output)
    }
}
