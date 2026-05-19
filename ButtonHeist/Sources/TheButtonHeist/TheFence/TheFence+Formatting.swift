import Foundation

import TheScore

/// Level of detail for interface responses.
public enum InterfaceDetail: String, CaseIterable, Sendable {
    case summary
    case full
}

/// Summary of a single step within a batch execution.
///
/// Consumed by batch formatters to build per-step human/JSON rows. `deltaKind`
/// is the wire-level `kind` discriminator from the step's `AccessibilityTrace.Delta`;
/// `expectationMet` is nil when the step had no expectation attached.
public struct BatchStepSummary: Sendable {
    public let command: String
    public let deltaKind: String?
    public let screenName: String?
    public let screenId: String?
    public let expectationMet: Bool?
    public let elementCount: Int?
    public let error: String?
    public let errorCode: String?
    public let phase: String?
    public let nextCommand: String?

    public init(
        command: String,
        deltaKind: String?,
        screenName: String?,
        screenId: String?,
        expectationMet: Bool?,
        elementCount: Int?,
        error: String?,
        errorCode: String? = nil,
        phase: String? = nil,
        nextCommand: String? = nil
    ) {
        self.command = command
        self.deltaKind = deltaKind
        self.screenName = screenName
        self.screenId = screenId
        self.expectationMet = expectationMet
        self.elementCount = elementCount
        self.error = error
        self.errorCode = errorCode
        self.phase = phase
        self.nextCommand = nextCommand
    }
}

public struct BatchStepOutcome {
    public enum Result {
        case response(FenceResponse)
        case skipped(reason: String, afterFailedIndex: Int)
    }

    public let command: String
    public let result: Result
    public let diagnosticDetails: FailureDetails?
    public let stopsBatch: Bool

    public init(
        command: String,
        response: FenceResponse,
        diagnosticDetails: FailureDetails? = nil,
        stopsBatch: Bool = false
    ) {
        self.command = command
        self.result = .response(response)
        self.diagnosticDetails = diagnosticDetails
        self.stopsBatch = stopsBatch
    }

    private init(
        command: String,
        result: Result,
        diagnosticDetails: FailureDetails? = nil,
        stopsBatch: Bool = false
    ) {
        self.command = command
        self.result = result
        self.diagnosticDetails = diagnosticDetails
        self.stopsBatch = stopsBatch
    }

    public static func skipped(command: String, afterFailedIndex failedIndex: Int) -> BatchStepOutcome {
        BatchStepOutcome(
            command: command,
            result: .skipped(reason: "skipped: stop_on_error stopped batch after step \(failedIndex)", afterFailedIndex: failedIndex)
        )
    }
}

extension BatchStepOutcome {
    var response: FenceResponse? {
        guard case .response(let response) = result else { return nil }
        return response
    }

    var isCompleted: Bool {
        response != nil
    }

    var isFailed: Bool {
        response?.isFailure == true
    }

    var hasActionResult: Bool {
        guard case .action = response else { return false }
        return true
    }

    var accessibilityTrace: AccessibilityTrace? {
        guard case .action(let result, _) = response else { return nil }
        return result.accessibilityTrace
    }

    var expectationCounted: Bool {
        guard case .action(_, let expectation) = response else { return false }
        return expectation?.expectation != nil
    }

    var expectationMet: Bool? {
        guard expectationCounted, case .action(_, let expectation) = response else { return nil }
        return expectation?.met
    }

    var stepSummary: BatchStepSummary {
        switch result {
        case .response(let response):
            return Self.makeStepSummary(
                command: command,
                response: response,
                diagnosticDetails: diagnosticDetails,
                expectationMet: expectationCounted ? expectationMet : nil
            )
        case .skipped(let reason, _):
            return BatchStepSummary(
                command: command,
                deltaKind: nil,
                screenName: nil,
                screenId: nil,
                expectationMet: nil,
                elementCount: nil,
                error: reason
            )
        }
    }

    private static func makeStepSummary(
        command: String,
        response: FenceResponse,
        diagnosticDetails: FailureDetails?,
        expectationMet: Bool?
    ) -> BatchStepSummary {
        switch response {
        case .action(let result, _):
            return BatchStepSummary(
                command: command,
                deltaKind: result.accessibilityDelta?.kindRawValue,
                screenName: result.screenName,
                screenId: result.screenId,
                expectationMet: expectationMet,
                elementCount: nil,
                error: result.success ? nil : result.message
            )
        case .interface(let iface, _):
            return BatchStepSummary(
                command: command, deltaKind: nil, screenName: nil, screenId: nil,
                expectationMet: nil, elementCount: iface.elements.count, error: nil
            )
        case .error(let message, let details):
            let details = details ?? diagnosticDetails
            return BatchStepSummary(
                command: command, deltaKind: nil, screenName: nil, screenId: nil,
                expectationMet: nil, elementCount: nil, error: message,
                errorCode: details?.errorCode,
                phase: details?.phase.rawValue,
                nextCommand: batchNextCommand(from: details)
            )
        default:
            return BatchStepSummary(
                command: command, deltaKind: nil, screenName: nil, screenId: nil,
                expectationMet: nil, elementCount: nil, error: nil
            )
        }
    }

    private static func batchNextCommand(from details: FailureDetails?) -> String? {
        guard details?.errorCode == FenceRequestErrorCode.missingTarget else { return nil }
        return details?.hint
    }
}

extension Array where Element == BatchStepOutcome {
    var completedStepCount: Int {
        count(where: \.isCompleted)
    }

    var stoppedFailedIndex: Int? {
        firstIndex(where: \.stopsBatch)
    }

    var expectationsChecked: Int {
        count(where: \.expectationCounted)
    }

    var expectationsMet: Int {
        count(where: { $0.expectationMet == true })
    }

    var stepSummaries: [BatchStepSummary] {
        map(\.stepSummary)
    }

    var jsonResultRows: [[String: Any]] {
        compactMap { $0.response?.jsonDict() }
    }
}

public enum SessionConnectionPhase: String, Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case failed
}

public struct SessionDevicePayload: Sendable, Equatable {
    public let deviceName: String
    public let appName: String
    public let connectionType: ConnectionScope
    public let shortId: String?

    public init(
        deviceName: String,
        appName: String,
        connectionType: ConnectionScope,
        shortId: String?
    ) {
        self.deviceName = deviceName
        self.appName = appName
        self.connectionType = connectionType
        self.shortId = shortId
    }
}

public struct SessionFailurePayload: Sendable, Equatable {
    public let errorCode: String
    public let phase: FailurePhase
    public let retryable: Bool
    public let message: String?
    public let hint: String?

    public init(
        errorCode: String,
        phase: FailurePhase,
        retryable: Bool,
        message: String?,
        hint: String?
    ) {
        self.errorCode = errorCode
        self.phase = phase
        self.retryable = retryable
        self.message = message
        self.hint = hint
    }
}

public struct SessionLastActionPayload: Sendable, Equatable {
    public let method: ActionMethod
    public let success: Bool
    public let message: String?
    public let latencyMs: Int

    public init(method: ActionMethod, success: Bool, message: String?, latencyMs: Int) {
        self.method = method
        self.success = success
        self.message = message
        self.latencyMs = latencyMs
    }
}

public struct SessionStatePayload: Sendable, Equatable {
    public let connected: Bool
    public let phase: SessionConnectionPhase
    public let device: SessionDevicePayload?
    public let isRecording: Bool
    public let actionTimeoutSeconds: TimeInterval
    public let longActionTimeoutSeconds: TimeInterval
    public let lastFailure: SessionFailurePayload?
    public let lastAction: SessionLastActionPayload?

    public init(
        connected: Bool,
        phase: SessionConnectionPhase,
        device: SessionDevicePayload?,
        isRecording: Bool,
        actionTimeoutSeconds: TimeInterval,
        longActionTimeoutSeconds: TimeInterval,
        lastFailure: SessionFailurePayload?,
        lastAction: SessionLastActionPayload?
    ) {
        self.connected = connected
        self.phase = phase
        self.device = device
        self.isRecording = isRecording
        self.actionTimeoutSeconds = actionTimeoutSeconds
        self.longActionTimeoutSeconds = longActionTimeoutSeconds
        self.lastFailure = lastFailure
        self.lastAction = lastAction
    }
}

enum FenceRequestErrorCode {
    static let missingTarget = "request.missing_target"
}

/// Typed response from TheFence command execution.
///
/// Cases marked `…Data` carry the raw payload in memory (base64-encoded) and are
/// returned when no session is active and no explicit `output:` path was given.
/// Cases without the `Data` suffix carry a filesystem path where the artifact
/// has been written and are returned when a session is active or `output:` was
/// specified.
public enum FenceResponse {
    case ok(message: String)
    case error(String, details: FailureDetails? = nil)
    case help(commands: [String])
    case status(connected: Bool, deviceName: String?)
    case devices([DiscoveredDevice])
    case interface(Interface, detail: InterfaceDetail = .summary)
    case action(result: ActionResult, expectation: ExpectationResult? = nil)
    /// Screenshot written to disk. `path` is the resolved filesystem location.
    case screenshot(path: String, payload: ScreenPayload)
    /// Screenshot held in memory as base64 PNG. Returned when no session is
    /// active and no explicit output path was requested.
    case screenshotData(payload: ScreenPayload)
    /// Recording written to disk. `path` is the resolved filesystem location.
    case recording(path: String, payload: RecordingPayload)
    /// Recording held in memory. Returned when no session is active and no
    /// explicit output path was requested.
    case recordingData(payload: RecordingPayload)
    case batch(
        outcomes: [BatchStepOutcome],
        totalTimingMs: Int,
        accessibilityTrace: AccessibilityTrace? = nil
    )
    case sessionState(payload: SessionStatePayload)
    case targets([String: TargetConfig], defaultTarget: String?)
    case sessionLog(snapshot: SessionLogSnapshot)
    case archiveResult(path: String, snapshot: SessionLogSnapshot)
    case heistStarted
    case heistStopped(path: String, stepCount: Int)
    case heistPlayback(completedSteps: Int, failedIndex: Int?, totalTimingMs: Int, failure: PlaybackFailure? = nil, report: HeistPlaybackReport? = nil)

    /// Extract the ActionResult if this response wraps one (for expectation checking).
    var actionResult: ActionResult? {
        if case .action(let result, _) = self { return result }
        return nil
    }

    /// Builds an error response with typed metadata when the error belongs to TheFence.
    public static func failure(_ error: Error) -> FenceResponse {
        if let fenceError = error as? FenceError {
            return .error(fenceError.coreMessage, details: fenceError.failureDetails)
        }
        return .error(error.displayMessage)
    }

    /// Whether callers should treat this response as a failed command.
    public var isFailure: Bool {
        switch self {
        case .error:
            return true
        case .action(let result, let expectation):
            return !result.success || expectation?.met == false
        case .batch(let outcomes, _, _):
            return outcomes.stoppedFailedIndex != nil
        case .heistPlayback(_, let failedIndex, _, _, _):
            return failedIndex != nil
        default:
            return false
        }
    }

    static func actionFailureDetails(_ result: ActionResult) -> FailureDetails? {
        guard !result.success,
              result.errorKind == nil || result.errorKind == .actionFailed,
              result.message == Self.accessibilityTreeUnavailableMessage
        else {
            return nil
        }

        return FailureDetails(
            errorCode: "request.accessibility_tree_unavailable",
            phase: .request,
            retryable: true,
            hint: "Wait for a traversable app window, then refresh the interface or retry the command."
        )
    }

    // Keep this literal in sync with `TheBrains.treeUnavailableMessage`; this
    // bridges tree-unavailable `actionFailed` wire results to local diagnostics.
    private static let accessibilityTreeUnavailableMessage =
        "Could not access accessibility tree: no traversable app windows"

    // MARK: - Human Formatting

    public func humanFormatted() -> String {
        switch self {
        case .ok(let message):
            return message
        case .error(let message, _):
            return "Error: \(message)"
        case .help(let commands):
            return "Commands:\n" + commands.map { "  \($0)" }.joined(separator: "\n")
        case .status(let connected, let deviceName):
            if connected, let name = deviceName {
                return "Connected to \(name)"
            }
            return "Not connected"
        case .devices(let devices):
            return formatDeviceList(devices)
        case .interface(let interface, _):
            return formatInterface(interface)
        case .action(let result, let expectation):
            var text = formatActionResult(result)
            if let expectation {
                if expectation.met {
                    text += "  [expectation met]"
                } else {
                    let tier = expectation.expectation.map(String.init(describing:)) ?? "delivery"
                    text += "  [expectation FAILED: expected \(tier), got \(expectation.actual ?? "nil")]"
                }
            }
            return text
        case .screenshot(let path, let payload):
            return "✓ Screenshot saved: \(path)  (\(Int(payload.width)) × \(Int(payload.height)))"
        case .screenshotData(let payload):
            return "✓ Screenshot captured (\(Int(payload.width)) × \(Int(payload.height))) — base64 PNG follows\n\(payload.pngData)"
        case .recording(let path, let payload):
            return formatRecordingHuman(path: path, payload: payload)
        case .recordingData(let payload):
            return formatRecordingDataHuman(payload)
        case .batch(let outcomes, let totalTimingMs, _):
            let completedSteps = outcomes.completedStepCount
            let failedIndex = outcomes.stoppedFailedIndex
            let checked = outcomes.expectationsChecked
            let met = outcomes.expectationsMet
            var text = "Batch: \(completedSteps) step(s) completed in \(totalTimingMs)ms"
            if let idx = failedIndex { text += " (failed at step \(idx))" }
            if checked > 0 { text += " [expectations: \(met)/\(checked) met]" }
            return text
        case .sessionState(let payload):
            return Self.formatSessionStateHuman(payload)
        case .targets(let targets, let defaultTarget):
            return formatTargetList(targets, defaultTarget: defaultTarget)
        case .sessionLog(let snapshot):
            return formatSessionLogHuman(snapshot)
        case .archiveResult(let path, let snapshot):
            return formatArchiveResultHuman(path: path, snapshot: snapshot)
        case .heistStarted:
            return "Heist recording started"
        case .heistStopped(let path, let stepCount):
            return "Heist saved: \(path) (\(stepCount) steps)"
        case .heistPlayback(let completedSteps, let failedIndex, let totalTimingMs, let failure, _):
            var text = "Playback: \(completedSteps) step(s) completed in \(totalTimingMs)ms"
            if let index = failedIndex { text += " (failed at step \(index))" }
            if let failure {
                text += "\n  command: \(failure.step.command)"
                if let target = failure.step.target {
                    text += "\n  target: \(target)"
                }
                text += "\n  error: \(failure.errorMessage)"
            }
            return text
        }
    }

    private static func formatSessionStateHuman(_ payload: SessionStatePayload) -> String {
        let device = payload.device?.deviceName ?? "unknown"
        switch payload.phase {
        case .connected:
            return "Session: connected to \(device)"
        case .connecting:
            return "Session: connecting"
        case .failed:
            if let failure = sessionStateFailureSummary(payload.lastFailure) {
                return "Session: failed (\(failure))"
            }
            return "Session: failed"
        case .disconnected:
            if let failure = sessionStateFailureSummary(payload.lastFailure) {
                return "Session: disconnected (\(failure))"
            }
            return "Session: not connected"
        }
    }

    private static func sessionStateFailureSummary(_ failure: SessionFailurePayload?) -> String? {
        guard let failure else { return nil }
        if let hint = failure.hint {
            return "\(failure.errorCode): \(hint)"
        }
        if let message = failure.message {
            return "\(failure.errorCode): \(message)"
        }
        return failure.errorCode
    }

    private func formatSessionLogHuman(_ snapshot: SessionLogSnapshot) -> String {
        let manifest = snapshot.manifest
        let counts = snapshot.counts
        let artifacts = snapshot.artifacts
        let formatter = ISO8601DateFormatter()
        var text = "Session: \(manifest.sessionId)\n"
        text += "  Started: \(formatter.string(from: manifest.startTime))\n"
        if let endTime = manifest.endTime {
            text += "  Ended: \(formatter.string(from: endTime))\n"
        }
        text += "  Commands: \(counts.commandCount)"
        if counts.errorCount > 0 {
            text += " (\(counts.errorCount) errors)"
        }
        text += "\n  Artifacts: \(artifacts.count)"
        let screenshots = artifacts.count(where: { $0.type == .screenshot })
        let recordings = artifacts.count(where: { $0.type == .recording })
        if screenshots > 0 && recordings > 0 {
            text += " (\(screenshots) screenshots, \(recordings) recordings)"
        } else if screenshots > 0 {
            text += " (\(screenshots) screenshots)"
        } else if recordings > 0 {
            text += " (\(recordings) recordings)"
        }
        if snapshot.projectionStatus.isDegraded {
            text += "\n  Projection: degraded"
            text += " (\(projectionStatusSummary(snapshot.projectionStatus)))"
        }
        return text
    }

    private func formatArchiveResultHuman(path: String, snapshot: SessionLogSnapshot) -> String {
        var text = "Session archived: \(path) (\(snapshot.artifacts.count) artifacts, "
        text += "\(snapshot.counts.commandCount) commands)"
        if snapshot.projectionStatus.isDegraded {
            text += "\n  Projection: degraded"
            text += " (\(projectionStatusSummary(snapshot.projectionStatus)))"
        }
        return text
    }

    private func projectionStatusSummary(_ status: SessionLogProjectionStatus) -> String {
        var details: [String] = []
        if status.malformedLineCount > 0 {
            details.append("\(status.malformedLineCount) malformed log line(s)")
        }
        if status.malformedArtifactCount > 0 {
            details.append("\(status.malformedArtifactCount) malformed artifact entry/entries")
        }
        if let lineNumber = status.firstMalformedLineNumber {
            details.append("first malformed line \(lineNumber)")
        }
        if let cause = status.firstMalformedLineCause {
            details.append(cause)
        }
        return details.joined(separator: ", ")
    }

    private func formatTargetList(_ targets: [String: TargetConfig], defaultTarget: String?) -> String {
        if targets.isEmpty { return "No targets configured" }
        var output = "\(targets.count) target(s):\n"
        for name in targets.keys.sorted() {
            guard let target = targets[name] else { continue }
            let isDefault = name == defaultTarget ? " (default)" : ""
            output += "  \(name): \(target.device)\(isDefault)\n"
        }
        return output.trimmingCharacters(in: .newlines)
    }

    private func formatDeviceList(_ devices: [DiscoveredDevice]) -> String {
        if devices.isEmpty { return "No devices found" }
        var output = "\(devices.count) device(s):\n"
        for (index, device) in devices.enumerated() {
            let id = device.shortId ?? "----"
            let typeLabel = switch device.connectionType {
            case .simulator: "sim"
            case .usb: "usb"
            case .network: "network"
            }
            output += "  [\(index)] \(id)  \(device.appName)  (\(device.deviceName))  [\(typeLabel)]\n"
        }
        return output.trimmingCharacters(in: .newlines)
    }

    private func formatRecordingHuman(path: String, payload: RecordingPayload) -> String {
        let duration = String(format: "%.1f", payload.duration)
        var text = "✓ Recording saved: \(path)  " +
            "(\(payload.width)×\(payload.height), \(duration)s, " +
            "\(payload.frameCount) frames, \(payload.stopReason.rawValue))"
        if let log = payload.interactionLog {
            text += "\n  Interactions: \(log.count)"
        }
        return text
    }

    private func formatRecordingDataHuman(_ payload: RecordingPayload) -> String {
        let sizeKB = payload.videoData.count * 3 / 4 / 1024
        let duration = String(format: "%.1f", payload.duration)
        var text = "✓ Recording captured " +
            "(\(payload.width)×\(payload.height), \(duration)s, " +
            "\(payload.frameCount) frames, ~\(sizeKB)KB, \(payload.stopReason.rawValue))"
        if let log = payload.interactionLog {
            text += "\n  Interactions: \(log.count)"
        }
        return text
    }

    // MARK: - Human Format Helpers

    private func formatInterface(_ interface: Interface) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium

        var output = "\(interface.elements.count) elements (\(formatter.string(from: interface.timestamp)))\n"
        output += String(repeating: "-", count: 60) + "\n"

        if interface.elements.isEmpty {
            output += "  (no elements)\n"
        } else {
            for (i, element) in interface.elements.enumerated() {
                output += formatElement(element, displayIndex: i)
            }
        }
        output += String(repeating: "-", count: 60)
        return output
    }

    private func formatElement(_ element: HeistElement, displayIndex: Int) -> String {
        var output = ""
        let index = String(format: "  [%2d]", displayIndex)
        let label = element.label ?? element.description
        output += "\(index) \(label)\n"

        if let value = element.value, !value.isEmpty {
            output += "       Value: \(value)\n"
        }
        if let identifier = element.identifier, !identifier.isEmpty {
            output += "       ID: \(identifier)\n"
        }
        if !element.actions.isEmpty {
            output += "       Actions: \(element.actions.map(\.description).joined(separator: ", "))\n"
        }
        if let rotors = element.rotors, !rotors.isEmpty {
            output += "       Rotors: \(rotors.map(\.name).joined(separator: ", "))\n"
        }
        output += "       Frame: (\(Int(element.frameX)), \(Int(element.frameY))) \(Int(element.frameWidth))×\(Int(element.frameHeight))\n"
        return output
    }

    private func formatActionResult(_ result: ActionResult) -> String {
        if result.success {
            var output = "✓ \(result.method.rawValue)"
            if case .value(let value) = result.payload {
                output += "  value: \"\(value)\""
            }
            if case .rotor(let search) = result.payload {
                output += "  rotor: \"\(search.rotor)\" \(search.direction.rawValue)"
                if let foundElement = search.foundElement {
                    output += " → \(foundElement.heistId)"
                }
                if let textRange = search.textRange {
                    output += "  range: \(textRange.rangeDescription)"
                    if let text = textRange.text {
                        output += " \"\(text)\""
                    }
                }
            }
            if let delta = result.accessibilityDelta {
                output += "  \(formatDelta(delta))"
            }
            if result.animating == true {
                output += "  (still animating)"
            }
            return output
        }
        return "Error: \(result.message ?? result.method.rawValue)"
    }

    /// Actions that aren't implied by the element's traits.
    /// `activate` is implied by `.button`; `increment`/`decrement` by `.adjustable`.
    static func meaningfulActions(_ element: HeistElement) -> [ElementAction] {
        element.actions.filter { action in
            switch action {
            case .activate: return !element.traits.contains(.button)
            case .increment, .decrement: return !element.traits.contains(.adjustable)
            case .custom: return true
            }
        }
    }

    private func formatDelta(_ delta: AccessibilityTrace.Delta) -> String {
        switch delta {
        case .noChange(let payload):
            return "[\(payload.elementCount) elements, no change]"
        case .elementsChanged(let payload):
            let edits = payload.edits
            var parts: [String] = ["\(payload.elementCount) elements"]
            if !edits.added.isEmpty { parts.append("+\(edits.added.count) added") }
            if !edits.removed.isEmpty { parts.append("-\(edits.removed.count) removed") }
            if !edits.updated.isEmpty { parts.append("~\(edits.updated.count) updated") }
            if !edits.treeInserted.isEmpty { parts.append("+\(edits.treeInserted.count) tree inserted") }
            if !edits.treeRemoved.isEmpty { parts.append("-\(edits.treeRemoved.count) tree removed") }
            if !edits.treeMoved.isEmpty { parts.append("↕\(edits.treeMoved.count) moved") }
            return "[" + parts.joined(separator: ", ") + "]"
        case .screenChanged(let payload):
            return "[\(payload.elementCount) elements, screen changed]"
        }
    }
}
