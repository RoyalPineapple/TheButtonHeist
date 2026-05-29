import Foundation

import TheScore

extension FenceResponse {

    // MARK: - Compact Text Format

    /// Token-efficient tree output for LLM agents. Omits geometry.
    public func compactFormatted() -> String {
        switch self {
        case .ok(let message):
            return message
        case .error(let message, let details):
            return Self.compactError(message, details: details)
        case .help(let commands):
            return commands.joined(separator: ", ")
        case .status(let connected, let deviceName):
            if connected, let name = deviceName { return "connected: \(name)" }
            return "not connected"
        case .pong(let payload):
            let name = payload.appName.isEmpty ? "App" : payload.appName
            let bundle = payload.bundleIdentifier.isEmpty ? "unknown" : payload.bundleIdentifier
            return "pong: \(name) \(bundle) [ButtonHeist \(payload.buttonHeistVersion)]"
        case .devices(let devices):
            if devices.isEmpty { return "no devices" }
            return devices.map {
                let name = $0.deviceName.isEmpty ? $0.appName : "\($0.appName) (\($0.deviceName))"
                return "\(name) [\($0.connectionType.rawValue)]"
            }
                .joined(separator: "\n")
        case .interface(let interface, let detail):
            let header = "\(interface.elements.count) elements"
            var lines: [String] = [interface.screenDescription, header]
            lines.append(contentsOf: Self.compactTreeLines(interface, detail: detail))
            return lines.joined(separator: "\n")
        case .action(let result, let expectation):
            return compactActionResult(result, expectation: expectation)
        case .screenshot(let path, let payload, _):
            return "screenshot: \(path) (\(Int(payload.width))x\(Int(payload.height)))"
        case .screenshotData(let payload, _):
            return "screenshot: \(Int(payload.width))x\(Int(payload.height))"
        case .recording(let path, let payload):
            return "recording: \(path) (\(String(format: "%.1f", payload.duration))s, \(payload.frameCount) frames)"
        case .recordingExpanded(let path, let payload, let options):
            var suffixes: [String] = []
            if options.inlineData { suffixes.append("inlineData") }
            if options.includeInteractionLog { suffixes.append("interactionLog") }
            let suffix = suffixes.isEmpty ? "" : ", \(suffixes.joined(separator: "+"))"
            return "recording: \(path) (\(String(format: "%.1f", payload.duration))s, \(payload.frameCount) frames\(suffix))"
        case .recordingData(let payload):
            return "recording: \(String(format: "%.1f", payload.duration))s, \(payload.frameCount) frames"
        case .batch(let outcomes, let totalTimingMs, let accessibilityTrace):
            return compactBatchFormatted(
                completedSteps: outcomes.completedStepCount,
                failedIndex: outcomes.stoppedFailedIndex,
                totalTimingMs: totalTimingMs,
                checked: outcomes.expectationsChecked,
                met: outcomes.expectationsMet,
                stepSummaries: outcomes.stepSummaries,
                netDelta: accessibilityTrace?.meaningfulEndpointDeltaProjection
            )
        case .sessionState(let payload):
            return Self.compactSessionState(payload)
        case .targets(let targets, let defaultTarget):
            if targets.isEmpty { return "no targets configured" }
            return targets.sorted(by: { $0.key < $1.key }).map { name, target in
                let isDefault = name == defaultTarget ? " *" : ""
                return "\(name): \(target.device)\(isDefault)"
            }.joined(separator: "\n")
        case .sessionLog(let snapshot):
            var text = "session: \(snapshot.manifest.sessionId), " +
                "\(snapshot.counts.commandCount) commands, \(snapshot.artifacts.count) artifacts"
            if snapshot.counts.errorCount > 0 { text += ", \(snapshot.counts.errorCount) errors" }
            return text
        case .archiveResult(let path, let snapshot):
            return "archived: \(path) (\(snapshot.artifacts.count) artifacts, \(snapshot.counts.commandCount) commands)"
        case .heistStarted:
            return "heist recording started"
        case .heistStopped(let path, let stepCount):
            return "saved: \(path) (\(stepCount) steps)"
        case .heistPlayback(let completedSteps, let failedIndex, let totalTimingMs, let failure, _):
            var text = "playback: \(completedSteps) steps in \(totalTimingMs)ms"
            if let index = failedIndex { text += " (failed at \(index))" }
            if let failure {
                text += " [\(failure.step.command): \(failure.errorMessage)]"
                if let diagnosticCaptureFailure = failure.diagnosticCaptureFailure {
                    text += " [diagnosticCaptureFailure: \(diagnosticCaptureFailure)]"
                }
            }
            return text
        }
    }

    private static func compactError(_ message: String, details: FailureDetails?) -> String {
        guard let details else {
            return "error: \(message)"
        }
        var text = "error[\(details.errorCode) \(details.phase.rawValue) retryable=\(details.retryable)]: \(message)"
        if let hint = details.hint {
            text += "\nhint: \(hint)"
        }
        return text
    }

}
