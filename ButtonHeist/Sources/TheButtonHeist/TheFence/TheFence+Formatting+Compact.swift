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
        }
    }

    private func compactActionResult(_ result: ActionResult, expectation: ExpectationResult?) -> String {
        guard result.success else {
            if case .scrollSearch(let search) = result.payload {
                return Self.compactScrollSearchNotFound(
                    search,
                    method: result.method,
                    errorKind: Self.compactActionErrorKind(result),
                    screenId: result.screenId
                )
            }
            return Self.compactActionFailure(result)
        }

        var text: String
        switch result.payload {
        case .scrollSearch(let search):
            text = Self.compactScrollSearchFound(search, method: result.method)
        case .rotor(let search):
            text = Self.compactRotor(search)
        case .value, .explore, .none:
            if let delta = result.interfaceDelta {
                text = Self.compactDelta(delta, method: result.method.rawValue)
            } else {
                text = "\(result.method.rawValue): ok"
            }
        }
        if let screenId = result.screenId {
            text = "\(screenId) | \(text)"
        }
        if case .value(let value) = result.payload {
            text += "\nvalue: \"\(value)\""
        }
        if let expectation {
            if !expectation.met {
                text += "\n[expectation FAILED: got \(expectation.actual ?? "nil")]"
                if let hint = Self.compactExpectationFailureHint(expectation) {
                    text += "\nhint: \(hint)"
                }
            }
        }
        return text
    }

    private static func compactRotor(_ search: RotorResult) -> String {
        var text = "rotor \(search.direction.rawValue): \(search.rotor)"
        if let element = search.foundElement {
            text += "\n  \(compactElementLine(element))"
        }
        if let range = search.textRange {
            text += "\n  textRange=\(range.rangeDescription)"
            if let rangeText = range.text {
                text += " \"\(rangeText)\""
            }
        }
        return text
    }

    private static func compactExpectationFailureHint(_ expectation: ExpectationResult) -> String? {
        guard expectation.expectation == .screenChanged, expectation.actual == "elementsChanged" else {
            return nil
        }
        return "screen_changed requires a screen-level transition; " +
            "use elements_changed for same-screen element updates " +
            "or wait_for_change when the UI may settle asynchronously"
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

    private static func compactActionFailure(_ result: ActionResult) -> String {
        let message = result.message ?? result.method.rawValue
        var text = "\(result.method.rawValue): error[\(compactActionErrorKind(result).rawValue)]: \(message)"
        if let screenId = result.screenId {
            text = "\(screenId) | \(text)"
        }
        return text
    }

    private static func compactActionErrorKind(_ result: ActionResult) -> ErrorKind {
        if let errorKind = result.errorKind {
            return errorKind
        }
        if case .scrollSearch = result.payload {
            return .elementNotFound
        }
        switch result.method {
        case .elementNotFound, .elementDeallocated:
            return .elementNotFound
        default:
            return .actionFailed
        }
    }

    private static func compactScrollSearchFound(
        _ search: ScrollSearchResult,
        method: ActionMethod
    ) -> String {
        let commandName = compactScrollSearchCommandName(for: method)
        var header: String
        if search.scrollCount == 0 {
            header = "\(commandName): already visible"
        } else {
            let itemInfo = scrollSearchItemInfo(search)
            header = "\(commandName): found after \(search.scrollCount) scrolls\(itemInfo)"
        }
        if let element = search.foundElement {
            header += "\n  \(compactElementLine(element))"
        }
        return header
    }

    private static func compactScrollSearchNotFound(
        _ search: ScrollSearchResult,
        method: ActionMethod,
        errorKind: ErrorKind,
        screenId: String?
    ) -> String {
        let commandName = compactScrollSearchCommandName(for: method)
        var text: String
        if search.exhaustive {
            let itemInfo = scrollSearchItemInfo(search)
            text = "\(commandName): error[\(errorKind.rawValue)]: not found\(itemInfo) (exhaustive)"
        } else if search.scrollCount > 0 {
            let itemInfo = scrollSearchItemInfo(search)
            text = "\(commandName): error[\(errorKind.rawValue)]: not found after \(search.scrollCount) scrolls\(itemInfo)"
        } else {
            text = "\(commandName): error[\(errorKind.rawValue)]: not found"
        }
        if let screenId {
            text = "\(screenId) | \(text)"
        }
        return text
    }

    private static func compactScrollSearchCommandName(for method: ActionMethod) -> String {
        switch method {
        case .elementSearch:
            return "element_search"
        case .scrollToVisible:
            return "scroll_to_visible"
        default:
            return method.rawValue
        }
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
    static func compactElementLine(
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
        if let rotors = element.rotors, !rotors.isEmpty {
            parts.append("rotors={\(rotors.map(\.name).joined(separator: ", "))}")
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

    static func compactInterface(_ interface: Interface) -> String {
        var lines: [String] = ["\(interface.elements.count) elements"]
        lines.append(contentsOf: compactTreeLines(interface, detail: .summary))
        return lines.joined(separator: "\n")
    }

    private static func compactTreeLines(
        _ interface: Interface,
        detail: InterfaceDetail
    ) -> [String] {
        let counter = LineIndexCounter()
        // Fold each node to a list of un-indented lines; the parent prepends
        // two spaces per nesting level on the way back up. Sharing
        // `InterfaceNode.folded` keeps this walker structurally identical to
        // the JSON encoder's walk.
        return interface.tree.flatMap { node in
            indented(
                lines: node.folded(
                    onElement: { element in
                        let index = counter.value
                        counter.value += 1
                        return [compactElementLine(element, displayIndex: index, detail: detail)]
                    },
                    onContainer: { info, childGroups in
                        let header = "<\(compactContainerLine(info, detail: detail))>"
                        let body = childGroups.flatMap { indented(lines: $0) }
                        return [header] + body
                    }
                ),
                by: 0
            )
        }
    }

    /// Reference counter used by `compactTreeLines` to thread display indices
    /// through `InterfaceNode.folded` without inout state in the closures.
    private final class LineIndexCounter {
        var value: Int = 0
    }

    private static func indented(lines: [String], by depth: Int = 1) -> [String] {
        guard depth > 0 else { return lines }
        let prefix = String(repeating: "  ", count: depth)
        return lines.map { prefix + $0 }
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

    static func compactDelta(_ delta: InterfaceDelta, method: String) -> String {
        switch delta {
        case .noChange(let payload):
            // Auto-settle can produce a no-change delta carrying transients
            // when an element appeared and disappeared during settle but
            // baseline and final are otherwise identical. Surface those.
            if payload.transient.isEmpty {
                return "\(method): no change"
            }
            var lines: [String] = ["\(method): no net change (\(payload.elementCount) elements)"]
            for element in payload.transient {
                lines.append("  +- \(compactElementLine(element))")
            }
            return lines.joined(separator: "\n")

        case .elementsChanged(let payload):
            var lines: [String] = ["\(method): elements changed (\(payload.elementCount) elements)"]
            lines.append(contentsOf: compactEditLines(payload.edits))
            for element in payload.transient {
                lines.append("  +- \(compactElementLine(element))")
            }
            return lines.joined(separator: "\n")

        case .screenChanged(let payload):
            var lines: [String] = ["\(method): screen changed"]
            lines.append(compactInterface(payload.newInterface))
            return lines.joined(separator: "\n")
        }
    }

    private static func compactEditLines(_ edits: ElementEdits) -> [String] {
        var lines: [String] = []
        for element in edits.added {
            lines.append("  + \(compactElementLine(element))")
        }
        for id in edits.removed {
            lines.append("  - \(id)")
        }
        // Omit geometry changes (frame/activationPoint) — layout shifts are structural noise.
        for update in edits.updated {
            for change in update.changes where !change.property.isGeometry {
                lines.append("  ~ \(update.heistId): \(change.property.rawValue) \"\(change.old ?? "nil")\" → \"\(change.new ?? "nil")\"")
            }
        }
        for entry in edits.treeInserted {
            lines.append("  + tree \(compactTreeLocation(entry.location))")
        }
        for entry in edits.treeRemoved {
            lines.append("  - tree \(entry.ref.id) at \(compactTreeLocation(entry.location))")
        }
        for entry in edits.treeMoved {
            lines.append("  ↕ \(entry.ref.id): \(compactTreeLocation(entry.from)) → \(compactTreeLocation(entry.to))")
        }
        return lines
    }

    private static func compactTreeLocation(_ location: TreeLocation) -> String {
        if let parentId = location.parentId {
            return "\(parentId)[\(location.index)]"
        }
        return "root[\(location.index)]"
    }

}
