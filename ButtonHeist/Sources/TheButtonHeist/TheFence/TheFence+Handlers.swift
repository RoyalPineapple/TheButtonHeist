import Foundation
import os.log

import TheScore

private let logger = Logger(subsystem: "com.buttonheist.fence", category: "handlers")

@ButtonHeistActor
extension TheFence {

    // MARK: - Handler: Interface

    func handleGetInterface(_ args: [String: Any] = [:]) async throws -> FenceResponse {
        let full = args.boolean("full") ?? true

        // Full mode (default): explore the screen, return all discovered elements
        if full {
            let result = try await sendAndAwaitAction(.explore, timeout: Timeouts.exploreSeconds)
            lastActionResult = result
            guard let exploreResult = result.exploreResult else {
                return .error("Explore failed: \(result.message ?? "unknown error")")
            }
            let detail = (args["detail"] as? String).flatMap(InterfaceDetail.init) ?? .summary
            let interface = Interface(
                timestamp: Date(),
                tree: exploreResult.elements.map { .element($0) }
            )
            return .interface(interface, detail: detail, explore: exploreResult)
        }

        let interface = try await sendAndAwaitInterface(.requestInterface, timeout: Timeouts.actionSeconds)
        let detail = (args["detail"] as? String).flatMap(InterfaceDetail.init) ?? .summary

        // Matcher-based filtering takes precedence over heistId list
        let matcher = try elementMatcher(args)
        if matcher.hasPredicates {
            let total = interface.elements.count
            let filtered = interface.elements.filter { $0.matches(matcher) }
            let filteredInterface = Interface(
                timestamp: interface.timestamp,
                tree: filtered.map { .element($0) }
            )
            return .interface(filteredInterface, detail: detail, filteredFrom: total)
        }

        if let filterIds = args["elements"] as? [String], !filterIds.isEmpty {
            let filterSet = Set(filterIds)
            let filtered = interface.elements.filter { filterSet.contains($0.heistId) }
            let filteredInterface = Interface(
                timestamp: interface.timestamp,
                tree: filtered.map { .element($0) }
            )
            return .interface(filteredInterface, detail: detail, filteredFrom: interface.elements.count)
        }
        return .interface(interface, detail: detail)
    }

    // MARK: - Handler: Screen

    func handleGetScreen(_ args: [String: Any]) async throws -> FenceResponse {
        let screen = try await sendAndAwaitScreen(.requestScreen, timeout: 30)
        let artifactRequestId = (args["_requestId"] as? String) ?? UUID().uuidString
        let metadata = ScreenshotMetadata(width: screen.width, height: screen.height)
        do {
            if let url = try bookKeeper.writeArtifactIfSinkAvailable(
                base64Data: screen.pngData,
                outputPath: args.string("output"),
                requestId: artifactRequestId,
                command: .getScreen,
                metadata: .screenshot(metadata)
            ) {
                return .screenshot(path: url.path, width: screen.width, height: screen.height)
            }
        } catch BookKeeperError.unsafePath {
            return .error("Invalid output path: must not contain '..' components")
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
        let x = args.number("x")
        let y = args.number("y")
        if let target {
            return try await sendAction(.touchTap(TouchTapTarget(elementTarget: target)))
        } else if let x, let y {
            return try await sendAction(.touchTap(TouchTapTarget(pointX: x, pointY: y)))
        }
        return .error("Must specify element (heistId or matcher) or coordinates (x, y)")
    }

    private func handleLongPress(_ args: [String: Any]) async throws -> FenceResponse {
        let target = try elementTarget(args)
        let x = args.number("x")
        let y = args.number("y")
        let duration = args.number("duration") ?? 0.5
        if let target {
            return try await sendAction(.touchLongPress(LongPressTarget(elementTarget: target, duration: duration)))
        } else if let x, let y {
            return try await sendAction(.touchLongPress(LongPressTarget(pointX: x, pointY: y, duration: duration)))
        }
        return .error("Must specify element (heistId or matcher) or coordinates (x, y)")
    }

    private func handleSwipe(_ args: [String: Any]) async throws -> FenceResponse {
        let directionValue = args.string("direction")
        var direction: SwipeDirection?
        if let directionValue {
            direction = SwipeDirection(rawValue: directionValue.lowercased())
            if direction == nil {
                return .error("Invalid direction '\(directionValue)'. Valid: \(SwipeDirection.allCases.map(\.rawValue).joined(separator: ", "))")
            }
        }

        let start = args.unitPoint("start")
        let end = args.unitPoint("end")

        if (start != nil) != (end != nil) {
            return .error("Unit-point swipe requires both start and end")
        }

        return try await sendAction(
            .touchSwipe(SwipeTarget(
                elementTarget: try elementTarget(args),
                startX: args.number("startX"), startY: args.number("startY"),
                endX: args.number("endX"), endY: args.number("endY"),
                direction: direction,
                duration: args.number("duration"),
                start: start, end: end
            ))
        )
    }

    private func handleDrag(_ args: [String: Any]) async throws -> FenceResponse {
        guard let endX = args.number("endX"), let endY = args.number("endY") else {
            return .error("endX and endY are required for drag")
        }
        return try await sendAction(
            .touchDrag(DragTarget(
                elementTarget: try elementTarget(args),
                startX: args.number("startX") ?? args.number("x"),
                startY: args.number("startY") ?? args.number("y"),
                endX: endX, endY: endY, duration: args.number("duration")
            ))
        )
    }

    private func handlePinch(_ args: [String: Any]) async throws -> FenceResponse {
        guard let scale = args.number("scale") else {
            return .error("scale is required for pinch")
        }
        return try await sendAction(
            .touchPinch(PinchTarget(
                elementTarget: try elementTarget(args),
                centerX: args.number("centerX") ?? args.number("x"),
                centerY: args.number("centerY") ?? args.number("y"),
                scale: scale, spread: args.number("spread"),
                duration: args.number("duration")
            ))
        )
    }

    private func handleRotate(_ args: [String: Any]) async throws -> FenceResponse {
        guard let angle = args.number("angle") else {
            return .error("angle is required for rotate")
        }
        return try await sendAction(
            .touchRotate(RotateTarget(
                elementTarget: try elementTarget(args),
                centerX: args.number("centerX") ?? args.number("x"),
                centerY: args.number("centerY") ?? args.number("y"),
                angle: angle, radius: args.number("radius"),
                duration: args.number("duration")
            ))
        )
    }

    private func handleTwoFingerTap(_ args: [String: Any]) async throws -> FenceResponse {
        return try await sendAction(
            .touchTwoFingerTap(TwoFingerTapTarget(
                elementTarget: try elementTarget(args),
                centerX: args.number("centerX") ?? args.number("x"),
                centerY: args.number("centerY") ?? args.number("y"),
                spread: args.number("spread")
            ))
        )
    }

    private func handleDrawPath(_ args: [String: Any]) async throws -> FenceResponse {
        guard let pointsArray = args["points"] as? [[String: Any]] else {
            return .error("points must be an array of {x, y} objects")
        }
        let pathPoints = pointsArray.compactMap { point -> PathPoint? in
            guard let x = point.number("x"), let y = point.number("y") else { return nil }
            return PathPoint(x: x, y: y)
        }
        guard pathPoints.count == pointsArray.count else {
            return .error("Each point must have numeric x and y fields")
        }
        guard pathPoints.count >= 2 else {
            return .error("Path requires at least 2 points")
        }
        return try await sendAction(
            .touchDrawPath(DrawPathTarget(
                points: pathPoints,
                duration: args.number("duration"),
                velocity: args.number("velocity")
            ))
        )
    }

    private func handleDrawBezier(_ args: [String: Any]) async throws -> FenceResponse {
        guard let startX = args.number("startX"), let startY = args.number("startY") else {
            return .error("startX and startY are required")
        }
        guard let segmentsArray = args["segments"] as? [[String: Any]] else {
            return .error("segments array is required")
        }
        let segments = segmentsArray.compactMap { segment -> BezierSegment? in
            guard
                let cp1X = segment.number("cp1X"), let cp1Y = segment.number("cp1Y"),
                let cp2X = segment.number("cp2X"), let cp2Y = segment.number("cp2Y"),
                let endX = segment.number("endX"), let endY = segment.number("endY")
            else { return nil }
            return BezierSegment(cp1X: cp1X, cp1Y: cp1Y, cp2X: cp2X, cp2Y: cp2Y, endX: endX, endY: endY)
        }
        guard segments.count == segmentsArray.count else {
            return .error("Each segment needs cp1X, cp1Y, cp2X, cp2Y, endX, endY")
        }
        guard !segments.isEmpty else {
            return .error("At least 1 bezier segment is required")
        }
        return try await sendAction(
            .touchDrawBezier(DrawBezierTarget(
                startX: startX, startY: startY, segments: segments,
                samplesPerSegment: args.integer("samplesPerSegment"),
                duration: args.number("duration"), velocity: args.number("velocity")
            ))
        )
    }

    // MARK: - Handler: Scroll Actions & Explore

    func handleScrollAction(command: Command, args: [String: Any]) async throws -> FenceResponse {
        switch command {
        case .scroll:
            guard let directionValue = args.string("direction") else {
                return .error("direction is required for scroll. Valid: \(ScrollDirection.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            guard let direction = ScrollDirection(rawValue: directionValue.lowercased()) else {
                return .error("Invalid direction '\(directionValue)'. Valid: \(ScrollDirection.allCases.map(\.rawValue).joined(separator: ", "))")
            }
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
            lastActionResult = result
            return .action(result: result)
        case .elementSearch:
            guard let target = try elementTarget(args) else {
                return .error("Must specify heistId or at least one match field (identifier, label, value, traits, or excludeTraits) for element_search")
            }
            let directionStr = args.string("direction")
            var direction: ScrollSearchDirection?
            if let directionStr {
                direction = ScrollSearchDirection(rawValue: directionStr.lowercased())
                if direction == nil {
                    return .error("Invalid direction '\(directionStr)'. Valid: \(ScrollSearchDirection.allCases.map(\.rawValue).joined(separator: ", "))")
                }
            }
            let searchTarget = ElementSearchTarget(
                elementTarget: target,
                direction: direction
            )
            let result = try await sendAndAwaitAction(.elementSearch(searchTarget), timeout: Timeouts.longActionSeconds)
            lastActionResult = result
            return .action(result: result)
        case .scrollToEdge:
            guard let edgeValue = args.string("edge") else {
                return .error("edge is required for scroll_to_edge. Valid: \(ScrollEdge.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            guard let edge = ScrollEdge(rawValue: edgeValue.lowercased()) else {
                return .error("Invalid edge '\(edgeValue)'. Valid: \(ScrollEdge.allCases.map(\.rawValue).joined(separator: ", "))")
            }
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
        guard let target = try elementTarget(args) else {
            return .error("Must specify element (heistId or matcher)")
        }

        // Resolve the action name: activate uses "action" param, standalone commands use the command itself
        let actionName: String? = switch command {
        case .activate: args.string("action")
        case .increment: "increment"
        case .decrement: "decrement"
        case .performCustomAction: args.string("action")
        default: nil
        }

        guard command != .performCustomAction || actionName != nil else {
            return .error("action is required")
        }

        // No action → default activation
        guard let actionName else {
            return try await sendAction(.activate(target))
        }

        // "action:foo" prefix forces custom action dispatch (escapes built-in names)
        if actionName.hasPrefix("action:") {
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
            return try await sendAction(.increment(target))
        case "decrement":
            return try await sendAction(.decrement(target))
        default:
            return try await sendAction(.performCustomAction(
                CustomActionTarget(elementTarget: target, actionName: actionName)))
        }
    }

    // MARK: - Handler: Text Input

    func handleTypeText(_ args: [String: Any]) async throws -> FenceResponse {
        let text = args.string("text")
        let deleteCount = args.integer("deleteCount")
        let clearFirst = args.boolean("clearFirst")
        guard text != nil || deleteCount != nil || clearFirst == true else {
            return .error("Must specify text, deleteCount, clearFirst, or a combination")
        }
        let result = try await sendAndAwaitAction(.typeText(TypeTextTarget(
            text: text, deleteCount: deleteCount, clearFirst: clearFirst, elementTarget: try elementTarget(args)
        )), timeout: Timeouts.longActionSeconds)
        lastActionResult = result
        return .action(result: result)
    }

    func handleEditAction(_ args: [String: Any]) async throws -> FenceResponse {
        guard let actionString = args.string("action") else {
            return .error("action is required (\(EditAction.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        guard let action = EditAction(rawValue: actionString) else {
            return .error("Invalid action '\(actionString)'. Valid: \(EditAction.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return try await sendAction(.editAction(EditActionTarget(action: action)))
    }

    // MARK: - Handler: Pasteboard

    func handleSetPasteboard(_ args: [String: Any]) async throws -> FenceResponse {
        guard let text = args.string("text") else {
            return .error("text is required for set_pasteboard")
        }
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
            absent: args.boolean("absent"),
            timeout: args.number("timeout")
        )
        let result = try await sendAndAwaitAction(.waitFor(waitForTarget), timeout: waitForTarget.resolvedTimeout + 5)
        lastActionResult = result
        return .action(result: result)
    }

    // MARK: - Handler: Wait For Change

    func handleWaitForChange(_ args: [String: Any]) async throws -> FenceResponse {
        let expectation = try parseExpectation(args)
        let timeout = args.number("timeout")
        let target = WaitForChangeTarget(expect: expectation, timeout: timeout)
        let result = try await sendAndAwaitAction(.waitForChange(target), timeout: target.resolvedTimeout + 5)
        lastActionResult = result
        return .action(result: result)
    }

    // MARK: - Handler: Recording

    func handleStartRecording(_ args: [String: Any]) async throws -> FenceResponse {
        guard handoff.isConnected else { throw FenceError.notConnected }
        guard !handoff.isRecording else {
            return .error("Recording already in progress — use stop_recording first")
        }
        let config = RecordingConfig(
            fps: args.integer("fps"),
            scale: args.number("scale"),
            inactivityTimeout: args.number("inactivity_timeout"),
            maxDuration: args.number("max_duration")
        )
        handoff.send(.startRecording(config))
        return .ok(message: "Recording start requested — use stop_recording to retrieve the video")
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
        let targetName = args.string("target")
        let device = args.string("device")
        let token = args.string("token")

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
            do {
                try await start()
            } catch {
                return .error("Connect failed and could not restore previous connection: \(error.displayMessage)")
            }
            return .error("Connect failed, restored previous connection: \(error.displayMessage)")
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
            if let url = try bookKeeper.writeArtifactIfSinkAvailable(
                base64Data: recording.videoData,
                outputPath: args.string("output"),
                requestId: artifactRequestId,
                command: .stopRecording,
                metadata: .recording(metadata)
            ) {
                return .recording(path: url.path, payload: recording)
            }
        } catch BookKeeperError.unsafePath {
            return .error("Invalid output path: must not contain '..' components")
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
            let deleteSource = args.boolean("delete_source") ?? false
            if case .active = bookKeeper.phase {
                try await bookKeeper.closeSession()
            }
            let (archiveURL, manifest) = try await bookKeeper.archiveSession(deleteSource: deleteSource)
            return .archiveResult(path: archiveURL.path, manifest: manifest)
        case .startHeist:
            let app = args.string("app") ?? "com.buttonheist.testapp"
            if bookKeeper.manifest == nil {
                let identifier = args.string("identifier") ?? "heist"
                try bookKeeper.beginSession(identifier: identifier)
            }
            try bookKeeper.startHeistRecording(app: app)
            return .heistStarted
        case .stopHeist:
            guard let outputPath = args.string("output") else {
                throw FenceError.invalidRequest("stop_heist requires an 'output' path")
            }
            guard let resolvedURL = bookKeeper.validateOutputPath(outputPath) else {
                throw FenceError.invalidRequest("Invalid output path: must not be empty or contain '..' components")
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
        guard let inputPath = args.string("input") else {
            throw FenceError.invalidRequest("play_heist requires an 'input' path")
        }
        guard let resolvedURL = bookKeeper.validateOutputPath(inputPath) else {
            throw FenceError.invalidRequest("Invalid input path: must not be empty or contain '..' components")
        }

        let heist = try TheBookKeeper.readHeist(from: resolvedURL)

        guard heist.version <= HeistPlayback.currentVersion else {
            throw FenceError.invalidRequest(
                "Heist file version \(heist.version) is newer than supported version \(HeistPlayback.currentVersion). Update Button Heist to play this file."
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

        playbackPhase = .playing
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
        case .error(let message):
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
