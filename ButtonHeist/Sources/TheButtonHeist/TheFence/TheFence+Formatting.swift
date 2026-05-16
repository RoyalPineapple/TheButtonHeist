import Foundation

import TheScore

/// Level of detail for interface responses.
public enum InterfaceDetail: String, CaseIterable, Sendable {
    case summary
    case full
}

/// Discovery scope for get_interface.
public enum GetInterfaceScope: String, CaseIterable, Sendable {
    case full
    case visible
}

/// Summary of a single step within a batch execution.
///
/// Consumed by batch formatters to build per-step human/JSON rows. `deltaKind`
/// is the wire-level `kind` discriminator from the step's `InterfaceDelta`;
/// `expectationMet` is nil when the step had no expectation attached.
public struct BatchStepSummary: Sendable {
    public let command: String
    public let deltaKind: String?
    public let screenName: String?
    public let screenId: String?
    public let expectationMet: Bool?
    public let elementCount: Int?
    public let error: String?
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
    case interface(Interface, detail: InterfaceDetail = .summary, filteredFrom: Int? = nil, explore: ExploreResult? = nil)
    case action(result: ActionResult, expectation: ExpectationResult? = nil)
    /// Screenshot written to disk. `path` is the resolved filesystem location.
    case screenshot(path: String, width: Double, height: Double)
    /// Screenshot held in memory as base64 PNG. Returned when no session is
    /// active and no explicit output path was requested.
    case screenshotData(pngData: String, width: Double, height: Double)
    /// Recording written to disk. `path` is the resolved filesystem location.
    case recording(path: String, payload: RecordingPayload)
    /// Recording held in memory. Returned when no session is active and no
    /// explicit output path was requested.
    case recordingData(payload: RecordingPayload)
    case batch(
        results: [[String: Any]], completedSteps: Int, failedIndex: Int?,
        totalTimingMs: Int, expectationsChecked: Int = 0, expectationsMet: Int = 0,
        stepSummaries: [BatchStepSummary] = [], netDelta: InterfaceDelta? = nil
    )
    case sessionState(payload: [String: Any])
    case targets([String: TargetConfig], defaultTarget: String?)
    case sessionLog(manifest: SessionManifest)
    case archiveResult(path: String, manifest: SessionManifest)
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
        case .batch(_, _, let failedIndex, _, _, _, _, _):
            return failedIndex != nil
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
        case .interface(let interface, _, _, _):
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
        case .screenshot(let path, let width, let height):
            return "✓ Screenshot saved: \(path)  (\(Int(width)) × \(Int(height)))"
        case .screenshotData(let pngData, let width, let height):
            return "✓ Screenshot captured (\(Int(width)) × \(Int(height))) — base64 PNG follows\n\(pngData)"
        case .recording(let path, let payload):
            return formatRecordingHuman(path: path, payload: payload)
        case .recordingData(let payload):
            return formatRecordingDataHuman(payload)
        case .batch(_, let completedSteps, let failedIndex, let totalTimingMs, let checked, let met, _, _):
            var text = "Batch: \(completedSteps) step(s) completed in \(totalTimingMs)ms"
            if let idx = failedIndex { text += " (failed at step \(idx))" }
            if checked > 0 { text += " [expectations: \(met)/\(checked) met]" }
            return text
        case .sessionState(let payload):
            return Self.formatSessionStateHuman(payload)
        case .targets(let targets, let defaultTarget):
            return formatTargetList(targets, defaultTarget: defaultTarget)
        case .sessionLog(let manifest):
            return formatSessionLogHuman(manifest)
        case .archiveResult(let path, let manifest):
            return "Session archived: \(path) (\(manifest.artifacts.count) artifacts, \(manifest.commandCount) commands)"
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

    private static func formatSessionStateHuman(_ payload: [String: Any]) -> String {
        let phase = payload["phase"] as? String
        let connected = payload["connected"] as? Bool ?? false
        let device = payload["deviceName"] as? String ?? "unknown"
        switch phase {
        case "connected":
            return "Session: connected to \(device)"
        case "connecting":
            return "Session: connecting"
        case "failed":
            if let failure = sessionStateFailureSummary(payload) {
                return "Session: failed (\(failure))"
            }
            return "Session: failed"
        case "disconnected":
            if let failure = sessionStateFailureSummary(payload) {
                return "Session: disconnected (\(failure))"
            }
            return "Session: not connected"
        default:
            return connected ? "Session: connected to \(device)" : "Session: not connected"
        }
    }

    private static func sessionStateFailureSummary(_ payload: [String: Any]) -> String? {
        guard let failure = payload["lastFailure"] as? [String: Any] else {
            return nil
        }
        let code = failure["errorCode"] as? String
        let hint = failure["hint"] as? String
        let message = failure["message"] as? String
        switch (code, hint, message) {
        case let (code?, hint?, _):
            return "\(code): \(hint)"
        case let (code?, nil, message?):
            return "\(code): \(message)"
        case let (code?, nil, nil):
            return code
        case let (nil, hint?, _):
            return hint
        case let (nil, nil, message?):
            return message
        case (nil, nil, nil):
            return nil
        }
    }

    private func formatSessionLogHuman(_ manifest: SessionManifest) -> String {
        let formatter = ISO8601DateFormatter()
        var text = "Session: \(manifest.sessionId)\n"
        text += "  Started: \(formatter.string(from: manifest.startTime))\n"
        if let endTime = manifest.endTime {
            text += "  Ended: \(formatter.string(from: endTime))\n"
        }
        text += "  Commands: \(manifest.commandCount)"
        if manifest.errorCount > 0 {
            text += " (\(manifest.errorCount) errors)"
        }
        text += "\n  Artifacts: \(manifest.artifacts.count)"
        let screenshots = manifest.artifacts.count(where: { $0.type == .screenshot })
        let recordings = manifest.artifacts.count(where: { $0.type == .recording })
        if screenshots > 0 && recordings > 0 {
            text += " (\(screenshots) screenshots, \(recordings) recordings)"
        } else if screenshots > 0 {
            text += " (\(screenshots) screenshots)"
        } else if recordings > 0 {
            text += " (\(recordings) recordings)"
        }
        return text
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
            if let delta = result.interfaceDelta {
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

    private func formatDelta(_ delta: InterfaceDelta) -> String {
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
