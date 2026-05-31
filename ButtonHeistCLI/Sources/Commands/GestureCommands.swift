import ArgumentParser
import ButtonHeist

extension GestureCLICommandContract {
    static func gestureRequest(
        parameters: CLIRequestParameters = [:],
        element: ElementTargetOptions,
        numbers: [(FenceParameterKey, Double?)] = [],
        strings: [(FenceParameterKey, String?)] = [],
        objects: [(FenceParameterKey, [FenceParameterKey: HeistValue]?)] = []
    ) throws -> TheFence.CommandArgumentEnvelope {
        let target = try element.parsedTarget()
        var merged = parameters
        for (key, value) in numbers {
            if let value { merged[key] = .double(value) }
        }
        for (key, value) in strings {
            if let value { merged[key] = .string(value) }
        }
        for (key, value) in objects {
            if let value {
                merged[key] = .object(Dictionary(
                    value.map { ($0.key.rawValue, $0.value) },
                    uniquingKeysWith: { _, newest in newest }
                ))
            }
        }
        return fenceArguments(merged, target: target)
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
        abstract: "One-finger tap by semantic element or explicit coordinates",
        discussion: """
            Performs a one-finger tap. Element-targeted taps use the semantic \
            actionability path: resolve, reveal, acquire fresh accessibility \
            geometry, then dispatch the tap. Coordinate taps are explicit \
            viewport actions.

            Use one_finger_tap when you need precise coordinate-based taps \
            or when the product intent is a tap rather than primary activation \
            (for example, a specific point on a canvas or map).
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
            throw ValidationError("Must specify a heistId, --identifier, or --x/--y coordinates")
        }

        let request = try Self.gestureRequest(element: element, numbers: [(.x, x), (.y, y)])
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
            throw ValidationError("Must specify a heistId, --identifier, or --x/--y coordinates")
        }

        let request = try Self.gestureRequest(
            parameters: [.duration: .double(duration)],
            element: element,
            numbers: [(.x, x), (.y, y)]
        )
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
                throw ValidationError("Unit-point swipe requires a semantic target (heistId, --identifier, or -l)")
            }
        } else {
            guard (try element.hasTarget) || (fromX != nil && fromY != nil) else {
                throw ValidationError("Must specify a heistId, --identifier, --from-x/--from-y, or --start-x/--start-y unit points")
            }
            guard (toX != nil && toY != nil) || direction != nil else {
                throw ValidationError("Must specify --to-x/--to-y, --direction, or --end-x/--end-y unit points")
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

        let startObject: [FenceParameterKey: HeistValue]?
        if let startUnitX, let startUnitY {
            startObject = [.x: .double(startUnitX), .y: .double(startUnitY)]
        } else {
            startObject = nil
        }
        let endObject: [FenceParameterKey: HeistValue]?
        if let endUnitX, let endUnitY {
            endObject = [.x: .double(endUnitX), .y: .double(endUnitY)]
        } else {
            endObject = nil
        }
        let request = try Self.gestureRequest(
            element: element,
            numbers: [
                (.startX, fromX),
                (.startY, fromY),
                (.endX, toX),
                (.endY, toY),
                (.duration, duration),
            ],
            strings: [(.direction, swipeDirection)],
            objects: [(.start, startObject), (.end, endObject)]
        )
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
            throw ValidationError("Must specify a heistId, --identifier, or --from-x/--from-y coordinates")
        }

        let request = try Self.gestureRequest(
            parameters: [
                .endX: .double(toX),
                .endY: .double(toY),
            ],
            element: element,
            numbers: [(.startX, fromX), (.startY, fromY), (.duration, duration)]
        )
        try await Self.sendGesture(request, connection: connection, output: output)
    }
}
