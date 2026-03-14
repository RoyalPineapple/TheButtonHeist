import Foundation
import TheScore

@ButtonHeistActor
extension TheFence {

    // MARK: - Handler: Interface

    func handleGetInterface() async throws -> Interface {
        try await sendAndAwait(.requestInterface) { requestId in
            try await client.waitForInterface(requestId: requestId, timeout: Timeouts.actionSeconds)
        }
    }

    // MARK: - Handler: Screen

    func handleGetScreen(_ args: [String: Any]) async throws -> FenceResponse {
        let screen: ScreenPayload = try await sendAndAwait(.requestScreen) { requestId in
            try await client.waitForScreen(requestId: requestId, timeout: 30)
        }
        if let outputPath = stringArg(args, "output") {
            guard !outputPath.split(separator: "/").contains("..") else {
                return .error("Invalid output path: must not contain '..' components")
            }
            let resolvedURL = URL(fileURLWithPath: outputPath).standardized
            guard let pngData = Data(base64Encoded: screen.pngData) else {
                return .error("Failed to decode screenshot data")
            }
            try pngData.write(to: resolvedURL)
            return .screenshot(path: resolvedURL.path, width: screen.width, height: screen.height)
        }
        return .screenshotData(pngData: screen.pngData, width: screen.width, height: screen.height)
    }

    // MARK: - Handler: Gestures

    func handleGesture(command: Command, args: [String: Any]) async throws -> FenceResponse {
        switch command {
        case .oneFingerTap:
            return try await handleOneFingerTap(args)
        case .longPress:
            return try await handleLongPress(args)
        case .swipe:
            return try await handleSwipe(args)
        case .drag:
            return try await handleDrag(args)
        case .pinch:
            return try await handlePinch(args)
        case .rotate:
            return try await handleRotate(args)
        case .twoFingerTap:
            return try await handleTwoFingerTap(args)
        case .drawPath:
            return try await handleDrawPath(args)
        case .drawBezier:
            return try await handleDrawBezier(args)
        default:
            return .error("Unknown gesture: \(command.rawValue)")
        }
    }

    private func handleOneFingerTap(_ args: [String: Any]) async throws -> FenceResponse {
        let target = elementTarget(args)
        let x = doubleArg(args, "x")
        let y = doubleArg(args, "y")
        if let target {
            return try await sendAction(.touchTap(TouchTapTarget(elementTarget: target)))
        } else if let x, let y {
            return try await sendAction(.touchTap(TouchTapTarget(pointX: x, pointY: y)))
        }
        return .error("Must specify element (identifier or order) or coordinates (x, y)")
    }

    private func handleLongPress(_ args: [String: Any]) async throws -> FenceResponse {
        let target = elementTarget(args)
        let x = doubleArg(args, "x")
        let y = doubleArg(args, "y")
        let duration = doubleArg(args, "duration") ?? 0.5
        if let target {
            return try await sendAction(.touchLongPress(LongPressTarget(elementTarget: target, duration: duration)))
        } else if let x, let y {
            return try await sendAction(.touchLongPress(LongPressTarget(pointX: x, pointY: y, duration: duration)))
        }
        return .error("Must specify element (identifier or order) or coordinates (x, y)")
    }

    private func handleSwipe(_ args: [String: Any]) async throws -> FenceResponse {
        let directionValue = stringArg(args, "direction")
        var direction: SwipeDirection?
        if let directionValue {
            direction = SwipeDirection(rawValue: directionValue.lowercased())
            if direction == nil {
                return .error("Invalid direction '\(directionValue)'. Valid: up, down, left, right")
            }
        }
        return try await sendAction(
            .touchSwipe(SwipeTarget(
                elementTarget: elementTarget(args),
                startX: doubleArg(args, "startX"), startY: doubleArg(args, "startY"),
                endX: doubleArg(args, "endX"), endY: doubleArg(args, "endY"),
                direction: direction, distance: doubleArg(args, "distance"),
                duration: doubleArg(args, "duration")
            ))
        )
    }

    private func handleDrag(_ args: [String: Any]) async throws -> FenceResponse {
        guard let endX = doubleArg(args, "endX"), let endY = doubleArg(args, "endY") else {
            return .error("endX and endY are required for drag")
        }
        return try await sendAction(
            .touchDrag(DragTarget(
                elementTarget: elementTarget(args),
                startX: doubleArg(args, "startX") ?? doubleArg(args, "x"),
                startY: doubleArg(args, "startY") ?? doubleArg(args, "y"),
                endX: endX, endY: endY, duration: doubleArg(args, "duration")
            ))
        )
    }

    private func handlePinch(_ args: [String: Any]) async throws -> FenceResponse {
        guard let scale = doubleArg(args, "scale") else {
            return .error("scale is required for pinch")
        }
        return try await sendAction(
            .touchPinch(PinchTarget(
                elementTarget: elementTarget(args),
                centerX: doubleArg(args, "centerX") ?? doubleArg(args, "x"),
                centerY: doubleArg(args, "centerY") ?? doubleArg(args, "y"),
                scale: scale, spread: doubleArg(args, "spread"),
                duration: doubleArg(args, "duration")
            ))
        )
    }

    private func handleRotate(_ args: [String: Any]) async throws -> FenceResponse {
        guard let angle = doubleArg(args, "angle") else {
            return .error("angle is required for rotate")
        }
        return try await sendAction(
            .touchRotate(RotateTarget(
                elementTarget: elementTarget(args),
                centerX: doubleArg(args, "centerX") ?? doubleArg(args, "x"),
                centerY: doubleArg(args, "centerY") ?? doubleArg(args, "y"),
                angle: angle, radius: doubleArg(args, "radius"),
                duration: doubleArg(args, "duration")
            ))
        )
    }

    private func handleTwoFingerTap(_ args: [String: Any]) async throws -> FenceResponse {
        return try await sendAction(
            .touchTwoFingerTap(TwoFingerTapTarget(
                elementTarget: elementTarget(args),
                centerX: doubleArg(args, "centerX") ?? doubleArg(args, "x"),
                centerY: doubleArg(args, "centerY") ?? doubleArg(args, "y"),
                spread: doubleArg(args, "spread")
            ))
        )
    }

    private func handleDrawPath(_ args: [String: Any]) async throws -> FenceResponse {
        guard let pointsArray = args["points"] as? [[String: Any]] else {
            return .error("points must be an array of {x, y} objects")
        }
        var pathPoints: [PathPoint] = []
        for point in pointsArray {
            guard let x = numberArg(point["x"]), let y = numberArg(point["y"]) else {
                return .error("Each point must have numeric x and y fields")
            }
            pathPoints.append(PathPoint(x: x, y: y))
        }
        guard pathPoints.count >= 2 else {
            return .error("Path requires at least 2 points")
        }
        return try await sendAction(
            .touchDrawPath(DrawPathTarget(
                points: pathPoints,
                duration: doubleArg(args, "duration"),
                velocity: doubleArg(args, "velocity")
            ))
        )
    }

    private func handleDrawBezier(_ args: [String: Any]) async throws -> FenceResponse {
        guard let startX = doubleArg(args, "startX"), let startY = doubleArg(args, "startY") else {
            return .error("startX and startY are required")
        }
        guard let segmentsArray = args["segments"] as? [[String: Any]] else {
            return .error("segments array is required")
        }
        var segments: [BezierSegment] = []
        for segment in segmentsArray {
            guard
                let cp1X = numberArg(segment["cp1X"]), let cp1Y = numberArg(segment["cp1Y"]),
                let cp2X = numberArg(segment["cp2X"]), let cp2Y = numberArg(segment["cp2Y"]),
                let endX = numberArg(segment["endX"]), let endY = numberArg(segment["endY"])
            else {
                return .error("Each segment needs cp1X, cp1Y, cp2X, cp2Y, endX, endY")
            }
            segments.append(BezierSegment(cp1X: cp1X, cp1Y: cp1Y, cp2X: cp2X, cp2Y: cp2Y, endX: endX, endY: endY))
        }
        guard !segments.isEmpty else {
            return .error("At least 1 bezier segment is required")
        }
        return try await sendAction(
            .touchDrawBezier(DrawBezierTarget(
                startX: startX, startY: startY, segments: segments,
                samplesPerSegment: intArg(args, "samplesPerSegment"),
                duration: doubleArg(args, "duration"), velocity: doubleArg(args, "velocity")
            ))
        )
    }

    // MARK: - Handler: Scroll Actions

    func handleScrollAction(command: Command, args: [String: Any]) async throws -> FenceResponse {
        switch command {
        case .scroll:
            guard let directionValue = stringArg(args, "direction") else {
                return .error("direction is required for scroll. Valid: up, down, left, right, next, previous")
            }
            guard let direction = ScrollDirection(rawValue: directionValue.lowercased()) else {
                return .error("Invalid direction '\(directionValue)'. Valid: up, down, left, right, next, previous")
            }
            guard elementTarget(args) != nil else {
                return .error("Must specify element (identifier or order) for scroll")
            }
            return try await sendAction(
                .scroll(ScrollTarget(elementTarget: elementTarget(args), direction: direction))
            )
        case .scrollToVisible:
            guard let target = elementTarget(args) else {
                return .error("Must specify element (identifier or order) for scroll_to_visible")
            }
            return try await sendAction(.scrollToVisible(target))
        case .scrollToEdge:
            guard let edgeValue = stringArg(args, "edge") else {
                return .error("edge is required for scroll_to_edge. Valid: top, bottom, left, right")
            }
            guard let edge = ScrollEdge(rawValue: edgeValue.lowercased()) else {
                return .error("Invalid edge '\(edgeValue)'. Valid: top, bottom, left, right")
            }
            guard let target = elementTarget(args) else {
                return .error("Must specify element (identifier or order) for scroll_to_edge")
            }
            return try await sendAction(.scrollToEdge(ScrollToEdgeTarget(elementTarget: target, edge: edge)))
        default:
            return .error("Unknown scroll action: \(command.rawValue)")
        }
    }

    // MARK: - Handler: Accessibility Actions

    func handleAccessibilityAction(command: Command, args: [String: Any]) async throws -> FenceResponse {
        switch command {
        case .activate:
            guard let target = elementTarget(args) else {
                return .error("Must specify element identifier or order")
            }
            return try await sendAction(.activate(target))
        case .increment:
            guard let target = elementTarget(args) else {
                return .error("Must specify element identifier or order")
            }
            return try await sendAction(.increment(target))
        case .decrement:
            guard let target = elementTarget(args) else {
                return .error("Must specify element identifier or order")
            }
            return try await sendAction(.decrement(target))
        case .performCustomAction:
            guard let target = elementTarget(args) else {
                return .error("Must specify element identifier or order")
            }
            guard let actionName = stringArg(args, "actionName") else {
                return .error("actionName is required")
            }
            return try await sendAction(.performCustomAction(CustomActionTarget(elementTarget: target, actionName: actionName)))
        default:
            return .error("Unknown accessibility action: \(command.rawValue)")
        }
    }

    // MARK: - Handler: Text Input

    func handleTypeText(_ args: [String: Any]) async throws -> FenceResponse {
        let text = stringArg(args, "text")
        let deleteCount = intArg(args, "deleteCount")
        guard text != nil || deleteCount != nil else {
            return .error("Must specify text, deleteCount, or both")
        }
        let result: ActionResult = try await sendAndAwait(.typeText(TypeTextTarget(
            text: text, deleteCount: deleteCount, elementTarget: elementTarget(args)
        ))) { requestId in
            try await client.waitForActionResult(requestId: requestId, timeout: Timeouts.longActionSeconds)
        }
        lastActionResult = result
        return .action(result: result)
    }

    func handleEditAction(_ args: [String: Any]) async throws -> FenceResponse {
        guard let actionString = stringArg(args, "action") else {
            return .error("action is required (\(EditAction.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        guard let action = EditAction(rawValue: actionString) else {
            return .error("Invalid action '\(actionString)'. Valid: \(EditAction.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return try await sendAction(.editAction(EditActionTarget(action: action)))
    }

    // MARK: - Handler: Recording

    func handleStartRecording(_ args: [String: Any]) async throws -> FenceResponse {
        guard client.connectionState == .connected else { throw FenceError.notConnected }
        let config = RecordingConfig(
            fps: intArg(args, "fps"),
            scale: doubleArg(args, "scale"),
            inactivityTimeout: doubleArg(args, "inactivity_timeout"),
            maxDuration: doubleArg(args, "max_duration")
        )
        client.send(.startRecording(config))
        return .ok(message: "Recording start requested — use stop_recording to retrieve the video")
    }

    func handleStopRecording(_ args: [String: Any]) async throws -> FenceResponse {
        let recording: RecordingPayload = try await sendAndAwait(.stopRecording) { _ in
            try await client.waitForRecording(timeout: Timeouts.longActionSeconds)
        }
        if let outputPath = stringArg(args, "output") {
            guard !outputPath.split(separator: "/").contains("..") else {
                return .error("Invalid output path: must not contain '..' components")
            }
            let resolvedURL = URL(fileURLWithPath: outputPath).standardized
            guard let videoData = Data(base64Encoded: recording.videoData) else {
                return .error("Failed to decode video data")
            }
            try videoData.write(to: resolvedURL)
            return .recording(path: resolvedURL.path, payload: recording)
        }
        return .recordingData(payload: recording)
    }
}
