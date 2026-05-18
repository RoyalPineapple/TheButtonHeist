import Foundation
import os.log

import TheScore

private let logger = Logger(subsystem: "com.buttonheist.fence", category: "handlers")
private let accessibilityAdjustmentCountRange = 1...100

private extension Interface {
    func retainingElements(withIds heistIds: Set<String>) -> Interface {
        Interface(
            timestamp: timestamp,
            tree: tree.compactMap { $0.retainingElements(withIds: heistIds) }
        )
    }
}

private extension InterfaceNode {
    func retainingElements(withIds heistIds: Set<String>) -> InterfaceNode? {
        switch self {
        case .element(let element):
            return heistIds.contains(element.heistId) ? self : nil
        case .container(let info, let children):
            let filteredChildren = children.compactMap { $0.retainingElements(withIds: heistIds) }
            guard !filteredChildren.isEmpty else { return nil }
            return .container(info, children: filteredChildren)
        }
    }
}

@ButtonHeistActor
extension TheFence {

    // MARK: - Handler: Interface

    func handleGetInterface(_ request: GetInterfaceRequest) async throws -> FenceResponse {
        // Default scope: capture the app accessibility state and return all discovered elements.
        if request.scope == .full {
            let result = try await sendAndAwaitAction(.explore, timeout: Timeouts.exploreSeconds)
            lastActionHistory = .completed(result)
            guard case .explore(let exploreResult) = result.payload else {
                return .error("Explore failed: \(result.message ?? "unknown error")")
            }
            let interface = Interface(
                timestamp: Date(),
                tree: exploreResult.elements.map { .element($0) }
            )
            let filtered = filteredInterface(interface, request: request)
            return .interface(
                filtered.interface,
                detail: request.detail,
                filteredFrom: filtered.filteredFrom,
                explore: exploreResult
            )
        }

        let interface = try await sendAndAwaitInterface(.requestInterface, timeout: Timeouts.actionSeconds)
        let filtered = filteredInterface(interface, request: request)
        return .interface(filtered.interface, detail: request.detail, filteredFrom: filtered.filteredFrom)
    }

    private func filteredInterface(
        _ interface: Interface,
        request: GetInterfaceRequest
    ) -> (interface: Interface, filteredFrom: Int?) {
        // Matcher-based filtering takes precedence over heistId list
        if request.matcher.hasPredicates {
            let total = interface.elements.count
            let matchingIds = Set(interface.elements.filter { $0.matches(request.matcher) }.map(\.heistId))
            let filteredInterface = interface.retainingElements(withIds: matchingIds)
            return (filteredInterface, total)
        }

        if let filterIds = request.elementIds, !filterIds.isEmpty {
            let filterSet = Set(filterIds)
            let filteredInterface = interface.retainingElements(withIds: filterSet)
            return (filteredInterface, interface.elements.count)
        }
        return (interface, nil)
    }

    // MARK: - Handler: Screen

    func handleGetScreen(_ request: ArtifactRequest) async throws -> FenceResponse {
        let screen = try await sendAndAwaitScreen(.requestScreen, timeout: 30)
        let metadata = ScreenshotMetadata(width: screen.width, height: screen.height)
        do {
            if let url = try bookKeeper.writeScreenshotIfSinkAvailable(
                base64Data: screen.pngData,
                outputPath: request.outputPath,
                requestId: request.requestId,
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

    func handleGesture(_ payload: GesturePayload) async throws -> FenceResponse {
        switch payload {
        case .oneFingerTap(let target):
            if target.elementTarget == nil, target.point == nil {
                return .error("Must specify element (heistId or matcher) or coordinates (x, y)")
            }
            return try await sendAction(.touchTap(target))
        case .longPress(let target):
            if target.elementTarget == nil, target.point == nil {
                return .error("Must specify element (heistId or matcher) or coordinates (x, y)")
            }
            return try await sendAction(.touchLongPress(target))
        case .swipe(let target):
            if (target.start != nil) != (target.end != nil) {
                return .error("Unit-point swipe requires both start and end")
            }
            return try await sendAction(.touchSwipe(target))
        case .drag(let target):
            return try await sendAction(.touchDrag(target))
        case .pinch(let target):
            return try await sendAction(.touchPinch(target))
        case .rotate(let target):
            return try await sendAction(.touchRotate(target))
        case .twoFingerTap(let target):
            return try await sendAction(.touchTwoFingerTap(target))
        case .drawPath(let target):
            guard target.points.count >= 2 else {
                return .error("Path requires at least 2 points")
            }
            return try await sendAction(.touchDrawPath(target))
        case .drawBezier(let target):
            guard !target.segments.isEmpty else {
                return .error("At least 1 bezier segment is required")
            }
            return try await sendAction(.touchDrawBezier(target))
        }
    }

    // MARK: - Handler: Scroll Actions & Explore

    func handleScrollAction(_ payload: ScrollPayload) async throws -> FenceResponse {
        switch payload {
        case .scroll(let target):
            guard target.elementTarget != nil else {
                return missingElementTargetResponse(command: Command.scroll.rawValue)
            }
            return try await sendAction(.scroll(target))
        case .scrollToVisible(let target):
            guard target.elementTarget != nil else {
                return missingElementTargetResponse(command: Command.scrollToVisible.rawValue)
            }
            let result = try await sendAndAwaitAction(.scrollToVisible(target), timeout: Timeouts.actionSeconds)
            lastActionHistory = .completed(result)
            return .action(result: result)
        case .elementSearch(let target):
            guard target.elementTarget != nil else {
                return missingElementTargetResponse(command: Command.elementSearch.rawValue)
            }
            let result = try await sendAndAwaitAction(.elementSearch(target), timeout: Timeouts.longActionSeconds)
            lastActionHistory = .completed(result)
            return .action(result: result)
        case .scrollToEdge(let target):
            guard target.elementTarget != nil else {
                return missingElementTargetResponse(command: Command.scrollToEdge.rawValue)
            }
            return try await sendAction(.scrollToEdge(target))
        }
    }

    // MARK: - Handler: Accessibility Actions

    func handleAccessibilityAction(_ payload: AccessibilityPayload) async throws -> FenceResponse {
        switch payload {
        case .activate(let target, let actionName, let count):
            guard let actionName else {
                try rejectCount(count)
                return try await sendAction(.activate(target))
            }
            return try await handleNamedAccessibilityAction(
                target: target,
                actionName: actionName,
                count: count
            )
        case .increment(let target, let count):
            let count = try accessibilityAdjustmentCount(count)
            return try await sendRepeatedAdjustment(.increment(target), actionName: Command.increment.rawValue, count: count)
        case .decrement(let target, let count):
            let count = try accessibilityAdjustmentCount(count)
            return try await sendRepeatedAdjustment(.decrement(target), actionName: Command.decrement.rawValue, count: count)
        case .performCustomAction(let target, let actionName, let count):
            return try await handleNamedAccessibilityAction(
                target: target,
                actionName: actionName,
                count: count
            )
        }
    }

    private func handleNamedAccessibilityAction(
        target: ElementTarget,
        actionName: String,
        count: CountArgument
    ) async throws -> FenceResponse {
        // "action:foo" prefix forces custom action dispatch (escapes built-in names)
        if actionName.hasPrefix("action:") {
            try rejectCount(count)
            let customName = String(actionName.dropFirst("action:".count))
            guard !customName.isEmpty else {
                return .error("action: prefix requires a name (e.g. \"action:myAction\")")
            }
            return try await sendAction(.performCustomAction(
                CustomActionTarget(elementTarget: target, actionName: customName)))
        }

        // Built-in actions map to their wire messages; everything else is a custom action
        switch actionName {
        case Command.increment.rawValue:
            let count = try accessibilityAdjustmentCount(count)
            return try await sendRepeatedAdjustment(.increment(target), actionName: actionName, count: count)
        case Command.decrement.rawValue:
            let count = try accessibilityAdjustmentCount(count)
            return try await sendRepeatedAdjustment(.decrement(target), actionName: actionName, count: count)
        default:
            try rejectCount(count)
            return try await sendAction(.performCustomAction(
                CustomActionTarget(elementTarget: target, actionName: actionName)))
        }
    }

    private func accessibilityAdjustmentCount(_ countArgument: CountArgument) throws -> Int {
        let count = countArgument.value ?? 1
        guard accessibilityAdjustmentCountRange.contains(count) else {
            throw SchemaValidationError(
                field: "count",
                observed: count,
                expected: "integer in \(accessibilityAdjustmentCountRange.lowerBound)...\(accessibilityAdjustmentCountRange.upperBound)"
            )
        }
        return count
    }

    private func rejectCount(_ countArgument: CountArgument) throws {
        guard countArgument.observed != nil else { return }
        throw SchemaValidationError(
            field: "count",
            observed: countArgument.observed,
            expected: "only valid with increment or decrement"
        )
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

    func handleRotor(_ target: RotorTarget) async throws -> FenceResponse {
        return try await sendAction(.rotor(target))
    }

    // MARK: - Handler: Text Input

    func handleTypeText(_ target: TypeTextTarget) async throws -> FenceResponse {
        if let text = target.text, text.isEmpty {
            throw SchemaValidationError(field: "text", observed: text as Any, expected: "non-empty string")
        }
        if let deleteCount = target.deleteCount, deleteCount <= 0 {
            throw SchemaValidationError(field: "deleteCount", observed: deleteCount, expected: "integer >= 1")
        }
        guard target.text != nil || target.deleteCount != nil || target.clearFirst == true else {
            return .error("Must specify text, deleteCount, clearFirst, or a combination")
        }

        let result = try await sendAndAwaitAction(.typeText(target), timeout: Timeouts.longActionSeconds)
        lastActionHistory = .completed(result)
        return .action(result: result)
    }

    func handleEditAction(_ target: EditActionTarget) async throws -> FenceResponse {
        return try await sendAction(.editAction(target))
    }

    // MARK: - Handler: Pasteboard

    func handleSetPasteboard(_ target: SetPasteboardTarget) async throws -> FenceResponse {
        return try await sendAction(.setPasteboard(target))
    }

    func handleGetPasteboard() async throws -> FenceResponse {
        return try await sendAction(.getPasteboard)
    }

    // MARK: - Handler: Wait For

    func handleWaitFor(_ target: WaitForTarget) async throws -> FenceResponse {
        let result = try await sendAndAwaitAction(.waitFor(target), timeout: target.resolvedTimeout + 5)
        lastActionHistory = .completed(result)
        return .action(result: result)
    }

    func missingElementTargetResponse(command: String) -> FenceResponse {
        let contract = "requires heistId or at least one matcher field (label, identifier, value, traits, or excludeTraits)"
        let next = "get_interface()"
        let message = "\(command) request contract failed: missing target; \(contract). " +
            "Next: \(next) to inspect the current app accessibility state, then retry \(command) with a heistId or exact matcher."
        return .error(
            message,
            details: FailureDetails(
                errorCode: FenceRequestErrorCode.missingTarget,
                phase: .request,
                retryable: false,
                hint: next
            )
        )
    }

    // MARK: - Handler: Wait For Change

    func handleWaitForChange(_ payload: ExpectationPayload) async throws -> FenceResponse {
        let target = WaitForChangeTarget(expect: payload.expectation, timeout: payload.timeout)
        let result = try await sendAndAwaitAction(.waitForChange(target), timeout: target.resolvedTimeout + 5)
        lastActionHistory = .completed(result)
        return .action(result: result)
    }

    // MARK: - Handler: Recording

    func handleStartRecording(_ config: RecordingConfig) async throws -> FenceResponse {
        guard handoff.isConnected else { throw FenceError.notConnected }
        guard !isRecording else {
            return .error("Recording already in progress — use stop_recording first")
        }
        if let fps = config.fps, fps < 1 || fps > 15 {
            throw SchemaValidationError(field: "fps", observed: fps, expected: "integer in 1...15")
        }
        if let scale = config.scale, scale < 0.25 || scale > 1.0 {
            throw SchemaValidationError(field: "scale", observed: scale, expected: "number in 0.25...1.0")
        }
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

    private func establishSessionOnly() async throws -> FenceResponse {
        try await start()
        return .sessionState(payload: currentSessionState())
    }

    func handleConnect(_ request: ConnectRequest) async throws -> FenceResponse {
        let resolvedDevice: String
        let resolvedToken: String?
        let resolvedDirectDevice: DiscoveredDevice?

        if let device = request.device {
            resolvedDevice = device
            resolvedToken = request.token
            resolvedDirectDevice = nil
        } else if let targetName = request.targetName {
            guard let fileConfig = config.fileConfig else {
                return .error("No config file loaded. Create .buttonheist.json or ~/.config/buttonheist/config.json")
            }
            guard let target = fileConfig.targets[targetName] else {
                let available = fileConfig.targets.keys.sorted()
                return .error("Unknown target '\(targetName)'. Available: \(available.joined(separator: ", "))")
            }
            resolvedDevice = target.device
            resolvedToken = request.token ?? target.token
            resolvedDirectDevice = DiscoveredDevice.fromHostPort(
                target.device,
                id: "config-\(targetName)",
                name: targetName,
                certFingerprint: target.certFingerprint
            )
        } else if handoff.isConnected || config.deviceFilter != nil || config.directDevice != nil {
            return try await establishSessionOnly()
        } else {
            return .error("Must specify 'target' (named config target), 'device' (host:port), or configure BUTTONHEIST_DEVICE/.buttonheist.json")
        }

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
            let connectionFailure = error as? FenceError
            let connectionFailureDetails = connectionFailure?.failureDetails
            let connectionFailureMessage = connectionFailure?.coreMessage ?? error.displayMessage
            handoff.disableAutoReconnect()
            handoff.stopDiscovery()
            clearClientSessionState(error: connectionFailure ?? FenceError.notConnected)
            return .error(
                "Connect failed; disconnected from previous target: \(connectionFailureMessage)",
                details: connectionFailureDetails
            )
        }

        return .sessionState(payload: currentSessionState())
    }

    func handleListTargets() -> FenceResponse {
        guard let fileConfig = config.fileConfig else {
            return .targets([:], defaultTarget: nil)
        }
        return .targets(fileConfig.targets, defaultTarget: fileConfig.defaultTarget)
    }

    func handleStopRecording(_ request: ArtifactRequest) async throws -> FenceResponse {
        guard handoff.isConnected else { throw FenceError.notConnected }
        let recording: RecordingPayload = try await stopRecordingAndWait(timeout: Timeouts.longActionSeconds)
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
                outputPath: request.outputPath,
                requestId: request.requestId,
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

    func handleGetSessionLog() -> FenceResponse {
        guard let manifest = bookKeeper.manifest else {
            return .error("No active session")
        }
        return .sessionLog(manifest: manifest)
    }

    func handleArchiveSession(_ request: ArchiveSessionRequest) async throws -> FenceResponse {
        // Drive whatever phase we observe toward .closed before archiving.
        switch bookKeeper.phase {
        case .idle:
            // No session to close. archiveSession will surface the phase
            // mismatch with a clean error message rather than silently
            // falling through as if .active.
            break
        case .active:
            try await bookKeeper.closeSession()
        case .closing:
            // A prior close is mid-flight (or its compression failed and left
            // us stuck). Don't attempt closeSession again; archiveSession will
            // surface the diagnostic.
            break
        case .closed, .archived:
            break
        }
        let (archiveURL, manifest) = try await bookKeeper.archiveSession(deleteSource: request.deleteSource)
        return .archiveResult(path: archiveURL.path, manifest: manifest)
    }

    func handleStartHeist(_ request: StartHeistRequest) throws -> FenceResponse {
        if bookKeeper.manifest == nil {
            try bookKeeper.beginSession(identifier: request.identifier)
        }
        try bookKeeper.startHeistRecording(app: request.app)
        return .heistStarted
    }

    func handleStopHeist(_ request: StopHeistRequest) throws -> FenceResponse {
        guard let resolvedURL = bookKeeper.validateOutputPath(request.outputPath) else {
            throw FenceError.invalidRequest("Invalid output path: must not be empty, contain '..' components, or contain control characters")
        }
        let heist = try bookKeeper.stopHeistRecording()
        try TheBookKeeper.writeHeist(heist, to: resolvedURL)
        return .heistStopped(path: resolvedURL.path, stepCount: heist.steps.count)
    }

    func handlePlayHeist(_ request: PlayHeistRequest) async throws -> FenceResponse {
        guard case .idle = playbackPhase else {
            throw FenceError.invalidRequest("Cannot nest play_heist inside an active playback")
        }
        guard let resolvedURL = bookKeeper.validateOutputPath(request.inputPath) else {
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

        let typedPlayback = try TypedHeistPlayback(wire: heist)
        let heistName = resolvedURL.deletingPathExtension().lastPathComponent
        let playbackStart = CFAbsoluteTimeGetCurrent()
        var completedSteps = 0
        var failedIndex: Int?
        var failure: PlaybackFailure?
        var stepResults: [HeistPlaybackReport.StepResult] = []

        playbackPhase = .playing(startedAt: Date())
        defer { playbackPhase = .idle }

        // Prime current element data before playback.
        _ = try await execute(request: ["command": Command.getInterface.rawValue])

        for (index, operation) in typedPlayback.steps.enumerated() {
            let stepStart = CFAbsoluteTimeGetCurrent()
            var stepFailure: PlaybackFailure?

            do {
                let response = try await execute(playback: operation)
                stepFailure = playbackFailure(operation: operation, response: response)
            } catch {
                let failedStep = PlaybackFailure.FailedStep(command: operation.commandName, target: operation.target)
                stepFailure = .thrown(step: failedStep, error: error.localizedDescription, interface: nil)
            }

            let stepTime = CFAbsoluteTimeGetCurrent() - stepStart
            stepResults.append(stepResult(index: index, operation: operation, timeSeconds: stepTime, failure: stepFailure))

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
            app: typedPlayback.app,
            totalStepCount: typedPlayback.totalStepCount,
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
        index: Int, operation: PlaybackOperation, timeSeconds: Double, failure: PlaybackFailure?
    ) -> HeistPlaybackReport.StepResult {
        let outcome: HeistPlaybackReport.Outcome
        if let failure {
            outcome = .failed(
                message: failure.errorMessage,
                errorKind: failure.step.command == operation.commandName ? failureErrorKind(failure) : nil
            )
        } else {
            outcome = .passed
        }
        return HeistPlaybackReport.StepResult(
            index: index,
            command: operation.commandName,
            target: operation.target,
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
    private func playbackFailure(operation: PlaybackOperation, response: FenceResponse) -> PlaybackFailure? {
        let failedStep = PlaybackFailure.FailedStep(command: operation.commandName, target: operation.target)
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
            let response = try await execute(request: ["command": Command.getInterface.rawValue])
            if case .interface(let snapshot, _, _, _) = response {
                return snapshot
            }
        } catch {
            logger.error("Failed to capture interface for playback diagnostics: \(error.localizedDescription)")
        }
        return nil
    }

}
