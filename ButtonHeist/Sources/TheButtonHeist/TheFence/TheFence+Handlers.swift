import Foundation
import os.log

import TheScore

private let logger = Logger(subsystem: "com.buttonheist.fence", category: "handlers")
private let accessibilityAdjustmentCountRange = 1...100

@ButtonHeistActor
extension TheFence {

    // MARK: - Handler: Interface

    func handleGetInterface(_ args: [String: Any] = [:]) async throws -> FenceResponse {
        let scope = try getInterfaceScope(args)
        let detail = try args.schemaEnum("detail", as: InterfaceDetail.self) ?? .summary

        // Full scope (default): explore the screen, return all discovered elements.
        if scope == .full {
            let result = try await sendAndAwaitAction(.explore, timeout: Timeouts.exploreSeconds)
            lastActionHistory = .completed(result)
            guard case .explore(let exploreResult) = result.payload else {
                return .error("Explore failed: \(result.message ?? "unknown error")")
            }
            let interface = Interface(
                timestamp: Date(),
                tree: exploreResult.elements.map { .element($0) }
            )
            let filtered = try filteredInterface(interface, args: args)
            return .interface(
                filtered.interface,
                detail: detail,
                filteredFrom: filtered.filteredFrom,
                explore: exploreResult
            )
        }

        let interface = try await sendAndAwaitInterface(.requestInterface, timeout: Timeouts.actionSeconds)
        let filtered = try filteredInterface(interface, args: args)
        return .interface(filtered.interface, detail: detail, filteredFrom: filtered.filteredFrom)
    }

    private func filteredInterface(
        _ interface: Interface,
        args: [String: Any]
    ) throws -> (interface: Interface, filteredFrom: Int?) {
        // Matcher-based filtering takes precedence over heistId list
        let matcher = try elementMatcher(args)
        if matcher.hasPredicates {
            let total = interface.elements.count
            let filtered = interface.elements.filter { $0.matches(matcher) }
            let filteredInterface = Interface(
                timestamp: interface.timestamp,
                tree: filtered.map { .element($0) }
            )
            return (filteredInterface, total)
        }

        if let filterIds = try args.schemaStringArray("elements"), !filterIds.isEmpty {
            let filterSet = Set(filterIds)
            let filtered = interface.elements.filter { filterSet.contains($0.heistId) }
            let filteredInterface = Interface(
                timestamp: interface.timestamp,
                tree: filtered.map { .element($0) }
            )
            return (filteredInterface, interface.elements.count)
        }
        return (interface, nil)
    }

    private func getInterfaceScope(_ args: [String: Any]) throws -> GetInterfaceScope {
        if let scope = try args.schemaEnum("scope", as: GetInterfaceScope.self) {
            return scope
        }
        let legacyFull = try args.schemaBoolean("full") ?? true
        return legacyFull ? .full : .visible
    }

    // MARK: - Handler: Screen

    func handleGetScreen(_ args: [String: Any]) async throws -> FenceResponse {
        let screen = try await sendAndAwaitScreen(.requestScreen, timeout: 30)
        let artifactRequestId = (args["_requestId"] as? String) ?? UUID().uuidString
        let metadata = ScreenshotMetadata(width: screen.width, height: screen.height)
        do {
            if let url = try bookKeeper.writeScreenshotIfSinkAvailable(
                base64Data: screen.pngData,
                outputPath: try args.schemaString("output"),
                requestId: artifactRequestId,
                command: .getScreen,
                metadata: metadata
            ) {
                return .screenshot(path: url.path, width: screen.width, height: screen.height)
            }
        } catch BookKeeperError.unsafePath {
            return .error("Invalid output path: must not contain '..' components or control characters")
        } catch BookKeeperError.base64DecodingFailed {
            return .error("Failed to decode screenshot data")
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
        let target = try elementTarget(args)
        let x = try args.schemaNumber("x")
        let y = try args.schemaNumber("y")
        if let target {
            return try await sendAction(.touchTap(TouchTapTarget(elementTarget: target)))
        } else if let x, let y {
            return try await sendAction(.touchTap(TouchTapTarget(pointX: x, pointY: y)))
        }
        return .error("Must specify element (heistId or matcher) or coordinates (x, y)")
    }

    private func handleLongPress(_ args: [String: Any]) async throws -> FenceResponse {
        let target = try elementTarget(args)
        let x = try args.schemaNumber("x")
        let y = try args.schemaNumber("y")
        let duration = try args.schemaNumber("duration") ?? 0.5
        if let target {
            return try await sendAction(.touchLongPress(LongPressTarget(elementTarget: target, duration: duration)))
        } else if let x, let y {
            return try await sendAction(.touchLongPress(LongPressTarget(pointX: x, pointY: y, duration: duration)))
        }
        return .error("Must specify element (heistId or matcher) or coordinates (x, y)")
    }

    private func handleSwipe(_ args: [String: Any]) async throws -> FenceResponse {
        let direction = try args.schemaEnum("direction", as: SwipeDirection.self) { $0.lowercased() }

        let start = try args.schemaUnitPoint("start")
        let end = try args.schemaUnitPoint("end")

        if (start != nil) != (end != nil) {
            return .error("Unit-point swipe requires both start and end")
        }

        return try await sendAction(
            .touchSwipe(SwipeTarget(
                elementTarget: try elementTarget(args),
                startX: try args.schemaNumber("startX"), startY: try args.schemaNumber("startY"),
                endX: try args.schemaNumber("endX"), endY: try args.schemaNumber("endY"),
                direction: direction,
                duration: try args.schemaNumber("duration"),
                start: start, end: end
            ))
        )
    }

    private func handleDrag(_ args: [String: Any]) async throws -> FenceResponse {
        let endX = try args.requiredSchemaNumber("endX")
        let endY = try args.requiredSchemaNumber("endY")
        return try await sendAction(
            .touchDrag(DragTarget(
                elementTarget: try elementTarget(args),
                startX: try args.schemaNumber("startX") ?? args.schemaNumber("x"),
                startY: try args.schemaNumber("startY") ?? args.schemaNumber("y"),
                endX: endX, endY: endY, duration: try args.schemaNumber("duration")
            ))
        )
    }

    private func handlePinch(_ args: [String: Any]) async throws -> FenceResponse {
        let scale = try args.requiredSchemaNumber("scale")
        return try await sendAction(
            .touchPinch(PinchTarget(
                elementTarget: try elementTarget(args),
                centerX: try args.schemaNumber("centerX") ?? args.schemaNumber("x"),
                centerY: try args.schemaNumber("centerY") ?? args.schemaNumber("y"),
                scale: scale, spread: try args.schemaNumber("spread"),
                duration: try args.schemaNumber("duration")
            ))
        )
    }

    private func handleRotate(_ args: [String: Any]) async throws -> FenceResponse {
        let angle = try args.requiredSchemaNumber("angle")
        return try await sendAction(
            .touchRotate(RotateTarget(
                elementTarget: try elementTarget(args),
                centerX: try args.schemaNumber("centerX") ?? args.schemaNumber("x"),
                centerY: try args.schemaNumber("centerY") ?? args.schemaNumber("y"),
                angle: angle, radius: try args.schemaNumber("radius"),
                duration: try args.schemaNumber("duration")
            ))
        )
    }

    private func handleTwoFingerTap(_ args: [String: Any]) async throws -> FenceResponse {
        return try await sendAction(
            .touchTwoFingerTap(TwoFingerTapTarget(
                elementTarget: try elementTarget(args),
                centerX: try args.schemaNumber("centerX") ?? args.schemaNumber("x"),
                centerY: try args.schemaNumber("centerY") ?? args.schemaNumber("y"),
                spread: try args.schemaNumber("spread")
            ))
        )
    }

    private func handleDrawPath(_ args: [String: Any]) async throws -> FenceResponse {
        let pointsArray = try args.requiredSchemaDictionaryArray("points")
        let pathPoints = try pointsArray.enumerated().map { index, point -> PathPoint in
            let x = try schemaNumber(in: point, key: "x", field: "points[\(index)].x")
            let y = try schemaNumber(in: point, key: "y", field: "points[\(index)].y")
            return PathPoint(x: x, y: y)
        }
        guard pathPoints.count >= 2 else {
            return .error("Path requires at least 2 points")
        }
        return try await sendAction(
            .touchDrawPath(DrawPathTarget(
                points: pathPoints,
                duration: try args.schemaNumber("duration"),
                velocity: try args.schemaNumber("velocity")
            ))
        )
    }

    private func handleDrawBezier(_ args: [String: Any]) async throws -> FenceResponse {
        let startX = try args.requiredSchemaNumber("startX")
        let startY = try args.requiredSchemaNumber("startY")
        let segmentsArray = try args.requiredSchemaDictionaryArray("segments")
        let segments = try segmentsArray.enumerated().map { index, segment -> BezierSegment in
            let cp1X = try schemaNumber(in: segment, key: "cp1X", field: "segments[\(index)].cp1X")
            let cp1Y = try schemaNumber(in: segment, key: "cp1Y", field: "segments[\(index)].cp1Y")
            let cp2X = try schemaNumber(in: segment, key: "cp2X", field: "segments[\(index)].cp2X")
            let cp2Y = try schemaNumber(in: segment, key: "cp2Y", field: "segments[\(index)].cp2Y")
            let endX = try schemaNumber(in: segment, key: "endX", field: "segments[\(index)].endX")
            let endY = try schemaNumber(in: segment, key: "endY", field: "segments[\(index)].endY")
            return BezierSegment(cp1X: cp1X, cp1Y: cp1Y, cp2X: cp2X, cp2Y: cp2Y, endX: endX, endY: endY)
        }
        guard !segments.isEmpty else {
            return .error("At least 1 bezier segment is required")
        }
        return try await sendAction(
            .touchDrawBezier(DrawBezierTarget(
                startX: startX, startY: startY, segments: segments,
                samplesPerSegment: try args.schemaInteger("samplesPerSegment"),
                duration: try args.schemaNumber("duration"), velocity: try args.schemaNumber("velocity")
            ))
        )
    }

    private func schemaNumber(in dictionary: [String: Any], key: String, field: String) throws -> Double {
        do {
            guard let value = try dictionary.schemaNumber(key) else {
                throw SchemaValidationError(field: field, observed: nil, expected: "number")
            }
            return value
        } catch let error as SchemaValidationError {
            throw SchemaValidationError(field: field, observed: error.observed, expected: error.expected)
        }
    }

    // MARK: - Handler: Scroll Actions & Explore

    func handleScrollAction(command: Command, args: [String: Any]) async throws -> FenceResponse {
        switch command {
        case .scroll:
            let direction = try args.requiredSchemaEnum("direction", as: ScrollDirection.self) { $0.lowercased() }
            guard let target = try elementTarget(args) else {
                return .error("Must specify element (heistId or matcher) for scroll")
            }
            return try await sendAction(
                .scroll(ScrollTarget(elementTarget: target, direction: direction))
            )
        case .scrollToVisible:
            guard let target = try elementTarget(args) else {
                return .error("Must specify heistId or at least one match field for scroll_to_visible")
            }
            let scrollToVisibleTarget = ScrollToVisibleTarget(elementTarget: target)
            let result = try await sendAndAwaitAction(.scrollToVisible(scrollToVisibleTarget), timeout: Timeouts.actionSeconds)
            lastActionHistory = .completed(result)
            return .action(result: result)
        case .elementSearch:
            guard let target = try elementTarget(args) else {
                return .error("Must specify heistId or at least one match field (identifier, label, value, traits, or excludeTraits) for element_search")
            }
            let direction = try args.schemaEnum("direction", as: ScrollSearchDirection.self) { $0.lowercased() }
            let searchTarget = ElementSearchTarget(
                elementTarget: target,
                direction: direction
            )
            let result = try await sendAndAwaitAction(.elementSearch(searchTarget), timeout: Timeouts.longActionSeconds)
            lastActionHistory = .completed(result)
            return .action(result: result)
        case .scrollToEdge:
            let edge = try args.requiredSchemaEnum("edge", as: ScrollEdge.self) { $0.lowercased() }
            guard let target = try elementTarget(args) else {
                return .error("Must specify element (heistId or matcher) for scroll_to_edge")
            }
            return try await sendAction(.scrollToEdge(ScrollToEdgeTarget(elementTarget: target, edge: edge)))
        default:
            return .error("Unknown scroll action: \(command.rawValue)")
        }
    }

    // MARK: - Handler: Accessibility Actions

    func handleAccessibilityAction(command: Command, args: [String: Any]) async throws -> FenceResponse {
        if command == .rotor {
            return try await handleRotor(args)
        }

        guard let target = try elementTarget(args) else {
            return .error("Must specify element (heistId or matcher)")
        }

        // Resolve the action name: activate uses "action" param, standalone commands use the command itself
        let actionName: String? = switch command {
        case .activate: try args.schemaString("action")
        case .increment: "increment"
        case .decrement: "decrement"
        case .performCustomAction: try args.schemaString("action")
        default: nil
        }

        guard command != .performCustomAction || actionName != nil else {
            throw SchemaValidationError(field: "action", observed: nil, expected: "string")
        }

        // No action → default activation
        guard let actionName else {
            if args.keys.contains("count") {
                throw SchemaValidationError(field: "count", observed: args["count"], expected: "only valid with increment or decrement")
            }
            return try await sendAction(.activate(target))
        }

        // "action:foo" prefix forces custom action dispatch (escapes built-in names)
        if actionName.hasPrefix("action:") {
            if args.keys.contains("count") {
                throw SchemaValidationError(field: "count", observed: args["count"], expected: "only valid with increment or decrement")
            }
            let customName = String(actionName.dropFirst("action:".count))
            guard !customName.isEmpty else {
                return .error("action: prefix requires a name (e.g. \"action:myAction\")")
            }
            return try await sendAction(.performCustomAction(
                CustomActionTarget(elementTarget: target, actionName: customName)))
        }

        // Built-in actions map to their wire messages; everything else is a custom action
        switch actionName {
        case "increment":
            let count = try accessibilityAdjustmentCount(args)
            return try await sendRepeatedAdjustment(.increment(target), actionName: actionName, count: count)
        case "decrement":
            let count = try accessibilityAdjustmentCount(args)
            return try await sendRepeatedAdjustment(.decrement(target), actionName: actionName, count: count)
        default:
            if args.keys.contains("count") {
                throw SchemaValidationError(field: "count", observed: args["count"], expected: "only valid with increment or decrement")
            }
            return try await sendAction(.performCustomAction(
                CustomActionTarget(elementTarget: target, actionName: actionName)))
        }
    }

    private func accessibilityAdjustmentCount(_ args: [String: Any]) throws -> Int {
        let count = try args.schemaInteger("count") ?? 1
        guard accessibilityAdjustmentCountRange.contains(count) else {
            throw SchemaValidationError(
                field: "count",
                observed: count,
                expected: "integer in \(accessibilityAdjustmentCountRange.lowerBound)...\(accessibilityAdjustmentCountRange.upperBound)"
            )
        }
        return count
    }

    private func sendRepeatedAdjustment(
        _ message: ClientMessage,
        actionName: String,
        count: Int
    ) async throws -> FenceResponse {
        var finalResult: ActionResult?
        for repetition in 1...count {
            let result = try await sendAndAwaitAction(message, timeout: Timeouts.actionSeconds)
            lastActionHistory = .completed(result)
            finalResult = result
            if !result.success && repetition < count {
                let detail = result.message.map { ": \($0)" } ?? ""
                return .error("\(actionName) repetition \(repetition) of \(count) failed\(detail)")
            }
        }
        guard let finalResult else {
            return .error("\(actionName) count produced no action result")
        }
        return .action(result: finalResult)
    }

    private func handleRotor(_ args: [String: Any]) async throws -> FenceResponse {
        guard let target = try elementTarget(args) else {
            return .error("Must specify element (heistId or matcher) for rotor")
        }
        let direction = try args.schemaEnum("direction", as: RotorDirection.self) { $0.lowercased() } ?? .next
        if let rotorIndex = try args.schemaInteger("rotorIndex"), rotorIndex < 0 {
            throw SchemaValidationError(field: "rotorIndex", observed: rotorIndex, expected: "integer >= 0")
        }
        let currentTextStartOffset = try args.schemaInteger("currentTextStartOffset")
        let currentTextEndOffset = try args.schemaInteger("currentTextEndOffset")
        if (currentTextStartOffset == nil) != (currentTextEndOffset == nil) {
            return .error("currentTextStartOffset and currentTextEndOffset must be provided together")
        }
        let currentTextRange: TextRangeReference?
        if let startOffset = currentTextStartOffset, let endOffset = currentTextEndOffset {
            guard try args.schemaString("currentHeistId") != nil else {
                throw SchemaValidationError(field: "currentHeistId", observed: nil, expected: "string")
            }
            guard startOffset >= 0, endOffset >= startOffset else {
                throw SchemaValidationError(
                    field: "currentTextStartOffset/currentTextEndOffset",
                    observed: "\(startOffset)..<\(endOffset)",
                    expected: "integer range with start >= 0 and end >= start"
                )
            }
            currentTextRange = TextRangeReference(startOffset: startOffset, endOffset: endOffset)
        } else {
            currentTextRange = nil
        }

        let rotorTarget = RotorTarget(
            elementTarget: target,
            rotor: try args.schemaString("rotor"),
            rotorIndex: try args.schemaInteger("rotorIndex"),
            direction: direction,
            currentHeistId: try args.schemaString("currentHeistId"),
            currentTextRange: currentTextRange
        )
        return try await sendAction(.rotor(rotorTarget))
    }

    // MARK: - Handler: Text Input

    func handleTypeText(_ args: [String: Any]) async throws -> FenceResponse {
        let text = try args.schemaString("text")
        let deleteCount = try args.schemaInteger("deleteCount")
        let clearFirst = try args.schemaBoolean("clearFirst")
        guard text != nil || deleteCount != nil || clearFirst == true else {
            return .error("Must specify text, deleteCount, clearFirst, or a combination")
        }
        let result = try await sendAndAwaitAction(.typeText(TypeTextTarget(
            text: text, deleteCount: deleteCount, clearFirst: clearFirst, elementTarget: try elementTarget(args)
        )), timeout: Timeouts.longActionSeconds)
        lastActionHistory = .completed(result)
        return .action(result: result)
    }

    func handleEditAction(_ args: [String: Any]) async throws -> FenceResponse {
        let action = try args.requiredSchemaEnum("action", as: EditAction.self)
        return try await sendAction(.editAction(EditActionTarget(action: action)))
    }

    // MARK: - Handler: Pasteboard

    func handleSetPasteboard(_ args: [String: Any]) async throws -> FenceResponse {
        let text = try args.requiredSchemaString("text")
        return try await sendAction(.setPasteboard(SetPasteboardTarget(text: text)))
    }

    func handleGetPasteboard() async throws -> FenceResponse {
        return try await sendAction(.getPasteboard)
    }

    // MARK: - Handler: Wait For

    func handleWaitFor(_ args: [String: Any]) async throws -> FenceResponse {
        guard let target = try elementTarget(args) else {
            return .error("Must specify heistId or at least one match field (label, identifier, value, traits, or excludeTraits) for wait_for")
        }
        let waitForTarget = WaitForTarget(
            elementTarget: target,
            absent: try args.schemaBoolean("absent"),
            timeout: try args.schemaNumber("timeout")
        )
        let result = try await sendAndAwaitAction(.waitFor(waitForTarget), timeout: waitForTarget.resolvedTimeout + 5)
        lastActionHistory = .completed(result)
        return .action(result: result)
    }

    // MARK: - Handler: Wait For Change

    func handleWaitForChange(_ args: [String: Any]) async throws -> FenceResponse {
        let expectation = try parseExpectation(args)
        let timeout = try args.schemaNumber("timeout")
        let target = WaitForChangeTarget(expect: expectation, timeout: timeout)
        let result = try await sendAndAwaitAction(.waitForChange(target), timeout: target.resolvedTimeout + 5)
        lastActionHistory = .completed(result)
        return .action(result: result)
    }

    // MARK: - Handler: Recording

    func handleStartRecording(_ args: [String: Any]) async throws -> FenceResponse {
        guard handoff.isConnected else { throw FenceError.notConnected }
        guard !handoff.isRecording else {
            return .error("Recording already in progress — use stop_recording first")
        }
        let fps = try args.schemaInteger("fps")
        if let fps, fps < 1 || fps > 15 {
            throw SchemaValidationError(field: "fps", observed: fps, expected: "integer in 1...15")
        }
        let scale = try args.schemaNumber("scale")
        if let scale, scale < 0.25 || scale > 1.0 {
            throw SchemaValidationError(field: "scale", observed: scale, expected: "number in 0.25...1.0")
        }
        let config = RecordingConfig(
            fps: fps,
            scale: scale,
            inactivityTimeout: try args.schemaNumber("inactivity_timeout"),
            maxDuration: try args.schemaNumber("max_duration")
        )
        try await startRecordingAndWait(config: config, timeout: Timeouts.actionSeconds)
        return .ok(message: "Recording started — use stop_recording to retrieve the video")
    }

    // MARK: - Handler: List Devices

    func handleListDevices() async throws -> FenceResponse {
        var devices = await handoff.discoverReachableDevices()
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
        let targetName = try args.schemaString("target")
        let device = try args.schemaString("device")
        let token = try args.schemaString("token")

        let resolvedDevice: String
        let resolvedToken: String?
        let resolvedDirectDevice: DiscoveredDevice?

        if let device {
            resolvedDevice = device
            resolvedToken = token
            resolvedDirectDevice = nil
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
            resolvedDirectDevice = DiscoveredDevice.fromHostPort(
                target.device,
                id: "config-\(targetName)",
                name: targetName,
                certFingerprint: target.certFingerprint
            )
        } else {
            return .error("Must specify 'target' (named config target) or 'device' (host:port)")
        }

        let previousConfig = config
        let previousToken = handoff.token

        stop()

        handoff.token = resolvedToken
        let newConfig = Configuration(
            deviceFilter: resolvedDevice,
            connectionTimeout: config.connectionTimeout,
            token: resolvedToken,
            autoReconnect: config.autoReconnect,
            fileConfig: config.fileConfig,
            directDevice: resolvedDirectDevice
        )
        config = newConfig

        do {
            try await start()
        } catch {
            config = previousConfig
            handoff.token = previousToken
            let connectionFailure = error as? FenceError
            let connectionFailureDetails = connectionFailure?.failureDetails
            let connectionFailureMessage = connectionFailure?.coreMessage ?? error.displayMessage
            do {
                try await start()
            } catch {
                let restoreFailure = error as? FenceError
                // Prefer restore details when available; otherwise keep the original connection failure typed.
                let restoreFailureDetails = restoreFailure?.failureDetails ?? connectionFailureDetails
                let restoreFailureMessage = restoreFailure?.coreMessage ?? error.displayMessage
                let message = "Connect failed (\(connectionFailureMessage)) " +
                    "and could not restore previous connection: \(restoreFailureMessage)"
                return .error(
                    message,
                    details: restoreFailureDetails
                )
            }
            return .error(
                "Connect failed, restored previous connection: \(connectionFailureMessage)",
                details: connectionFailureDetails
            )
        }

        return try await handleGetInterface()
    }

    func handleListTargets() -> FenceResponse {
        guard let fileConfig = config.fileConfig else {
            return .targets([:], defaultTarget: nil)
        }
        return .targets(fileConfig.targets, defaultTarget: fileConfig.defaultTarget)
    }

    func handleStopRecording(_ args: [String: Any]) async throws -> FenceResponse {
        guard handoff.isRecording else {
            return .error("No recording in progress — use start_recording first")
        }
        let recording: RecordingPayload = try await stopRecordingAndWait(timeout: Timeouts.longActionSeconds)
        let artifactRequestId = (args["_requestId"] as? String) ?? UUID().uuidString
        let metadata = RecordingMetadata(
            width: recording.width,
            height: recording.height,
            duration: recording.duration,
            fps: recording.fps,
            frameCount: recording.frameCount
        )
        do {
            if let url = try bookKeeper.writeRecordingIfSinkAvailable(
                base64Data: recording.videoData,
                outputPath: try args.schemaString("output"),
                requestId: artifactRequestId,
                command: .stopRecording,
                metadata: metadata
            ) {
                return .recording(path: url.path, payload: recording)
            }
        } catch BookKeeperError.unsafePath {
            return .error("Invalid output path: must not contain '..' components or control characters")
        } catch BookKeeperError.base64DecodingFailed {
            return .error("Failed to decode video data")
        }
        return .recordingData(payload: recording)
    }

    // MARK: - Handler: BookKeeper

    func handleBookKeeperCommand(command: Command, args: [String: Any]) async throws -> FenceResponse {
        switch command {
        case .getSessionLog:
            guard let manifest = bookKeeper.manifest else {
                return .error("No active session")
            }
            return .sessionLog(manifest: manifest)
        case .archiveSession:
            let deleteSource = try args.schemaBoolean("delete_source") ?? false
            // Drive whatever phase we observe toward .closed before archiving.
            switch bookKeeper.phase {
            case .idle:
                // No session to close. archiveSession will surface the
                // phase mismatch with a clean error message rather than
                // silently fall through as if .active.
                break
            case .active:
                try await bookKeeper.closeSession()
            case .closing:
                // A prior close is mid-flight (or its compression failed
                // and left us stuck). Don't attempt closeSession again —
                // it would throw a phase mismatch. Fall through and let
                // archiveSession surface the diagnostic.
                break
            case .closed, .archived:
                break
            }
            let (archiveURL, manifest) = try await bookKeeper.archiveSession(deleteSource: deleteSource)
            return .archiveResult(path: archiveURL.path, manifest: manifest)
        case .startHeist:
            let app = try args.schemaString("app") ?? "com.buttonheist.testapp"
            if bookKeeper.manifest == nil {
                let identifier = try args.schemaString("identifier") ?? "heist"
                try bookKeeper.beginSession(identifier: identifier)
            }
            try bookKeeper.startHeistRecording(app: app)
            return .heistStarted
        case .stopHeist:
            let outputPath = try args.requiredSchemaString("output")
            guard let resolvedURL = bookKeeper.validateOutputPath(outputPath) else {
                throw FenceError.invalidRequest("Invalid output path: must not be empty, contain '..' components, or contain control characters")
            }
            let heist = try bookKeeper.stopHeistRecording()
            try TheBookKeeper.writeHeist(heist, to: resolvedURL)
            return .heistStopped(path: resolvedURL.path, stepCount: heist.steps.count)
        case .playHeist:
            return try await handlePlayHeist(args)
        default:
            return .error("Unexpected BookKeeper command: \(command.rawValue)")
        }
    }

    private func handlePlayHeist(_ args: [String: Any]) async throws -> FenceResponse {
        guard case .idle = playbackPhase else {
            throw FenceError.invalidRequest("Cannot nest play_heist inside an active playback")
        }
        let inputPath = try args.requiredSchemaString("input")
        guard let resolvedURL = bookKeeper.validateOutputPath(inputPath) else {
            throw FenceError.invalidRequest("Invalid input path: must not be empty or contain '..' components")
        }

        let heist = try TheBookKeeper.readHeist(from: resolvedURL)

        guard heist.version == HeistPlayback.currentVersion else {
            throw FenceError.invalidRequest(
                "Unsupported heist file version \(heist.version). " +
                    "This Button Heist build supports version \(HeistPlayback.currentVersion). " +
                    "Re-record the heist with the current format."
            )
        }

        // Warn if the connected app doesn't match the app the heist was recorded against
        if let connectedBundle = handoff.serverInfo?.bundleIdentifier,
           connectedBundle != heist.app {
            logger.warning(
                "Heist was recorded against \(heist.app) but connected app is \(connectedBundle)"
            )
        }

        let heistName = resolvedURL.deletingPathExtension().lastPathComponent
        let playbackStart = CFAbsoluteTimeGetCurrent()
        var completedSteps = 0
        var failedIndex: Int?
        var failure: PlaybackFailure?
        var stepResults: [HeistPlaybackReport.StepResult] = []

        playbackPhase = .playing(startedAt: Date())
        defer { playbackPhase = .idle }

        // Prime the registry before playback — get_interface defaults to full exploration
        _ = try await execute(request: ["command": "get_interface"])

        for (index, step) in heist.steps.enumerated() {
            let stepStart = CFAbsoluteTimeGetCurrent()
            let request = step.toRequestDictionary()
            var stepFailure: PlaybackFailure?

            do {
                let response = try await execute(request: request)

                // On elementNotFound with a matcher target, try scroll_to_visible then retry.
                // The element may be off-screen — during recording it was found via full explore,
                // but playback only sees the viewport.
                if let actionResult = response.actionResult,
                   !actionResult.success,
                   actionResult.errorKind == .elementNotFound,
                   let target = step.target, target.hasPredicates {
                    let scrollRequest = step.scrollToVisibleRequest()
                    let scrollResponse = try await execute(request: scrollRequest)
                    if let scrollResult = scrollResponse.actionResult, scrollResult.success {
                        let retryResponse = try await execute(request: request)
                        stepFailure = playbackFailure(step: step, response: retryResponse)
                    } else {
                        // Report the original action failure, not the scroll failure —
                        // the root cause is the element not being found, not the scroll attempt.
                        stepFailure = playbackFailure(step: step, response: response)
                    }
                } else {
                    stepFailure = playbackFailure(step: step, response: response)
                }
            } catch {
                let failedStep = PlaybackFailure.FailedStep(command: step.command, target: step.target)
                stepFailure = .thrown(step: failedStep, error: error.localizedDescription, interface: nil)
            }

            let stepTime = CFAbsoluteTimeGetCurrent() - stepStart
            stepResults.append(stepResult(index: index, step: step, timeSeconds: stepTime, failure: stepFailure))

            if let stepFailure {
                failedIndex = index
                failure = stepFailure
                break
            }
            completedSteps += 1
        }

        // Capture the live interface at time of failure for diagnostics
        if let currentFailure = failure {
            let interface = await captureInterfaceSnapshot()
            failure = currentFailure.withInterface(interface)
        }

        let totalTimeSeconds = CFAbsoluteTimeGetCurrent() - playbackStart
        let totalTimingMs = Int(totalTimeSeconds * 1000)
        let report = HeistPlaybackReport(
            heistName: heistName,
            app: heist.app,
            totalStepCount: heist.steps.count,
            totalTimeSeconds: totalTimeSeconds,
            steps: stepResults
        )
        return .heistPlayback(
            completedSteps: completedSteps,
            failedIndex: failedIndex,
            totalTimingMs: totalTimingMs,
            failure: failure,
            report: report
        )
    }

    /// Build a StepResult from a step and its optional failure.
    private func stepResult(
        index: Int, step: HeistEvidence, timeSeconds: Double, failure: PlaybackFailure?
    ) -> HeistPlaybackReport.StepResult {
        let outcome: HeistPlaybackReport.Outcome
        if let failure {
            outcome = .failed(message: failure.errorMessage, errorKind: failure.step.command == step.command ? failureErrorKind(failure) : nil)
        } else {
            outcome = .passed
        }
        return HeistPlaybackReport.StepResult(
            index: index,
            command: step.command,
            target: step.target,
            timeSeconds: timeSeconds,
            outcome: outcome
        )
    }

    /// Extract the typed error kind from a PlaybackFailure.
    private func failureErrorKind(_ failure: PlaybackFailure) -> HeistPlaybackReport.PlaybackErrorKind? {
        switch failure {
        case .fenceError: return .commandError
        case .actionFailed(_, let result, _, _):
            guard let errorKind = result.errorKind else { return nil }
            return .action(errorKind)
        case .thrown: return .thrown
        }
    }

    /// Extract a PlaybackFailure from a response, or nil if the step succeeded.
    private func playbackFailure(step: HeistEvidence, response: FenceResponse) -> PlaybackFailure? {
        let failedStep = PlaybackFailure.FailedStep(command: step.command, target: step.target)
        switch response {
        case .error(let message, _):
            return .fenceError(step: failedStep, message: message, interface: nil)
        case .action(let result, let expectation) where !result.success || expectation?.met == false:
            return .actionFailed(step: failedStep, result: result, expectation: expectation, interface: nil)
        default:
            return nil
        }
    }

    /// Capture a live interface snapshot for failure diagnostics.
    private func captureInterfaceSnapshot() async -> Interface? {
        do {
            let response = try await execute(request: ["command": "get_interface"])
            if case .interface(let snapshot, _, _, _) = response {
                return snapshot
            }
        } catch {
            logger.error("Failed to capture interface for playback diagnostics: \(error.localizedDescription)")
        }
        return nil
    }

}
