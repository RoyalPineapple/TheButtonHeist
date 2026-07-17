import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist
import ThePlans

private func requiredScreenPoint(x: Double?, y: Double?, label: String) throws -> ScreenPoint {
    guard let x, let y else {
        throw ValidationError("Must specify \(label) x/y coordinates together")
    }
    return ScreenPoint(x: x, y: y)
}

// MARK: - Tap

struct TapSubcommand: ConnectedOneShotCLICommand {
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

    @OptionGroup var element: AccessibilityTargetOptions

    @Option(name: .long, help: "X coordinate")
    var x: Double?

    @Option(name: .long, help: "Y coordinate")
    var y: Double?

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    var runnerStatusMessage: String? { "Sending gesture..." }

    func requestArguments() throws -> TheFence.CommandArgumentEnvelope {
        guard (try element.hasTarget) || (x != nil && y != nil) else {
            throw ValidationError("Must specify --identifier, -l, or --x/--y coordinates")
        }

        let selection: GesturePointSelection
        if let target = try element.parsedTarget() {
            selection = .element(target)
        } else {
            selection = .coordinate(try requiredScreenPoint(x: x, y: y, label: "--x/--y"))
        }
        return Self.fenceArguments(payload: TapTarget(selection: selection))
    }
}

// MARK: - Long Press

struct LongPressSubcommand: ConnectedOneShotCLICommand {
    static let configuration = CommandConfiguration(commandName: Self.cliCommandName, abstract: "Long press at a point or element")

    @OptionGroup var element: AccessibilityTargetOptions

    @Option(name: .long, help: "X coordinate")
    var x: Double?

    @Option(name: .long, help: "Y coordinate")
    var y: Double?

    @Option(name: .long, help: "Press duration in seconds (default 0.5)")
    var duration: Double = 0.5

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    var runnerStatusMessage: String? { "Sending gesture..." }

    func requestArguments() throws -> TheFence.CommandArgumentEnvelope {
        guard (try element.hasTarget) || (x != nil && y != nil) else {
            throw ValidationError("Must specify --identifier, -l, or --x/--y coordinates")
        }

        let selection: GesturePointSelection
        if let target = try element.parsedTarget() {
            selection = .element(target)
        } else {
            selection = .coordinate(try requiredScreenPoint(x: x, y: y, label: "--x/--y"))
        }
        return Self.fenceArguments(payload: LongPressTarget(
            selection: selection,
            duration: try GestureDuration(validatingSeconds: duration)
        ))
    }
}

// MARK: - Swipe

struct SwipeSubcommand: ConnectedOneShotCLICommand {
    static let configuration = CommandConfiguration(commandName: Self.cliCommandName, abstract: "Swipe between two points or in a direction")

    @OptionGroup var element: AccessibilityTargetOptions

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

    @Option(name: .shortAndLong, help: "Swipe direction: \(Self.catalogAllowedValuesDescription(for: FenceParameters.swipeDirection))")
    var direction: String?

    @Option(name: .long, help: "Duration in seconds (default 0.15)")
    var duration: Double?

    @OptionGroup var connection: ConnectionOptions
    @OptionGroup var output: OutputOptions

    var runnerStatusMessage: String? { "Sending gesture..." }

    func requestArguments() throws -> TheFence.CommandArgumentEnvelope {
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

        let swipeDirection: SwipeDirection?
        if let dir = direction {
            guard let parsedDirection = Self.catalogCanonicalValue(dir, for: FenceParameters.swipeDirection) else {
                throw ValidationError("Invalid direction: \(dir). Valid: \(Self.catalogAllowedValuesDescription(for: FenceParameters.swipeDirection))")
            }
            swipeDirection = parsedDirection
        } else {
            swipeDirection = nil
        }

        let selection: SwipeGestureSelection
        if let startUnitX, let startUnitY, let endUnitX, let endUnitY {
            let target = try element.requireTarget()
            selection = .unitElement(
                target,
                start: UnitPoint(x: startUnitX, y: startUnitY),
                end: UnitPoint(x: endUnitX, y: endUnitY)
            )
        } else if let target = try element.parsedTarget() {
            guard let swipeDirection else {
                throw ValidationError("Element swipe requires --direction")
            }
            selection = .elementDirection(target, swipeDirection)
        } else if let swipeDirection {
            selection = .pointDirection(
                start: try requiredScreenPoint(x: fromX, y: fromY, label: "--from-x/--from-y"),
                direction: swipeDirection
            )
        } else {
            selection = .pointToPoint(
                start: try requiredScreenPoint(x: fromX, y: fromY, label: "--from-x/--from-y"),
                end: try requiredScreenPoint(x: toX, y: toY, label: "--to-x/--to-y")
            )
        }
        return Self.fenceArguments(payload: SwipeTarget(
            selection: selection,
            duration: try duration.map(GestureDuration.init(validatingSeconds:))
        ))
    }
}

// MARK: - Drag

struct DragSubcommand: ConnectedOneShotCLICommand {
    static let configuration = CommandConfiguration(commandName: Self.cliCommandName, abstract: "Drag from one point to another")

    @OptionGroup var element: AccessibilityTargetOptions

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

    var runnerStatusMessage: String? { "Sending gesture..." }

    func requestArguments() throws -> TheFence.CommandArgumentEnvelope {
        guard (try element.hasTarget) || (fromX != nil && fromY != nil) else {
            throw ValidationError("Must specify --identifier, -l, or --from-x/--from-y coordinates")
        }

        let selection: DragGestureSelection
        let end = ScreenPoint(x: toX, y: toY)
        if let target = try element.parsedTarget() {
            guard fromX == nil, fromY == nil else {
                throw ValidationError("Element drag cannot mix with --from-x/--from-y coordinates")
            }
            selection = .elementToPoint(target, start: nil, end: end)
        } else {
            selection = .pointToPoint(
                start: try requiredScreenPoint(x: fromX, y: fromY, label: "--from-x/--from-y"),
                end: end
            )
        }
        return Self.fenceArguments(payload: DragTarget(
            selection: selection,
            duration: try duration.map(GestureDuration.init(validatingSeconds:))
        ))
    }
}
