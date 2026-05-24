import Foundation
import os.log

import TheScore

private let logger = Logger(subsystem: "com.buttonheist.fence", category: "handlers")
private let accessibilityAdjustmentCountRange = 1...100

private extension ScreenPayload {
    func responsePayload(includeInterface: Bool) -> ScreenPayload {
        ScreenPayload(
            pngData: pngData,
            width: width,
            height: height,
            timestamp: timestamp,
            interface: includeInterface ? interface : Interface(timestamp: timestamp, tree: [])
        )
    }
}

@ButtonHeistActor
extension TheFence {

    // MARK: - Handler: Interface

    func handlePing() async throws -> FenceResponse {
        let payload = try await sendAndAwaitPong(timeout: Timeouts.healthSeconds)
        return .pong(payload)
    }

    func handleGetInterface(_ request: GetInterfaceRequest) async throws -> FenceResponse {
        let interface = try await sendAndAwaitInterface(
            .requestInterface(request.query),
            timeout: Timeouts.exploreSeconds
        )
        return .interface(interface, detail: request.detail)
    }

    // MARK: - Handler: Screen

    func handleGetScreen(_ request: ScreenRequest) async throws -> FenceResponse {
        let screen = try await sendAndAwaitScreen(.requestScreen, timeout: 30)
        let metadata = ScreenshotMetadata(width: screen.width, height: screen.height)
        let responsePayload = screen.responsePayload(includeInterface: request.includeInterface)
        let options = ScreenshotResponseOptions(includeInterface: request.includeInterface)

        if request.inlineData {
            let byteCount = screen.pngData.utf8.count
            guard byteCount <= DecodeLimits.maxInlineScreenshotBase64Bytes else {
                return .error(
                    "Inline screenshot payload is too large: \(byteCount) bytes exceeds " +
                        "\(DecodeLimits.maxInlineScreenshotBase64Bytes) bytes",
                    details: FailureDetails(
                        errorCode: "screen.inline_payload_too_large",
                        phase: .client,
                        retryable: false,
                        hint: "Omit inlineData or pass output to receive a screenshot artifact path."
                    )
                )
            }
            return .screenshotData(payload: responsePayload, options: options)
        }

        do {
            let url = try bookKeeper.writeScreenshotArtifact(
                base64Data: screen.pngData,
                outputPath: request.outputPath,
                requestId: request.requestId,
                command: .getScreen,
                metadata: metadata
            )
            return .screenshot(path: url.path, payload: responsePayload, options: options)
        } catch BookKeeperError.unsafePath {
            return .error("Invalid output path: must not contain '..' components or control characters")
        } catch BookKeeperError.base64DecodingFailed {
            return .error("Failed to decode screenshot data")
        }
    }

    // MARK: - Handler: Gestures

    func handleOneFingerTap(_ payload: TouchTapGesturePayload) async throws -> FenceResponse {
        try await sendAction(.touchTap(payload.target))
    }

    func handleLongPress(_ payload: LongPressGesturePayload) async throws -> FenceResponse {
        try await sendAction(.touchLongPress(payload.target))
    }

    func handleSwipe(_ payload: SwipeGesturePayload) async throws -> FenceResponse {
        try await sendAction(.touchSwipe(payload.target))
    }

    func handleDrag(_ payload: DragGesturePayload) async throws -> FenceResponse {
        try await sendAction(.touchDrag(payload.target))
    }

    func handlePinch(_ payload: PinchGesturePayload) async throws -> FenceResponse {
        try await sendAction(.touchPinch(payload.target))
    }

    func handleRotate(_ payload: RotateGesturePayload) async throws -> FenceResponse {
        try await sendAction(.touchRotate(payload.target))
    }

    func handleTwoFingerTap(_ payload: TwoFingerTapGesturePayload) async throws -> FenceResponse {
        try await sendAction(.touchTwoFingerTap(payload.target))
    }

    func handleDrawPath(_ payload: DrawPathGesturePayload) async throws -> FenceResponse {
        try await sendAction(.touchDrawPath(payload.target))
    }

    func handleDrawBezier(_ payload: DrawBezierGesturePayload) async throws -> FenceResponse {
        try await sendAction(.touchDrawBezier(payload.target))
    }

    // MARK: - Handler: Scroll Actions & Explore

    func handleScrollAction(_ payload: ScrollPayload) async throws -> FenceResponse {
        switch payload {
        case .scroll(let target):
            return try await sendAction(.scroll(target))
        case .scrollToVisible(let target):
            let result = try await sendAndAwaitAction(.scrollToVisible(target), timeout: Timeouts.actionSeconds)
            recordCompletedAction(result)
            return .action(result: result)
        case .elementSearch(let target):
            let result = try await sendAndAwaitAction(.elementSearch(target), timeout: Timeouts.longActionSeconds)
            recordCompletedAction(result)
            return .action(result: result)
        case .scrollToEdge(let target):
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
        case .performCustomAction(let target, let count):
            return try await handleNamedAccessibilityAction(
                target: target,
                count: count
            )
        }
    }

    private func handleNamedAccessibilityAction(
        target: CustomActionTarget,
        count: CountArgument
    ) async throws -> FenceResponse {
        if let elementTarget = target.elementTarget {
            return try await handleNamedAccessibilityAction(
                target: elementTarget,
                actionName: target.actionName,
                count: count
            )
        }
        try rejectCount(count)
        return try await sendAction(.performCustomAction(target))
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
            recordCompletedAction(result)
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
        let result = try await sendAndAwaitAction(.typeText(target), timeout: Timeouts.longActionSeconds)
        recordCompletedAction(result)
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
        let result = try await sendAndAwaitAction(.getPasteboard, timeout: Timeouts.healthSeconds)
        return .action(result: result)
    }

    // MARK: - Handler: Wait For

    func handleWaitFor(_ target: WaitForTarget) async throws -> FenceResponse {
        let result = try await sendAndAwaitAction(.waitFor(target), timeout: target.resolvedTimeout + 5)
        recordCompletedAction(result)
        return .action(result: result)
    }

    func missingElementTargetResponse(command: String) -> FenceResponse {
        let contract = "requires heistId, ordinal, or at least one matcher field (label, identifier, value, traits, or excludeTraits)"
        let next = "get_interface()"
        let message = "\(command) request contract failed: missing target; \(contract). " +
            "Next: \(next) to inspect the current app accessibility state, then retry \(command) with a heistId, exact matcher, or ordinal fallback."
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
        recordCompletedAction(result)
        return .action(result: result)
    }

    // MARK: - Handler: Recording

    func handleStartRecording(_ config: RecordingConfig) async throws -> FenceResponse {
        guard handoff.isConnected else { throw FenceError.notConnected }
        guard !isRecording else {
            return .error("Recording already in progress — use stop_recording first")
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
            directDevice: resolvedDirectDevice,
            bookKeeperBaseDirectory: config.bookKeeperBaseDirectory
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
        let responseOptions = RecordingResponseOptions(
            inlineData: request.inlineData,
            includeInteractionLog: request.includeInteractionLog
        )
        if let expandedResponseError = validateExpandedRecordingResponse(
            recording,
            options: responseOptions
        ) {
            return expandedResponseError
        }
        do {
            let url = try bookKeeper.writeRecordingArtifact(
                base64Data: recording.videoData,
                outputPath: request.outputPath,
                requestId: request.requestId,
                command: .stopRecording,
                metadata: metadata
            )
            if request.inlineData || request.includeInteractionLog {
                let response = FenceResponse.recordingExpanded(
                    path: url.path,
                    payload: recording,
                    options: responseOptions
                )
                if let oversizedResponseError = validateExpandedRecordingResponseSize(response) {
                    return oversizedResponseError
                }
                return response
            }
            return .recording(path: url.path, payload: recording)
        } catch BookKeeperError.unsafePath {
            return .error("Invalid output path: must not contain '..' components or control characters")
        } catch BookKeeperError.base64DecodingFailed {
            return .error("Failed to decode video data")
        }
    }

    private func validateExpandedRecordingResponse(
        _ recording: RecordingPayload,
        options: RecordingResponseOptions
    ) -> FenceResponse? {
        guard options.inlineData else { return nil }
        let byteCount = recording.videoData.utf8.count
        guard byteCount <= DecodeLimits.maxInlineRecordingBase64Bytes else {
            return .error(
                "Inline recording payload is too large: \(byteCount) bytes exceeds " +
                    "\(DecodeLimits.maxInlineRecordingBase64Bytes) bytes",
                details: FailureDetails(
                    errorCode: "recording.inline_payload_too_large",
                    phase: .client,
                    retryable: false,
                    hint: "Omit inlineData to receive a recording artifact path."
                )
            )
        }
        return nil
    }

    private func validateExpandedRecordingResponseSize(_ response: FenceResponse) -> FenceResponse? {
        let data: Data
        do {
            data = try response.jsonData(outputFormatting: [.sortedKeys])
        } catch {
            return .error(
                "Failed to encode expanded recording response",
                details: FailureDetails(
                    errorCode: "recording.expanded_response_encoding_failed",
                    phase: .client,
                    retryable: false,
                    hint: "Omit inlineData or includeInteractionLog and retry."
                )
            )
        }
        guard data.count <= DecodeLimits.maxExpandedRecordingResponseBytes else {
            return .error(
                "Expanded recording response is too large: \(data.count) bytes exceeds " +
                    "\(DecodeLimits.maxExpandedRecordingResponseBytes) bytes",
                details: FailureDetails(
                    errorCode: "recording.expanded_response_too_large",
                    phase: .client,
                    retryable: false,
                    hint: "Omit inlineData or includeInteractionLog to receive a recording artifact path and metadata."
                )
            )
        }
        return nil
    }

    // MARK: - Handler: BookKeeper

    func handleGetSessionLog() throws -> FenceResponse {
        guard let snapshot = try bookKeeper.sessionLogSnapshot() else {
            return .error("No active session")
        }
        return .sessionLog(snapshot: snapshot)
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
            // A prior close either still owns compression or left a retryable
            // failed compression. closeSession coalesces or retries it.
            try await bookKeeper.closeSession()
        case .closed, .archived:
            break
        }
        let (archiveURL, snapshot) = try await bookKeeper.archiveSession(deleteSource: request.deleteSource)
        return .archiveResult(path: archiveURL.path, snapshot: snapshot)
    }

    func handleStartHeist(_ request: StartHeistRequest) throws -> FenceResponse {
        if bookKeeper.manifest == nil {
            try bookKeeper.beginSession(identifier: request.identifier)
        }
        try bookKeeper.startHeistRecording(app: request.app)
        beginRecordingAccessibilityHistoryRetention()
        return .heistStarted
    }

    func handleStopHeist(_ request: StopHeistRequest) throws -> FenceResponse {
        guard let resolvedURL = bookKeeper.validateOutputPath(request.outputPath) else {
            throw FenceError.invalidRequest("Invalid output path: must not be empty, contain '..' components, or contain control characters")
        }
        do {
            let heist = try bookKeeper.stopHeistRecording()
            endRecordingAccessibilityHistoryRetention()
            try TheBookKeeper.writeHeist(heist, to: resolvedURL)
            return .heistStopped(path: resolvedURL.path, stepCount: heist.steps.count)
        } catch {
            if !bookKeeper.isRecordingHeist {
                endRecordingAccessibilityHistoryRetention()
            }
            throw error
        }
    }

    func handlePlayHeist(_ request: PlayHeistRequest) async throws -> FenceResponse {
        try playback.begin()
        defer { playback.end() }

        guard let resolvedURL = bookKeeper.validateOutputPath(request.inputPath) else {
            throw FenceError.invalidRequest("Invalid input path: must not be empty or contain '..' components")
        }

        let typedPlayback = try TypedHeistPlayback(contentsOf: resolvedURL)

        // Warn if the connected app doesn't match the app the heist was recorded against
        if let connectedBundle = handoff.serverInfo?.bundleIdentifier,
           connectedBundle != typedPlayback.app {
            logger.warning(
                "Heist was recorded against \(typedPlayback.app) but connected app is \(connectedBundle)"
            )
        }

        let heistName = resolvedURL.deletingPathExtension().lastPathComponent
        let playbackStart = CFAbsoluteTimeGetCurrent()
        var completedSteps = 0
        var failedIndex: Int?
        var failure: PlaybackFailure?
        var stepResults: [HeistPlaybackReport.StepResult] = []

        // Prime current element data before playback.
        try await primePlaybackInterface()

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

            if index < typedPlayback.steps.index(before: typedPlayback.steps.endIndex) {
                try await primePlaybackInterface()
            }
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

    private func primePlaybackInterface() async throws {
        _ = try await execute(parsed: defaultGetInterfaceParsedRequest())
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
            let response = try await execute(parsed: defaultGetInterfaceParsedRequest())
            if case .interface(let snapshot, _) = response {
                return snapshot
            }
        } catch {
            logger.error("Failed to capture interface for playback diagnostics: \(error.localizedDescription)")
        }
        return nil
    }

}
