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
    static let configuration = CommandConfiguration(commandName: "tap", abstract: "Tap at a point or element")

    @Option(name: .long, help: "Element identifier")
    var identifier: String?

    @Option(name: .long, help: "Element index")
    var index: Int?

    @Option(name: .long, help: "X coordinate")
    var x: Double?

    @Option(name: .long, help: "Y coordinate")
    var y: Double?

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

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

        try await sendTouchGesture(message: message, timeout: timeout, quiet: quiet)
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

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

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

        try await sendTouchGesture(message: message, timeout: timeout, quiet: quiet)
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

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

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

        try await sendTouchGesture(message: message, timeout: timeout, quiet: quiet)
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

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

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

        try await sendTouchGesture(message: message, timeout: timeout, quiet: quiet)
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

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

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

        try await sendTouchGesture(message: message, timeout: timeout, quiet: quiet)
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

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

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

        try await sendTouchGesture(message: message, timeout: timeout, quiet: quiet)
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

    @Option(name: .shortAndLong, help: "Timeout in seconds")
    var timeout: Double = 10.0

    @Flag(name: .shortAndLong, help: "Suppress status messages")
    var quiet: Bool = false

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

        try await sendTouchGesture(message: message, timeout: timeout, quiet: quiet)
    }
}

// MARK: - Shared Connection Helper

@MainActor
private func sendTouchGesture(message: ClientMessage, timeout: Double, quiet: Bool) async throws {
    let client = HeistClient()

    if !quiet {
        logStatus("Searching for iOS devices...")
    }

    client.startDiscovery()

    let discoveryTimeout: UInt64 = 5_000_000_000
    let startTime = DispatchTime.now()
    while client.discoveredDevices.isEmpty {
        if DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds > discoveryTimeout {
            throw ValidationError("No devices found within timeout")
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    guard let device = client.discoveredDevices.first else {
        throw ValidationError("No devices found")
    }

    if !quiet {
        logStatus("Found device: \(device.name)")
        logStatus("Connecting...")
    }

    var connected = false
    var connectionError: Error?

    client.onConnected = { _ in connected = true }
    client.onDisconnected = { error in connectionError = error }

    client.connect(to: device)

    let connectionTimeout: UInt64 = 5_000_000_000
    let connectionStart = DispatchTime.now()
    while !connected && connectionError == nil {
        if DispatchTime.now().uptimeNanoseconds - connectionStart.uptimeNanoseconds > connectionTimeout {
            throw ValidationError("Connection timed out")
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    if let error = connectionError {
        throw ValidationError("Connection failed: \(error.localizedDescription)")
    }

    if !quiet {
        logStatus("Connected")
    }

    defer {
        client.disconnect()
        client.stopDiscovery()
    }

    if !quiet {
        logStatus("Sending gesture...")
    }

    client.send(message)

    let result = try await client.waitForActionResult(timeout: timeout)

    if result.success {
        if !quiet {
            logStatus("Gesture succeeded (method: \(result.method.rawValue))")
        }
        writeOutput("success")
    } else {
        let errorMessage = result.message ?? result.method.rawValue
        if !quiet {
            logStatus("Gesture failed: \(errorMessage)")
        }
        writeOutput("failed: \(errorMessage)")
        Darwin.exit(1)
    }
}
