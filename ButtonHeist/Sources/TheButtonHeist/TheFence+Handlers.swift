import Foundation
import TheScore

@ButtonHeistActor
extension TheFence {

    // MARK: - Handler: Interface

    func handleGetInterface(_ args: [String: Any] = [:]) async throws -> FenceResponse {
        let interface: Interface = try await sendAndAwait(.requestInterface) { requestId in
            try await client.waitForInterface(requestId: requestId, timeout: Timeouts.actionSeconds)
        }
        let detail = (args["detail"] as? String).flatMap(InterfaceDetail.init) ?? .summary

        if let filterIds = args["elements"] as? [String], !filterIds.isEmpty {
            let filterSet = Set(filterIds)
            let filtered = interface.elements.filter { filterSet.contains($0.heistId) }
            let filteredInterface = Interface(
                timestamp: interface.timestamp,
                elements: filtered,
                tree: nil
            )
            return .interface(filteredInterface, detail: detail, filteredFrom: interface.elements.count)
        }
        return .interface(interface, detail: detail)
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
            let matcher = elementMatcher(args)
            guard matcher.label != nil || matcher.identifier != nil || matcher.heistId != nil || matcher.value != nil else {
                return .error("Must specify at least one match field (heistId, identifier, label, or value) for scroll_to_visible")
            }
            let directionStr = stringArg(args, "direction")
            var direction: ScrollSearchDirection?
            if let directionStr {
                direction = ScrollSearchDirection(rawValue: directionStr.lowercased())
                if direction == nil {
                    return .error("Invalid direction '\(directionStr)'. Valid: \(ScrollSearchDirection.allCases.map(\.rawValue).joined(separator: ", "))")
                }
            }
            let target = ScrollToVisibleTarget(
                match: matcher,
                maxScrolls: intArg(args, "maxScrolls"),
                direction: direction
            )
            let result: ActionResult = try await sendAndAwait(.scrollToVisible(target)) { requestId in
                try await client.waitForActionResult(requestId: requestId, timeout: Timeouts.longActionSeconds)
            }
            lastActionResult = result
            return .action(result: result)
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
        let clearFirst = boolArg(args, "clearFirst")
        guard text != nil || deleteCount != nil || clearFirst == true else {
            return .error("Must specify text, deleteCount, clearFirst, or a combination")
        }
        let result: ActionResult = try await sendAndAwait(.typeText(TypeTextTarget(
            text: text, deleteCount: deleteCount, clearFirst: clearFirst, elementTarget: elementTarget(args)
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

    // MARK: - Handler: Pasteboard

    func handleSetPasteboard(_ args: [String: Any]) async throws -> FenceResponse {
        guard let text = stringArg(args, "text") else {
            return .error("text is required for set_pasteboard")
        }
        return try await sendAction(.setPasteboard(SetPasteboardTarget(text: text)))
    }

    func handleGetPasteboard() async throws -> FenceResponse {
        return try await sendAction(.getPasteboard)
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

    // MARK: - Handler: List Devices

    func handleListDevices() async throws -> FenceResponse {
        var devices = await client.discoverReachableDevices()
        if let fileConfig = config.fileConfig {
            let configDevices = Self.configTargetsAsDevices(fileConfig)
            let existingIDs = Set(devices.map(\.id))
            for device in configDevices where !existingIDs.contains(device.id) {
                devices.append(device)
            }
        }
        return .devices(devices)
    }

    // MARK: - Handler: Connect (runtime target switching)

    func handleConnect(_ args: [String: Any]) async throws -> FenceResponse {
        let targetName = stringArg(args, "target")
        let device = stringArg(args, "device")
        let token = stringArg(args, "token")

        let resolvedDevice: String
        let resolvedToken: String?

        if let device {
            resolvedDevice = device
            resolvedToken = token
        } else if let targetName {
            guard let fileConfig = config.fileConfig else {
                return .error("No config file loaded. Create .buttonheist.json or ~/.config/buttonheist/config.json")
            }
            guard let target = fileConfig.targets[targetName] else {
                let available = fileConfig.targets.keys.sorted()
                return .error("Unknown target '\(targetName)'. Available: \(available.joined(separator: ", "))")
            }
            resolvedDevice = target.device
            resolvedToken = token ?? target.token
        } else {
            return .error("Must specify 'target' (named config target) or 'device' (host:port)")
        }

        let previousConfig = config
        let previousToken = client.token

        stop()

        client.token = resolvedToken
        let newConfig = Configuration(
            deviceFilter: resolvedDevice,
            connectionTimeout: config.connectionTimeout,
            token: resolvedToken,
            autoReconnect: config.autoReconnect,
            fileConfig: config.fileConfig
        )
        config = newConfig

        do {
            try await start()
        } catch {
            config = previousConfig
            client.token = previousToken
            do {
                try await start()
            } catch {
                return .error("Connect failed and could not restore previous connection: \(error.localizedDescription)")
            }
            return .error("Connect failed, restored previous connection: \(error.localizedDescription)")
        }

        let deviceName = client.connectedDevice.map { client.displayName(for: $0) } ?? resolvedDevice
        return .ok(message: "Connected to \(deviceName)")
    }

    func handleListTargets() -> FenceResponse {
        guard let fileConfig = config.fileConfig else {
            return .targets([:], defaultTarget: nil)
        }
        return .targets(fileConfig.targets, defaultTarget: fileConfig.defaultTarget)
    }

    // MARK: - Handler: Recording

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
