import Foundation

import TheScore

/// Level of detail for interface responses.
public enum InterfaceDetail: String, CaseIterable, Sendable {
    case summary
    case full
}

/// Summary of a single step within a batch execution.
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
public enum FenceResponse {
    case ok(message: String)
    case error(String)
    case help(commands: [String])
    case status(connected: Bool, deviceName: String?)
    case devices([DiscoveredDevice])
    case interface(Interface, detail: InterfaceDetail = .summary, filteredFrom: Int? = nil, explore: ExploreResult? = nil)
    case action(result: ActionResult, expectation: ExpectationResult? = nil)
    case screenshot(path: String, width: Double, height: Double)
    case screenshotData(pngData: String, width: Double, height: Double)
    case recording(path: String, payload: RecordingPayload)
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
    case heistPlayback(completedSteps: Int, failedIndex: Int?, totalTimingMs: Int, failure: PlaybackFailure? = nil)

    /// Extract the ActionResult if this response wraps one (for expectation checking).
    public var actionResult: ActionResult? {
        if case .action(let result, _) = self { return result }
        return nil
    }

    // MARK: - Human Formatting

    public func humanFormatted() -> String {
        switch self {
        case .ok(let message):
            return message
        case .error(let message):
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
            let connected = payload["connected"] as? Bool ?? false
            let device = payload["deviceName"] as? String ?? "unknown"
            return connected ? "Session: connected to \(device)" : "Session: not connected"
        case .targets(let targets, let defaultTarget):
            return formatTargetList(targets, defaultTarget: defaultTarget)
        case .sessionLog, .archiveResult, .heistStarted, .heistStopped, .heistPlayback:
            return formatBookKeeperHuman(self)
        }
    }

    private func formatBookKeeperHuman(_ response: FenceResponse) -> String {
        switch response {
        case .sessionLog(let manifest):
            return formatSessionLogHuman(manifest)
        case .archiveResult(let path, let manifest):
            return "Session archived: \(path) (\(manifest.artifacts.count) artifacts, \(manifest.commandCount) commands)"
        case .heistStarted:
            return "Heist recording started"
        case .heistStopped(let path, let stepCount):
            return "Heist saved: \(path) (\(stepCount) steps)"
        case .heistPlayback(let completedSteps, let failedIndex, let totalTimingMs, let failure):
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
        default:
            return ""
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
        output += "       Frame: (\(Int(element.frameX)), \(Int(element.frameY))) \(Int(element.frameWidth))×\(Int(element.frameHeight))\n"
        return output
    }

    private func formatActionResult(_ result: ActionResult) -> String {
        if result.success {
            var output = "✓ \(result.method.rawValue)"
            if let value = result.value {
                output += "  value: \"\(value)\""
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
        switch delta.kind {
        case .noChange:
            return "[\(delta.elementCount) elements, no change]"
        case .elementsChanged:
            let addedCount = delta.added?.count ?? 0
            let removedCount = delta.removed?.count ?? 0
            let updatedCount = delta.updated?.count ?? 0
            var parts: [String] = ["\(delta.elementCount) elements"]
            if addedCount > 0 { parts.append("+\(addedCount) added") }
            if removedCount > 0 { parts.append("-\(removedCount) removed") }
            if updatedCount > 0 { parts.append("~\(updatedCount) updated") }
            return "[" + parts.joined(separator: ", ") + "]"
        case .screenChanged:
            return "[\(delta.elementCount) elements, screen changed]"
        }
    }
}
