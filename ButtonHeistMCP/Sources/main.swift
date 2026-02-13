import Foundation
import MCP
import ButtonHeist

// MARK: - Logging (stderr, never stdout — MCP uses stdout)

func log(_ message: String) {
    FileHandle.standardError.write(Data("[buttonheist-mcp] \(message)\n".utf8))
}

// MARK: - Tool Definitions

let snapshotTool = Tool(
    name: "get_snapshot",
    // swiftlint:disable:next line_length
    description: "Get the current UI element hierarchy from the connected iOS app. Returns a list of all accessibility elements with their labels, values, identifiers, frames, and available actions.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([:]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
)

let screenshotTool = Tool(
    name: "get_screenshot",
    description: "Capture a PNG screenshot of the connected iOS app's current screen.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([:]),
    ]),
    annotations: .init(readOnlyHint: true, openWorldHint: false)
)

let tapTool = Tool(
    name: "tap",
    description: "Tap an element or screen coordinate. Specify either an element (by identifier or order) or exact screen coordinates (x, y).",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "identifier": .object(["type": .string("string"), "description": .string("Element accessibility identifier")]),
            "order": .object(["type": .string("integer"), "description": .string("Element order index from snapshot (0-based)")]),
            "x": .object(["type": .string("number"), "description": .string("Screen X coordinate in points")]),
            "y": .object(["type": .string("number"), "description": .string("Screen Y coordinate in points")]),
        ]),
    ]),
    annotations: .init(readOnlyHint: false, idempotentHint: false, openWorldHint: false)
)

let longPressTool = Tool(
    name: "long_press",
    description: "Long press at an element or screen coordinate.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "identifier": .object(["type": .string("string"), "description": .string("Element accessibility identifier")]),
            "order": .object(["type": .string("integer"), "description": .string("Element order index from snapshot (0-based)")]),
            "x": .object(["type": .string("number"), "description": .string("Screen X coordinate")]),
            "y": .object(["type": .string("number"), "description": .string("Screen Y coordinate")]),
            "duration": .object(["type": .string("number"), "description": .string("Press duration in seconds (default 0.5)")]),
        ]),
    ]),
    annotations: .init(readOnlyHint: false, idempotentHint: false, openWorldHint: false)
)

let swipeTool = Tool(
    name: "swipe",
    // swiftlint:disable:next line_length
    description: "Swipe from a start point to an end point or in a direction. Start from an element or explicit coordinates. End with explicit coordinates, or use direction (up/down/left/right) with optional distance.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "identifier": .object(["type": .string("string"), "description": .string("Start from element's center (accessibility identifier)")]),
            "order": .object(["type": .string("integer"), "description": .string("Start from element's center (order index)")]),
            "startX": .object(["type": .string("number"), "description": .string("Start X coordinate")]),
            "startY": .object(["type": .string("number"), "description": .string("Start Y coordinate")]),
            "endX": .object(["type": .string("number"), "description": .string("End X coordinate")]),
            "endY": .object(["type": .string("number"), "description": .string("End Y coordinate")]),
            "direction": .object(["type": .string("string"), "description": .string("Swipe direction: up, down, left, right")]),
            "distance": .object(["type": .string("number"), "description": .string("Swipe distance in points (default 200)")]),
            "duration": .object(["type": .string("number"), "description": .string("Duration in seconds (default 0.15)")]),
        ]),
    ]),
    annotations: .init(readOnlyHint: false, idempotentHint: false, openWorldHint: false)
)

let dragTool = Tool(
    name: "drag",
    description: "Drag from a start point to an end point. Start from an element or explicit coordinates. End coordinates are required.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "identifier": .object(["type": .string("string"), "description": .string("Start from element's center")]),
            "order": .object(["type": .string("integer"), "description": .string("Start from element's center (order index)")]),
            "startX": .object(["type": .string("number"), "description": .string("Start X coordinate")]),
            "startY": .object(["type": .string("number"), "description": .string("Start Y coordinate")]),
            "endX": .object(["type": .string("number"), "description": .string("End X coordinate (required)")]),
            "endY": .object(["type": .string("number"), "description": .string("End Y coordinate (required)")]),
            "duration": .object(["type": .string("number"), "description": .string("Duration in seconds (default 0.5)")]),
        ]),
    ]),
    annotations: .init(readOnlyHint: false, idempotentHint: false, openWorldHint: false)
)

let pinchTool = Tool(
    name: "pinch",
    description: "Pinch/zoom gesture. Scale > 1.0 zooms in (fingers spread apart), < 1.0 zooms out (fingers pinch together).",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "identifier": .object(["type": .string("string"), "description": .string("Center on element")]),
            "order": .object(["type": .string("integer"), "description": .string("Center on element (order index)")]),
            "centerX": .object(["type": .string("number"), "description": .string("Center X coordinate")]),
            "centerY": .object(["type": .string("number"), "description": .string("Center Y coordinate")]),
            "scale": .object(["type": .string("number"), "description": .string("Scale factor (required). >1.0 = zoom in, <1.0 = zoom out")]),
            "spread": .object(["type": .string("number"), "description": .string("Initial finger spread in points (default 100)")]),
            "duration": .object(["type": .string("number"), "description": .string("Duration in seconds (default 0.5)")]),
        ]),
        "required": .array([.string("scale")]),
    ]),
    annotations: .init(readOnlyHint: false, idempotentHint: false, openWorldHint: false)
)

let rotateTool = Tool(
    name: "rotate",
    description: "Two-finger rotation gesture. Angle is in radians (positive = counter-clockwise).",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "identifier": .object(["type": .string("string"), "description": .string("Center on element")]),
            "order": .object(["type": .string("integer"), "description": .string("Center on element (order index)")]),
            "centerX": .object(["type": .string("number"), "description": .string("Center X coordinate")]),
            "centerY": .object(["type": .string("number"), "description": .string("Center Y coordinate")]),
            "angle": .object(["type": .string("number"), "description": .string("Rotation angle in radians (required)")]),
            "radius": .object(["type": .string("number"), "description": .string("Finger distance from center in points (default 100)")]),
            "duration": .object(["type": .string("number"), "description": .string("Duration in seconds (default 0.5)")]),
        ]),
        "required": .array([.string("angle")]),
    ]),
    annotations: .init(readOnlyHint: false, idempotentHint: false, openWorldHint: false)
)

let twoFingerTapTool = Tool(
    name: "two_finger_tap",
    description: "Simultaneous two-finger tap at an element or screen coordinate.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "identifier": .object(["type": .string("string"), "description": .string("Center on element")]),
            "order": .object(["type": .string("integer"), "description": .string("Center on element (order index)")]),
            "centerX": .object(["type": .string("number"), "description": .string("Center X coordinate")]),
            "centerY": .object(["type": .string("number"), "description": .string("Center Y coordinate")]),
            "spread": .object(["type": .string("number"), "description": .string("Distance between fingers in points (default 40)")]),
        ]),
    ]),
    annotations: .init(readOnlyHint: false, idempotentHint: false, openWorldHint: false)
)

let drawPathTool = Tool(
    name: "draw_path",
    // swiftlint:disable:next line_length
    description: "Draw along a path by tracing through a sequence of points. Useful for drawing shapes, writing characters, or following complex paths on canvas views.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "points": .object([
                "type": .string("array"),
                "description": .string("Array of {x, y} coordinate objects to trace through (minimum 2)"),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "x": .object(["type": .string("number"), "description": .string("X coordinate in screen points")]),
                        "y": .object(["type": .string("number"), "description": .string("Y coordinate in screen points")]),
                    ]),
                    "required": .array([.string("x"), .string("y")]),
                ]),
            ]),
            "duration": .object(["type": .string("number"), "description": .string("Total duration in seconds (mutually exclusive with velocity)")]),
            "velocity": .object(["type": .string("number"), "description": .string("Speed in points per second (mutually exclusive with duration)")]),
        ]),
        "required": .array([.string("points")]),
    ]),
    annotations: .init(readOnlyHint: false, idempotentHint: false, openWorldHint: false)
)

let drawBezierTool = Tool(
    name: "draw_bezier",
    // swiftlint:disable:next line_length
    description: "Draw along a cubic bezier curve path. Provide a start point and one or more bezier segments (each with two control points and an endpoint). The curve is sampled to a polyline and traced as a touch gesture. Useful for smooth curves, arcs, and organic shapes.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "startX": .object(["type": .string("number"), "description": .string("Start X coordinate")]),
            "startY": .object(["type": .string("number"), "description": .string("Start Y coordinate")]),
            "segments": .object([
                "type": .string("array"),
                "description": .string("Array of cubic bezier segments"),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "cp1X": .object(["type": .string("number"), "description": .string("First control point X")]),
                        "cp1Y": .object(["type": .string("number"), "description": .string("First control point Y")]),
                        "cp2X": .object(["type": .string("number"), "description": .string("Second control point X")]),
                        "cp2Y": .object(["type": .string("number"), "description": .string("Second control point Y")]),
                        "endX": .object(["type": .string("number"), "description": .string("Endpoint X")]),
                        "endY": .object(["type": .string("number"), "description": .string("Endpoint Y")]),
                    ]),
                    "required": .array([.string("cp1X"), .string("cp1Y"), .string("cp2X"), .string("cp2Y"), .string("endX"), .string("endY")]),
                ]),
            ]),
            "samplesPerSegment": .object(["type": .string("integer"), "description": .string("Points to sample per bezier segment (default 20)")]),
            "duration": .object(["type": .string("number"), "description": .string("Total duration in seconds (mutually exclusive with velocity)")]),
            "velocity": .object(["type": .string("number"), "description": .string("Speed in points per second (mutually exclusive with duration)")]),
        ]),
        "required": .array([.string("startX"), .string("startY"), .string("segments")]),
    ]),
    annotations: .init(readOnlyHint: false, idempotentHint: false, openWorldHint: false)
)

let activateTool = Tool(
    name: "activate",
    // swiftlint:disable:next line_length
    description: "Activate an element using accessibility API (equivalent to VoiceOver double-tap). Falls back to synthetic tap if accessibility activation fails.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "identifier": .object(["type": .string("string"), "description": .string("Element accessibility identifier")]),
            "order": .object(["type": .string("integer"), "description": .string("Element order index from snapshot (0-based)")]),
        ]),
    ]),
    annotations: .init(readOnlyHint: false, idempotentHint: false, openWorldHint: false)
)

let incrementTool = Tool(
    name: "increment",
    description: "Increment an adjustable element (slider, stepper, picker).",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "identifier": .object(["type": .string("string"), "description": .string("Element accessibility identifier")]),
            "order": .object(["type": .string("integer"), "description": .string("Element order index from snapshot (0-based)")]),
        ]),
    ]),
    annotations: .init(readOnlyHint: false, idempotentHint: false, openWorldHint: false)
)

let decrementTool = Tool(
    name: "decrement",
    description: "Decrement an adjustable element (slider, stepper, picker).",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "identifier": .object(["type": .string("string"), "description": .string("Element accessibility identifier")]),
            "order": .object(["type": .string("integer"), "description": .string("Element order index from snapshot (0-based)")]),
        ]),
    ]),
    annotations: .init(readOnlyHint: false, idempotentHint: false, openWorldHint: false)
)

let customActionTool = Tool(
    name: "perform_custom_action",
    // swiftlint:disable:next line_length
    description: "Perform a named custom accessibility action on an element. The action name must match one listed in the element's 'actions' array from get_snapshot.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "identifier": .object(["type": .string("string"), "description": .string("Element accessibility identifier")]),
            "order": .object(["type": .string("integer"), "description": .string("Element order index from snapshot (0-based)")]),
            "actionName": .object(["type": .string("string"), "description": .string("Name of the custom action to perform (required)")]),
        ]),
        "required": .array([.string("actionName")]),
    ]),
    annotations: .init(readOnlyHint: false, idempotentHint: false, openWorldHint: false)
)

let typeTextTool = Tool(
    name: "type_text",
    // swiftlint:disable:next line_length
    description: "Type text into a text field by tapping individual keyboard keys, and/or delete characters. Returns the current text field value after the operation. Use deleteCount to backspace before typing for corrections. The software keyboard must be visible (disable 'Connect Hardware Keyboard' in Simulator). Specify an element to target — it will be tapped to focus, and its value read back after typing.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "text": .object(["type": .string("string"), "description": .string("Text to type character-by-character")]),
            "deleteCount": .object(["type": .string("integer"), "description": .string("Number of delete key taps before typing (for corrections)")]),
            "identifier": .object(["type": .string("string"), "description": .string("Element accessibility identifier (focuses field, reads value)")]),
            "order": .object(["type": .string("integer"), "description": .string("Element order index (focuses field, reads value)")]),
        ]),
    ]),
    annotations: .init(readOnlyHint: false, idempotentHint: false, openWorldHint: false)
)

let allTools: [Tool] = [
    snapshotTool, screenshotTool,
    tapTool, longPressTool, swipeTool, dragTool, pinchTool, rotateTool, twoFingerTapTool,
    drawPathTool, drawBezierTool,
    activateTool, incrementTool, decrementTool, customActionTool,
    typeTextTool,
]

// MARK: - Argument Helpers

func stringArg(_ args: [String: Value]?, _ key: String) -> String? {
    args?[key]?.stringValue
}

func intArg(_ args: [String: Value]?, _ key: String) -> Int? {
    args?[key]?.intValue
}

func doubleArg(_ args: [String: Value]?, _ key: String) -> Double? {
    if let d = args?[key]?.doubleValue { return d }
    if let i = args?[key]?.intValue { return Double(i) }
    return nil
}

func elementTarget(_ args: [String: Value]?) -> ActionTarget? {
    let id = stringArg(args, "identifier")
    let order = intArg(args, "order")
    guard id != nil || order != nil else { return nil }
    return ActionTarget(identifier: id, order: order)
}

func errorResult(_ message: String) -> CallTool.Result {
    CallTool.Result(content: [.text(message)], isError: true)
}

// MARK: - Tool Call Handler

@MainActor
// swiftlint:disable:next cyclomatic_complexity function_body_length
func handleToolCall(_ params: CallTool.Parameters, client: HeistClient) async throws -> CallTool.Result {
    let args = params.arguments

    switch params.name {

    // MARK: Read Tools

    case "get_snapshot":
        client.send(.requestSnapshot)
        // Wait for the snapshot callback to fire
        let snapshot: Snapshot = try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                if !didResume {
                    didResume = true
                    continuation.resume(throwing: HeistClient.ActionError.timeout)
                }
            }
            client.onSnapshotUpdate = { payload in
                if !didResume {
                    didResume = true
                    timeoutTask.cancel()
                    continuation.resume(returning: payload)
                }
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let json = try encoder.encode(snapshot)
        return CallTool.Result(content: [.text(String(data: json, encoding: .utf8) ?? "{}")])

    case "get_screenshot":
        client.send(.requestScreenshot)
        let screenshot = try await client.waitForScreenshot(timeout: 30)
        return CallTool.Result(content: [
            .image(data: screenshot.pngData, mimeType: "image/png", metadata: nil),
        ])

    // MARK: Touch Gesture Tools

    case "tap":
        let target = elementTarget(args)
        let x = doubleArg(args, "x")
        let y = doubleArg(args, "y")
        let message: ClientMessage
        if let target {
            message = .touchTap(TouchTapTarget(elementTarget: target))
        } else if let x, let y {
            message = .touchTap(TouchTapTarget(pointX: x, pointY: y))
        } else {
            return errorResult("Must specify element (identifier or order) or coordinates (x, y)")
        }
        return try await sendAction(message, client: client)

    case "long_press":
        let target = elementTarget(args)
        let x = doubleArg(args, "x")
        let y = doubleArg(args, "y")
        let duration = doubleArg(args, "duration") ?? 0.5
        let message: ClientMessage
        if let target {
            message = .touchLongPress(LongPressTarget(elementTarget: target, duration: duration))
        } else if let x, let y {
            message = .touchLongPress(LongPressTarget(pointX: x, pointY: y, duration: duration))
        } else {
            return errorResult("Must specify element (identifier or order) or coordinates (x, y)")
        }
        return try await sendAction(message, client: client)

    case "swipe":
        let target = elementTarget(args)
        let startX = doubleArg(args, "startX")
        let startY = doubleArg(args, "startY")
        let endX = doubleArg(args, "endX")
        let endY = doubleArg(args, "endY")
        let dirStr = stringArg(args, "direction")
        let distance = doubleArg(args, "distance")
        let duration = doubleArg(args, "duration")

        var direction: SwipeDirection?
        if let dirStr {
            direction = SwipeDirection(rawValue: dirStr.lowercased())
            if direction == nil {
                return errorResult("Invalid direction '\(dirStr)'. Valid: up, down, left, right")
            }
        }

        let message = ClientMessage.touchSwipe(SwipeTarget(
            elementTarget: target,
            startX: startX, startY: startY,
            endX: endX, endY: endY,
            direction: direction, distance: distance,
            duration: duration
        ))
        return try await sendAction(message, client: client)

    case "drag":
        let target = elementTarget(args)
        let startX = doubleArg(args, "startX")
        let startY = doubleArg(args, "startY")
        guard let endX = doubleArg(args, "endX"), let endY = doubleArg(args, "endY") else {
            return errorResult("endX and endY are required for drag")
        }
        let duration = doubleArg(args, "duration")
        let message = ClientMessage.touchDrag(DragTarget(
            elementTarget: target,
            startX: startX, startY: startY,
            endX: endX, endY: endY,
            duration: duration
        ))
        return try await sendAction(message, client: client)

    case "pinch":
        let target = elementTarget(args)
        let centerX = doubleArg(args, "centerX")
        let centerY = doubleArg(args, "centerY")
        guard let scale = doubleArg(args, "scale") else {
            return errorResult("scale is required for pinch")
        }
        let spread = doubleArg(args, "spread")
        let duration = doubleArg(args, "duration")
        let message = ClientMessage.touchPinch(PinchTarget(
            elementTarget: target,
            centerX: centerX, centerY: centerY,
            scale: scale, spread: spread, duration: duration
        ))
        return try await sendAction(message, client: client)

    case "rotate":
        let target = elementTarget(args)
        let centerX = doubleArg(args, "centerX")
        let centerY = doubleArg(args, "centerY")
        guard let angle = doubleArg(args, "angle") else {
            return errorResult("angle is required for rotate")
        }
        let radius = doubleArg(args, "radius")
        let duration = doubleArg(args, "duration")
        let message = ClientMessage.touchRotate(RotateTarget(
            elementTarget: target,
            centerX: centerX, centerY: centerY,
            angle: angle, radius: radius, duration: duration
        ))
        return try await sendAction(message, client: client)

    case "two_finger_tap":
        let target = elementTarget(args)
        let centerX = doubleArg(args, "centerX")
        let centerY = doubleArg(args, "centerY")
        let spread = doubleArg(args, "spread")
        let message = ClientMessage.touchTwoFingerTap(TwoFingerTapTarget(
            elementTarget: target,
            centerX: centerX, centerY: centerY,
            spread: spread
        ))
        return try await sendAction(message, client: client)

    case "draw_path":
        guard let pointsValue = args?["points"]?.arrayValue else {
            return errorResult("points array is required")
        }
        let pathPoints: [PathPoint] = try pointsValue.compactMap { value in
            guard let obj = value.objectValue,
                  let x = obj["x"]?.doubleValue ?? obj["x"]?.intValue.map(Double.init),
                  let y = obj["y"]?.doubleValue ?? obj["y"]?.intValue.map(Double.init) else {
                throw MCPError.invalidParams("Each point must have x and y numbers")
            }
            return PathPoint(x: x, y: y)
        }
        guard pathPoints.count >= 2 else {
            return errorResult("Path requires at least 2 points")
        }
        let dpDuration = doubleArg(args, "duration")
        let dpVelocity = doubleArg(args, "velocity")
        let dpMessage = ClientMessage.touchDrawPath(DrawPathTarget(
            points: pathPoints,
            duration: dpDuration,
            velocity: dpVelocity
        ))
        return try await sendAction(dpMessage, client: client)

    case "draw_bezier":
        guard let startX = doubleArg(args, "startX"),
              let startY = doubleArg(args, "startY") else {
            return errorResult("startX and startY are required")
        }
        guard let segmentsValue = args?["segments"]?.arrayValue else {
            return errorResult("segments array is required")
        }
        let segments: [BezierSegment] = try segmentsValue.map { value in
            guard let obj = value.objectValue,
                  let cp1X = obj["cp1X"]?.doubleValue ?? obj["cp1X"]?.intValue.map(Double.init),
                  let cp1Y = obj["cp1Y"]?.doubleValue ?? obj["cp1Y"]?.intValue.map(Double.init),
                  let cp2X = obj["cp2X"]?.doubleValue ?? obj["cp2X"]?.intValue.map(Double.init),
                  let cp2Y = obj["cp2Y"]?.doubleValue ?? obj["cp2Y"]?.intValue.map(Double.init),
                  let endX = obj["endX"]?.doubleValue ?? obj["endX"]?.intValue.map(Double.init),
                  let endY = obj["endY"]?.doubleValue ?? obj["endY"]?.intValue.map(Double.init) else {
                throw MCPError.invalidParams("Each segment needs cp1X, cp1Y, cp2X, cp2Y, endX, endY")
            }
            return BezierSegment(cp1X: cp1X, cp1Y: cp1Y, cp2X: cp2X, cp2Y: cp2Y, endX: endX, endY: endY)
        }
        guard !segments.isEmpty else {
            return errorResult("At least 1 bezier segment is required")
        }
        let dbSamples = intArg(args, "samplesPerSegment")
        let dbDuration = doubleArg(args, "duration")
        let dbVelocity = doubleArg(args, "velocity")
        let dbMessage = ClientMessage.touchDrawBezier(DrawBezierTarget(
            startX: startX, startY: startY,
            segments: segments,
            samplesPerSegment: dbSamples,
            duration: dbDuration,
            velocity: dbVelocity
        ))
        return try await sendAction(dbMessage, client: client)

    // MARK: Accessibility Action Tools

    case "activate":
        guard let target = elementTarget(args) else {
            return errorResult("Must specify element identifier or order")
        }
        return try await sendAction(.activate(target), client: client)

    case "increment":
        guard let target = elementTarget(args) else {
            return errorResult("Must specify element identifier or order")
        }
        return try await sendAction(.increment(target), client: client)

    case "decrement":
        guard let target = elementTarget(args) else {
            return errorResult("Must specify element identifier or order")
        }
        return try await sendAction(.decrement(target), client: client)

    case "perform_custom_action":
        guard let target = elementTarget(args) else {
            return errorResult("Must specify element identifier or order")
        }
        guard let actionName = stringArg(args, "actionName") else {
            return errorResult("actionName is required")
        }
        let customTarget = CustomActionTarget(elementTarget: target, actionName: actionName)
        return try await sendAction(.performCustomAction(customTarget), client: client)

    case "type_text":
        let text = stringArg(args, "text")
        let deleteCount = intArg(args, "deleteCount")
        guard text != nil || deleteCount != nil else {
            return errorResult("Must specify text, deleteCount, or both")
        }
        let target = elementTarget(args)
        let message = ClientMessage.typeText(TypeTextTarget(
            text: text,
            deleteCount: deleteCount,
            elementTarget: target
        ))
        client.send(message)
        let typeResult = try await client.waitForActionResult(timeout: 30)
        if typeResult.success {
            var content: [Tool.Content] = [
                .text("Success (method: \(typeResult.method.rawValue))"),
            ]
            if let value = typeResult.value {
                content.append(.text("Value: \(value)"))
            }
            return CallTool.Result(content: content)
        } else {
            let errorMsg = typeResult.message ?? typeResult.method.rawValue
            return CallTool.Result(content: [.text("Failed: \(errorMsg)")], isError: true)
        }

    default:
        throw MCPError.methodNotFound("Unknown tool: \(params.name)")
    }
}

/// Send a ClientMessage and wait for ActionResult
@MainActor
func sendAction(_ message: ClientMessage, client: HeistClient) async throws -> CallTool.Result {
    client.send(message)
    let result = try await client.waitForActionResult(timeout: 15)
    if result.success {
        return CallTool.Result(content: [
            .text("Success (method: \(result.method.rawValue))"),
        ])
    } else {
        let errorMsg = result.message ?? result.method.rawValue
        return CallTool.Result(content: [.text("Failed: \(errorMsg)")], isError: true)
    }
}

// MARK: - Device Connection

@MainActor
func discoverAndConnect(client: HeistClient) async throws {
    log("Starting device discovery...")
    client.startDiscovery()

    // Wait for a device (up to 30 seconds)
    let deadline = Date().addingTimeInterval(30)
    while client.discoveredDevices.isEmpty {
        if Date() > deadline {
            throw MCPError.internalError("No iOS devices found within 30 seconds. Ensure an app with InsideMan is running.")
        }
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    }

    let device = client.discoveredDevices[0]
    log("Found device: \(device.name)")

    // Connect and wait
    client.connect(to: device)
    let connectDeadline = Date().addingTimeInterval(10)
    while client.connectionState != .connected {
        if Date() > connectDeadline {
            throw MCPError.internalError("Connection to device timed out")
        }
        if case .failed(let msg) = client.connectionState {
            throw MCPError.internalError("Connection failed: \(msg)")
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    log("Connected to \(device.name)")
}

// MARK: - Entry Point

@main
struct ButtonHeistMCP {
    @MainActor
    static func main() async throws {
        let client = HeistClient()

        try await discoverAndConnect(client: client)

        log("Starting MCP server...")

        // Create MCP server
        let server = Server(
            name: "buttonheist",
            version: "1.0.0",
            instructions: """
                ButtonHeist MCP server for iOS app automation. \
                Use get_snapshot to read the UI element hierarchy, \
                get_screenshot to see the screen, \
                and interaction tools (tap, swipe, etc.) to drive the app. \
                Elements can be targeted by accessibility identifier or order index from the snapshot.
                """,
            capabilities: .init(tools: .init(listChanged: false))
        )

        // Register tool list handler
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: allTools)
        }

        // Register tool call handler — bridge from Server actor to MainActor
        await server.withMethodHandler(CallTool.self) { params in
            try await handleToolCall(params, client: client)
        }

        // Start stdio transport
        let transport = StdioTransport()
        try await server.start(transport: transport)
        log("MCP server running")
        await server.waitUntilCompleted()
    }
}
