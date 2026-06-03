import Foundation

import TheScore

extension FenceResponse {

    // MARK: - Human Formatting

    public func humanFormatted() -> String {
        switch self {
        case .ok(let message):
            return message
        case .error(let message, _):
            return "Error: \(message)"
        case .status(let connected, let deviceName):
            if connected, let name = deviceName {
                return "Connected to \(name)"
            }
            return "Not connected"
        case .pong(let payload):
            return Self.formatPongHuman(payload)
        case .devices(let devices):
            return formatDeviceList(devices)
        case .interface(let interface, _):
            return formatInterface(interface)
        case .action(let command, let result, let expectation):
            var text = formatActionResult(command: command, result)
            if let expectation {
                if expectation.met {
                    text += "  [expectation met]"
                } else {
                    let tier = expectation.predicate.map(String.init(describing:)) ?? "delivery"
                    text += "  [expectation FAILED: expected \(tier), got \(expectation.actual ?? "nil")]"
                }
            }
            return text
        case .screenshot(let path, let payload, _):
            return "✓ Screenshot saved: \(path)  (\(Int(payload.width)) × \(Int(payload.height)))"
        case .screenshotData(let payload, _):
            return "✓ Screenshot captured (\(Int(payload.width)) × \(Int(payload.height))) — base64 PNG follows\n\(payload.pngData)"
        case .heistExecution(let plan, let result, _):
            let projection = HeistReportProjection(plan: plan, result: result)
            let completedSteps = result.completedStepCount
            let failedIndex = result.stoppedFailedIndex
            let checked = projection.summary.expectationsChecked
            let met = projection.summary.expectationsMet
            var text = "Heist: \(completedSteps) step(s) completed in \(result.totalTimingMs)ms"
            if let idx = failedIndex { text += " (failed at step \(idx))" }
            if checked > 0 { text += " [expectations: \(met)/\(checked) met]" }
            return text
        case .sessionState(let payload):
            return Self.formatSessionStateHuman(payload)
        case .targets(let targets, let defaultTarget):
            return formatTargetList(targets, defaultTarget: defaultTarget)
        case .heistStarted:
            return "Heist recording started"
        case .heistStopped(let path, let stepCount):
            return "Heist saved: \(path) (\(stepCount) steps)"
        case .heistPlayback(let completedSteps, let failedIndex, let totalTimingMs, let failure, _):
            var text = "Playback: \(completedSteps) step(s) completed in \(totalTimingMs)ms"
            if let index = failedIndex { text += " (failed at step \(index))" }
            if let failure {
                text += "\n  command: \(failure.step.commandName)"
                if let target = failure.step.target {
                    text += "\n  target: \(target)"
                }
                text += "\n  error: \(failure.errorMessage)"
                if let diagnosticCaptureFailure = failure.diagnosticCaptureFailure {
                    text += "\n  diagnosticCaptureFailure: \(diagnosticCaptureFailure)"
                }
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

    private static func formatPongHuman(_ payload: PongPayload) -> String {
        var parts = [
            payload.appName.isEmpty ? "App" : payload.appName,
            "bundle: \(payload.bundleIdentifier.isEmpty ? "unknown" : payload.bundleIdentifier)",
            "ButtonHeist: \(payload.buttonHeistVersion)",
        ]
        if let version = payload.appVersion, !version.isEmpty {
            parts.append("version: \(version)")
        }
        if let build = payload.appBuild, !build.isEmpty {
            parts.append("build: \(build)")
        }
        if let identifier = payload.serverInstanceIdentifier, !identifier.isEmpty {
            parts.append("server: \(identifier)")
        }
        if let timestamp = payload.serverTimestampMs {
            parts.append("serverTimestampMs: \(timestamp)")
        }
        return "Pong: " + parts.joined(separator: ", ")
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
            let name = device.deviceName.isEmpty ? device.appName : "\(device.appName)  (\(device.deviceName))"
            output += "  [\(index)] \(id)  \(name)  [\(typeLabel)]\n"
        }
        return output.trimmingCharacters(in: .newlines)
    }

    // MARK: - Human Format Helpers

    private func formatInterface(_ interface: Interface) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium

        var output = "\(interface.projectedElements.count) elements (\(formatter.string(from: interface.timestamp)))\n"
        output += String(repeating: "-", count: 60) + "\n"

        if interface.projectedElements.isEmpty {
            output += "  (no elements)\n"
        } else {
            for (i, element) in interface.projectedElements.enumerated() {
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
            output += "       Rotors: \(rotors.map { $0.name }.joined(separator: ", "))\n"
        }
        output += "       Frame: (\(Int(element.frameX)), \(Int(element.frameY))) \(Int(element.frameWidth))×\(Int(element.frameHeight))\n"
        return output
    }

    private func formatActionResult(command: TheFence.Command, _ result: ActionResult) -> String {
        let methodName = command.rawValue
        if result.success {
            var output = "✓ \(methodName)"
            if case .value(let value) = result.payload {
                output += "  value: \"\(value)\""
            }
            if case .rotor(let search) = result.payload {
                output += "  rotor: \"\(search.rotor)\" \(search.direction.rawValue)"
                if let foundElement = search.foundElement {
                    output += " → \(foundElement.label ?? foundElement.description)"
                }
                if let textRange = search.textRange {
                    output += "  range: \(textRange.rangeDescription)"
                    if let text = textRange.text {
                        output += " \"\(text)\""
                    }
                }
            }
            if let delta = result.accessibilityTrace?.endpointDeltaProjection {
                output += "  \(formatDelta(delta))"
            }
            return output
        }
        return "Error: \(result.message ?? methodName)"
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
            return "[" + parts.joined(separator: ", ") + "]"
        case .screenChanged(let payload):
            return "[\(payload.elementCount) elements, screen changed]"
        }
    }
}
