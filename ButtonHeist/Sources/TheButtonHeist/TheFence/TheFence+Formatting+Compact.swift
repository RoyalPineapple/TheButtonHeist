import Foundation

import TheScore

extension FenceResponse {

    // MARK: - Compact Text Format

    /// Token-efficient tree output for LLM agents. Omits geometry.
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
        case .interface(let interface, let detail, let filteredFrom, _):
            var header = "\(interface.elements.count) elements"
            if let filteredFrom { header += " (filtered from \(filteredFrom))" }
            var lines: [String] = [interface.screenDescription, header]
            lines.append(contentsOf: Self.compactTreeLines(interface, detail: detail))
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
        case .heistPlayback(let completedSteps, let failedIndex, let totalTimingMs, let failure, _):
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
            let percentage = total > 0 ? Int(Double(search.uniqueElementsSeen) / Double(total) * 100) : 0
            return " (\(search.uniqueElementsSeen)/\(total) items seen, \(percentage)%)"
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
        if let failedIndex { text += " (failed at \(failedIndex))" }
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

    /// Compact one-line element format for LLM agents. Geometry is omitted.
    public static func compactElementLine(
        _ element: HeistElement,
        displayIndex: Int? = nil,
        detail: InterfaceDetail = .summary
    ) -> String {
        var parts: [String] = []
        if let displayIndex { parts.append("[\(displayIndex)]") }
        parts.append(element.heistId)

        if let identifier = element.identifier, !identifier.isEmpty {
            parts.append("id=\"\(identifier)\"")
        }
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
        if let hint = element.hint, !hint.isEmpty {
            parts.append("hint=\"\(hint)\"")
        }
        if let customContent = element.customContent {
            let content = customContent.compactMap { item -> String? in
                switch (item.label.isEmpty, item.value.isEmpty) {
                case (false, false): return "\(item.label): \(item.value)"
                case (false, true): return item.label
                case (true, false): return item.value
                case (true, true): return nil
                }
            }
            if !content.isEmpty {
                parts.append("content=\"\(content.joined(separator: "; "))\"")
            }
        }
        if detail == .full {
            parts.append("frame=(\(Int(element.frameX)),\(Int(element.frameY)),\(Int(element.frameWidth)),\(Int(element.frameHeight)))")
            parts.append("activation=(\(Int(element.activationPointX)),\(Int(element.activationPointY)))")
        }

        return parts.joined(separator: " ")
    }

    public static func compactInterface(_ interface: Interface) -> String {
        var lines: [String] = ["\(interface.elements.count) elements"]
        lines.append(contentsOf: compactTreeLines(interface, detail: .summary))
        return lines.joined(separator: "\n")
    }

    private static func compactTreeLines(
        _ interface: Interface,
        detail: InterfaceDetail
    ) -> [String] {
        var displayIndex = 0
        return interface.tree.flatMap { node in
            compactTreeLines(node, detail: detail, depth: 0, indexCounter: &displayIndex)
        }
    }

    private static func compactTreeLines(
        _ node: InterfaceNode,
        detail: InterfaceDetail,
        depth: Int,
        indexCounter: inout Int
    ) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        switch node {
        case .element(let element):
            let line = "\(indent)\(compactElementLine(element, displayIndex: indexCounter, detail: detail))"
            indexCounter += 1
            return [line]
        case .container(let info, let children):
            let header = "\(indent)<\(compactContainerLine(info, detail: detail))>"
            let childLines = children.flatMap {
                compactTreeLines($0, detail: detail, depth: depth + 1, indexCounter: &indexCounter)
            }
            return [header] + childLines
        }
    }

    private static func compactContainerLine(_ info: ContainerInfo, detail: InterfaceDetail) -> String {
        var parts: [String]
        switch info.type {
        case .semanticGroup(let label, let value, let identifier):
            parts = ["semanticGroup"]
            if let identifier, !identifier.isEmpty { parts.append("id=\"\(identifier)\"") }
            if let label, !label.isEmpty { parts.append("\"\(label)\"") }
            if let value, !value.isEmpty { parts.append("= \"\(value)\"") }
        case .list:
            parts = ["list"]
        case .landmark:
            parts = ["landmark"]
        case .dataTable(let rowCount, let columnCount):
            parts = ["dataTable", "\(rowCount)x\(columnCount)"]
        case .tabBar:
            parts = ["tabBar"]
        case .scrollable(let contentWidth, let contentHeight):
            parts = ["scrollable", "= \"\(Int(contentWidth))x\(Int(contentHeight))\""]
        }
        if detail == .full {
            parts.append("frame=(\(Int(info.frameX)),\(Int(info.frameY)),\(Int(info.frameWidth)),\(Int(info.frameHeight)))")
        }
        return parts.joined(separator: " ")
    }

    public static func compactDelta(_ delta: InterfaceDelta, method: String) -> String {
        switch delta.kind {
        case .noChange:
            // Auto-settle can produce a .noChange delta carrying transient
            // and/or flicker classifications when an element appeared and
            // disappeared during settle but baseline and final are
            // otherwise identical (the canonical "brief loading spinner
            // after activate" case the feature targets, and the same
            // shape `computeBackgroundDelta` synthesizes for between-call
            // captures). Surface those entries instead of swallowing them.
            let transient = delta.transient ?? []
            let flicker = delta.flicker ?? []
            if transient.isEmpty && flicker.isEmpty {
                return "\(method): no change"
            }
            var lines: [String] = ["\(method): no net change (\(delta.elementCount) elements)"]
            for element in transient {
                lines.append("  +- \(compactElementLine(element))")
            }
            for element in flicker {
                lines.append("  -+ \(compactElementLine(element))")
            }
            return lines.joined(separator: "\n")

        case .elementsChanged:
            var lines: [String] = ["\(method): elements changed (\(delta.elementCount) elements)"]
            if let added = delta.added, !added.isEmpty {
                for element in added {
                    lines.append("  + \(compactElementLine(element))")
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
            if let inserted = delta.treeInserted, !inserted.isEmpty {
                for entry in inserted {
                    lines.append("  + tree \(Self.compactTreeLocation(entry.location))")
                }
            }
            if let removed = delta.treeRemoved, !removed.isEmpty {
                for entry in removed {
                    lines.append("  - tree \(entry.ref.id) at \(Self.compactTreeLocation(entry.location))")
                }
            }
            if let moved = delta.treeMoved, !moved.isEmpty {
                for entry in moved {
                    lines.append("  ↕ \(entry.ref.id): \(Self.compactTreeLocation(entry.from)) → \(Self.compactTreeLocation(entry.to))")
                }
            }
            if let transient = delta.transient, !transient.isEmpty {
                for element in transient {
                    lines.append("  +- \(compactElementLine(element))")
                }
            }
            if let flicker = delta.flicker, !flicker.isEmpty {
                for element in flicker {
                    lines.append("  -+ \(compactElementLine(element))")
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

    private static func compactTreeLocation(_ location: TreeLocation) -> String {
        if let parentId = location.parentId {
            return "\(parentId)[\(location.index)]"
        }
        return "root[\(location.index)]"
    }

}
