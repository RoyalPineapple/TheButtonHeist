import Foundation

import TheScore

extension FenceResponse {

    // MARK: - Compact Text Format

    /// Token-efficient output for LLM agents. One line per element, no geometry.
    public func compactFormatted() -> String {
        switch self {
        case .ok(let message):
            return message
        case .error(let message):
            return "error: \(message)"
        case .help(let commands):
            return commands.joined(separator: ", ")
        case .status(let connected, let deviceName):
            if connected, let name = deviceName { return "connected: \(name)" }
            return "not connected"
        case .devices(let devices):
            if devices.isEmpty { return "no devices" }
            return devices.map { "\($0.appName) (\($0.deviceName)) [\($0.connectionType.rawValue)]" }
                .joined(separator: "\n")
        case .interface(let interface, _, let filteredFrom, _):
            var header = "\(interface.elements.count) elements"
            if let filteredFrom { header += " (filtered from \(filteredFrom))" }
            var lines: [String] = [interface.screenDescription, header]
            for (i, element) in interface.elements.enumerated() {
                lines.append(Self.compactElementLine(element, displayIndex: i))
            }
            return lines.joined(separator: "\n")
        case .action(let result, let expectation):
            return compactActionResult(result, expectation: expectation)
        case .screenshot(let path, let width, let height):
            return "screenshot: \(path) (\(Int(width))x\(Int(height)))"
        case .screenshotData(_, let width, let height):
            return "screenshot: \(Int(width))x\(Int(height))"
        case .recording(let path, let payload):
            return "recording: \(path) (\(String(format: "%.1f", payload.duration))s, \(payload.frameCount) frames)"
        case .recordingData(let payload):
            return "recording: \(String(format: "%.1f", payload.duration))s, \(payload.frameCount) frames"
        case .batch(_, let completedSteps, let failedIndex, let totalTimingMs, let checked, let met, let stepSummaries, let netDelta):
            return compactBatchFormatted(
                completedSteps: completedSteps, failedIndex: failedIndex,
                totalTimingMs: totalTimingMs, checked: checked, met: met,
                stepSummaries: stepSummaries, netDelta: netDelta
            )
        case .sessionState(let payload):
            let connected = payload["connected"] as? Bool ?? false
            return connected ? "session: connected" : "session: not connected"
        case .targets(let targets, let defaultTarget):
            if targets.isEmpty { return "no targets configured" }
            return targets.sorted(by: { $0.key < $1.key }).map { name, target in
                let isDefault = name == defaultTarget ? " *" : ""
                return "\(name): \(target.device)\(isDefault)"
            }.joined(separator: "\n")
        case .sessionLog, .archiveResult, .heistStarted, .heistStopped, .heistPlayback:
            return compactBookKeeper(self)
        }
    }

    private func compactBookKeeper(_ response: FenceResponse) -> String {
        switch response {
        case .sessionLog(let manifest):
            var text = "session: \(manifest.sessionId), \(manifest.commandCount) commands, \(manifest.artifacts.count) artifacts"
            if manifest.errorCount > 0 { text += ", \(manifest.errorCount) errors" }
            return text
        case .archiveResult(let path, let manifest):
            return "archived: \(path) (\(manifest.artifacts.count) artifacts, \(manifest.commandCount) commands)"
        case .heistStarted:
            return "heist recording started"
        case .heistStopped(let path, let stepCount):
            return "saved: \(path) (\(stepCount) steps)"
        case .heistPlayback(let completedSteps, let failedIndex, let totalTimingMs, let failure):
            var text = "playback: \(completedSteps) steps in \(totalTimingMs)ms"
            if let index = failedIndex { text += " (failed at \(index))" }
            if let failure { text += " [\(failure.step.command): \(failure.errorMessage)]" }
            return text
        default:
            return ""
        }
    }

    private func compactActionResult(_ result: ActionResult, expectation: ExpectationResult?) -> String {
        guard result.success else {
            if let search = result.scrollSearchResult {
                return Self.compactScrollSearchNotFound(search, screenId: result.screenId)
            }
            return "error: \(result.message ?? result.method.rawValue)"
        }

        var text: String
        if let search = result.scrollSearchResult {
            text = Self.compactScrollSearchFound(search)
        } else if let delta = result.interfaceDelta {
            text = Self.compactDelta(delta, method: result.method.rawValue)
        } else {
            text = "\(result.method.rawValue): ok"
        }
        if let screenId = result.screenId {
            text = "\(screenId) | \(text)"
        }
        if let value = result.value {
            text += "\nvalue: \"\(value)\""
        }
        if let expectation {
            if !expectation.met {
                text += "\n[expectation FAILED: got \(expectation.actual ?? "nil")]"
            }
        }
        return text
    }

    private static func compactScrollSearchFound(_ search: ScrollSearchResult) -> String {
        var header: String
        if search.scrollCount == 0 {
            header = "scroll_to_visible: already visible"
        } else {
            let itemInfo = scrollSearchItemInfo(search)
            header = "scroll_to_visible: found after \(search.scrollCount) scrolls\(itemInfo)"
        }
        if let element = search.foundElement {
            header += "\n  \(compactElementLine(element))"
        }
        return header
    }

    private static func compactScrollSearchNotFound(_ search: ScrollSearchResult, screenId: String?) -> String {
        var text: String
        if search.exhaustive {
            let itemInfo = scrollSearchItemInfo(search)
            text = "scroll_to_visible: not found\(itemInfo) (exhaustive)"
        } else if search.scrollCount > 0 {
            let itemInfo = scrollSearchItemInfo(search)
            text = "scroll_to_visible: not found after \(search.scrollCount) scrolls\(itemInfo)"
        } else {
            text = "scroll_to_visible: not found"
        }
        if let screenId {
            text = "\(screenId) | \(text)"
        }
        return text
    }

    private static func scrollSearchItemInfo(_ search: ScrollSearchResult) -> String {
        if let total = search.totalItems {
            let pct = total > 0 ? Int(Double(search.uniqueElementsSeen) / Double(total) * 100) : 0
            return " (\(search.uniqueElementsSeen)/\(total) items seen, \(pct)%)"
        } else if search.uniqueElementsSeen > 0 {
            return " (\(search.uniqueElementsSeen) unique elements seen)"
        }
        return ""
    }

    private func compactBatchFormatted(
        completedSteps: Int, failedIndex: Int?, totalTimingMs: Int,
        checked: Int, met: Int, stepSummaries: [BatchStepSummary],
        netDelta: InterfaceDelta?
    ) -> String {
        var text = "batch: \(completedSteps) steps in \(totalTimingMs)ms"
        if let idx = failedIndex { text += " (failed at \(idx))" }
        if checked > 0 { text += " [expectations: \(met)/\(checked)]" }
        if let lastScreenId = stepSummaries.last(where: { $0.screenId != nil })?.screenId {
            text = "\(lastScreenId) | \(text)"
        }
        for (index, step) in stepSummaries.enumerated() {
            var line = "  [\(index)] \(step.command)"
            if let error = step.error {
                line += " → error: \(error)"
            } else if let kind = step.deltaKind {
                line += " → \(kind)"
            } else if let count = step.elementCount {
                line += " → \(count) elements"
            }
            if let met = step.expectationMet {
                line += met ? " ✓" : " ✗"
            }
            text += "\n\(line)"
        }
        if let netDelta {
            text += "\n" + Self.compactDelta(netDelta, method: "net")
        }
        return text
    }

    /// Compact one-line-per-element format for LLM agents.
    /// Geometry is omitted by default — agents can request it via `get_interface --detail full`.
    public static func compactElementLine(_ element: HeistElement, displayIndex: Int? = nil) -> String {
        var parts: [String] = []
        if let displayIndex { parts.append("[\(displayIndex)]") }
        parts.append(element.heistId)

        if let label = element.label {
            parts.append("\"\(label)\"")
        }
        if let value = element.value, !value.isEmpty {
            parts.append("= \"\(value)\"")
        }

        let meaningful = element.traits.filter { $0 != .staticText }
        if !meaningful.isEmpty {
            parts.append("[\(meaningful.map(\.rawValue).joined(separator: ", "))]")
        }

        let actions = meaningfulActions(element)
        if !actions.isEmpty {
            parts.append("{\(actions.map(\.description).joined(separator: ", "))}")
        }

        return parts.joined(separator: " ")
    }

    public static func compactInterface(_ interface: Interface) -> String {
        var lines: [String] = ["\(interface.elements.count) elements"]
        for (i, element) in interface.elements.enumerated() {
            lines.append(compactElementLine(element, displayIndex: i))
        }
        return lines.joined(separator: "\n")
    }

    public static func compactDelta(_ delta: InterfaceDelta, method: String) -> String {
        switch delta.kind {
        case .noChange:
            return "\(method): no change"

        case .elementsChanged:
            var lines: [String] = ["\(method): elements changed (\(delta.elementCount) elements)"]
            if let added = delta.added, !added.isEmpty {
                for el in added {
                    lines.append("  + \(compactElementLine(el))")
                }
            }
            if let removed = delta.removed, !removed.isEmpty {
                for id in removed {
                    lines.append("  - \(id)")
                }
            }
            if let updates = delta.updated, !updates.isEmpty {
                // Omit geometry changes (frame/activationPoint) — layout shifts are structural noise
                for update in updates {
                    let meaningful = update.changes.filter { !$0.property.isGeometry }
                    for change in meaningful {
                        lines.append("  ~ \(update.heistId): \(change.property.rawValue) \"\(change.old ?? "nil")\" → \"\(change.new ?? "nil")\"")
                    }
                }
            }
            return lines.joined(separator: "\n")

        case .screenChanged:
            var lines: [String] = ["\(method): screen changed"]
            if let newInterface = delta.newInterface {
                lines.append(compactInterface(newInterface))
            }
            return lines.joined(separator: "\n")
        }
    }

}
