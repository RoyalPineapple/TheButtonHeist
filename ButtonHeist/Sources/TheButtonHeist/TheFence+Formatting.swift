import Foundation
import TheScore

public enum InterfaceDetail: String, CaseIterable, Sendable {
    case summary
    case full
}

public struct BatchStepSummary: Sendable {
    public let command: String
    public let deltaKind: String?
    public let screenName: String?
    public let expectationMet: Bool?
    public let elementCount: Int?
    public let error: String?
}

// MARK: - Net Delta Accumulator

/// Merges per-step deltas into a single net delta (like git squash).
/// If any step triggered a screen change, the net delta is screenChanged
/// with the final interface. Otherwise, tracks net added/removed/updated.
enum NetDeltaAccumulator {
    static func merge(deltas: [InterfaceDelta]) -> InterfaceDelta? {
        let meaningful = deltas.filter { $0.kind != .noChange }
        guard !meaningful.isEmpty else { return nil }

        // If any step was a screen change, the net is screenChanged with the last one's interface
        if let lastScreenChange = meaningful.last(where: { $0.kind == .screenChanged }) {
            return mergeAfterScreenChange(screenChange: lastScreenChange, deltas: deltas)
        }

        // All steps are elementsChanged — accumulate net adds/removes/updates
        return mergeElementDeltas(meaningful)
    }

    private static func mergeAfterScreenChange(
        screenChange: InterfaceDelta, deltas: [InterfaceDelta]
    ) -> InterfaceDelta {
        // Find steps after the last screen change and fold their element changes
        // into the screen change's interface
        guard let screenIdx = deltas.lastIndex(where: { $0.kind == .screenChanged }) else {
            return screenChange
        }
        let afterScreen = Array(deltas[(screenIdx + 1)...])
        let postDeltas = afterScreen.filter { $0.kind == .elementsChanged }
        if postDeltas.isEmpty {
            return screenChange
        }
        // Merge the post-screen element changes into one
        guard let postMerge = mergeElementDeltas(postDeltas) else { return screenChange }
        // Return screenChanged but with the merged updates appended
        return InterfaceDelta(
            kind: .screenChanged,
            elementCount: postMerge.elementCount,
            added: postMerge.added,
            removed: postMerge.removed,
            updated: postMerge.updated,
            newInterface: screenChange.newInterface
        )
    }

    private static func mergeElementDeltas(_ deltas: [InterfaceDelta]) -> InterfaceDelta? {
        guard !deltas.isEmpty else { return nil }

        var netAdded: [String: HeistElement] = [:]  // heistId → element
        var netRemoved: Set<String> = []
        var netUpdated: [String: [PropertyChange]] = [:]  // heistId → latest changes

        for delta in deltas {
            for el in delta.added ?? [] {
                if netRemoved.contains(el.heistId) {
                    // Was removed earlier, now re-added → treat as net add
                    netRemoved.remove(el.heistId)
                    netAdded[el.heistId] = el
                } else {
                    netAdded[el.heistId] = el
                }
            }
            for hid in delta.removed ?? [] {
                if netAdded.removeValue(forKey: hid) != nil {
                    // Was added earlier in this batch, now removed → nets to nothing
                } else {
                    netRemoved.insert(hid)
                    netUpdated.removeValue(forKey: hid)
                }
            }
            for update in delta.updated ?? [] {
                // Keep latest property values per heistId
                var existing = netUpdated[update.heistId] ?? []
                for change in update.changes {
                    if let idx = existing.firstIndex(where: { $0.property == change.property }) {
                        // Same property updated again — keep original old, use new new
                        existing[idx] = PropertyChange(
                            property: change.property, old: existing[idx].old, new: change.new
                        )
                    } else {
                        existing.append(change)
                    }
                }
                netUpdated[update.heistId] = existing
            }
        }

        // Filter out updates where old == new (property changed and changed back)
        for (hid, changes) in netUpdated {
            let meaningful = changes.filter { $0.old != $0.new }
            if meaningful.isEmpty {
                netUpdated.removeValue(forKey: hid)
            } else {
                netUpdated[hid] = meaningful
            }
        }

        let addedList = netAdded.values.sorted { $0.heistId < $1.heistId }
        let removedList = netRemoved.sorted()
        let updatedList = netUpdated.map { ElementUpdate(heistId: $0.key, changes: $0.value) }
            .sorted { $0.heistId < $1.heistId }

        if addedList.isEmpty && removedList.isEmpty && updatedList.isEmpty { return nil }

        let lastCount = deltas.last?.elementCount ?? 0
        return InterfaceDelta(
            kind: .elementsChanged,
            elementCount: lastCount,
            added: addedList.isEmpty ? nil : addedList,
            removed: removedList.isEmpty ? nil : removedList,
            updated: updatedList.isEmpty ? nil : updatedList
        )
    }
}

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
                    let tier = expectation.expectation
                        .map(String.init(describing:)) ?? "delivery"
                    text += "  [expectation FAILED: expected \(tier),"
                    text += " got \(expectation.actual ?? "nil")]"
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
        case .sessionLog, .archiveResult:
            return formatBookKeeperHuman(self)
        }
    }

    private func formatBookKeeperHuman(_ response: FenceResponse) -> String {
        switch response {
        case .sessionLog(let manifest):
            return formatSessionLogHuman(manifest)
        case .archiveResult(let path, let manifest):
            return "Session archived: \(path) (\(manifest.artifacts.count) artifacts, \(manifest.commandCount) commands)"
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
        let screenshots = manifest.artifacts.filter { $0.type == .screenshot }.count
        let recordings = manifest.artifacts.filter { $0.type == .recording }.count
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
            let typeLabel: String
            switch device.connectionType {
            case .simulator: typeLabel = "sim"
            case .usb: typeLabel = "usb"
            case .network: typeLabel = "network"
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

    // MARK: - JSON Encoding

    public func jsonDict() -> [String: Any]? {
        switch self {
        case .ok(let message):
            return ["status": "ok", "message": message]
        case .error(let message):
            return ["status": "error", "message": message]
        case .help(let commands):
            return ["status": "ok", "commands": commands]
        case .status(let connected, let deviceName):
            var payload: [String: Any] = ["status": "ok", "connected": connected]
            if let deviceName { payload["device"] = deviceName }
            return payload
        case .devices(let devices):
            return devicesJsonDict(devices)
        case .interface(let interface, let detail, let filteredFrom, let explore):
            return interfaceJsonDict(interface, detail: detail, filteredFrom: filteredFrom, explore: explore)
        case .action(let result, let expectation):
            return actionWithExpectationJsonDict(result, expectation: expectation)
        case .screenshot(let path, let width, let height):
            return ["status": "ok", "path": path, "width": width, "height": height]
        case .screenshotData(let pngData, let width, let height):
            return ["status": "ok", "pngData": pngData, "width": width, "height": height]
        case .recording(let path, let payload):
            return recordingJsonDict(path: path, payload: payload)
        case .recordingData(let payload):
            return recordingDataJsonDict(payload)
        case .batch(let results, let completedSteps, let failedIndex, let totalTimingMs, let checked, let met, let stepSummaries, let netDelta):
            return batchJsonDict(
                results: results, completedSteps: completedSteps, failedIndex: failedIndex,
                totalTimingMs: totalTimingMs, checked: checked, met: met,
                stepSummaries: stepSummaries, netDelta: netDelta
            )
        case .sessionState(let payload):
            return payload
        case .targets(let targets, let defaultTarget):
            var info: [String: [String: Any]] = [:]
            for (name, target) in targets {
                var entry: [String: Any] = ["device": target.device]
                if target.token != nil { entry["hasToken"] = true }
                info[name] = entry
            }
            var result: [String: Any] = ["status": "ok", "targets": info]
            if let defaultTarget { result["default"] = defaultTarget }
            return result
        case .sessionLog(let manifest):
            return sessionLogJsonDict(manifest)
        case .archiveResult(let path, let manifest):
            var dict = sessionLogJsonDict(manifest)
            dict["path"] = path
            return dict
        }
    }

    private func sessionLogJsonDict(_ manifest: SessionManifest) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var dict: [String: Any] = [
            "status": "ok",
            "sessionId": manifest.sessionId,
            "startTime": formatter.string(from: manifest.startTime),
            "commandCount": manifest.commandCount,
            "errorCount": manifest.errorCount,
            "artifactCount": manifest.artifacts.count,
        ]
        if let endTime = manifest.endTime {
            dict["endTime"] = formatter.string(from: endTime)
        }
        dict["artifacts"] = manifest.artifacts.map { artifact -> [String: Any] in
            var entry: [String: Any] = [
                "type": artifact.type.rawValue,
                "path": artifact.path,
                "size": artifact.size,
                "timestamp": formatter.string(from: artifact.timestamp),
                "command": artifact.command,
            ]
            if !artifact.metadata.isEmpty {
                entry["metadata"] = artifact.metadata
            }
            return entry
        }
        return dict
    }

    private func interfaceJsonDict(
        _ interface: Interface, detail: InterfaceDetail, filteredFrom: Int?,
        explore: ExploreResult? = nil
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "status": "ok",
            "detail": detail.rawValue,
            "interface": interfaceDictionary(interface, detail: detail),
        ]
        if let filteredFrom { dict["filteredFrom"] = filteredFrom }
        if let explore {
            dict["explore"] = [
                "elementCount": explore.elementCount,
                "scrollCount": explore.scrollCount,
                "containersExplored": explore.containersExplored,
                "explorationTime": explore.explorationTime,
            ] as [String: Any]
        }
        return dict
    }

    private func actionWithExpectationJsonDict(
        _ result: ActionResult, expectation: ExpectationResult?
    ) -> [String: Any] {
        var dict = actionJsonDict(result)
        if let expectation {
            dict["expectation"] = Self.expectationResultDict(expectation)
            if !expectation.met {
                dict["status"] = "expectation_failed"
            }
        }
        return dict
    }

    private func batchJsonDict(
        results: [[String: Any]], completedSteps: Int, failedIndex: Int?,
        totalTimingMs: Int, checked: Int, met: Int,
        stepSummaries: [BatchStepSummary], netDelta: InterfaceDelta?
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "status": failedIndex == nil ? "ok" : "partial",
            "results": results,
            "completedSteps": completedSteps,
            "totalTimingMs": totalTimingMs,
        ]
        if let idx = failedIndex { dict["failedIndex"] = idx }
        if checked > 0 {
            dict["expectations"] = [
                "checked": checked,
                "met": met,
                "allMet": checked == met,
            ]
        }
        if !stepSummaries.isEmpty {
            dict["stepSummaries"] = stepSummaries.enumerated().map { index, s in
                Self.stepSummaryDict(index: index, summary: s)
            }
        }
        if let netDelta {
            dict["netDelta"] = deltaDictionary(netDelta)
        }
        return dict
    }

    private static func stepSummaryDict(index: Int, summary s: BatchStepSummary) -> [String: Any] {
        var entry: [String: Any] = ["index": index, "command": s.command]
        if let kind = s.deltaKind { entry["deltaKind"] = kind }
        if let screen = s.screenName { entry["screenName"] = screen }
        if let met = s.expectationMet { entry["expectationMet"] = met }
        if let count = s.elementCount { entry["elementCount"] = count }
        if let error = s.error { entry["error"] = error }
        return entry
    }

    private func devicesJsonDict(_ devices: [DiscoveredDevice]) -> [String: Any] {
        let info = devices.map { device -> [String: Any] in
            var payload: [String: Any] = [
                "name": device.name,
                "appName": device.appName,
                "deviceName": device.deviceName,
                "connectionType": device.connectionType.rawValue,
            ]
            if let shortId = device.shortId { payload["shortId"] = shortId }
            if let simulatorUDID = device.simulatorUDID { payload["simulatorUDID"] = simulatorUDID }
            return payload
        }
        return ["status": "ok", "devices": info]
    }

    private func actionJsonDict(_ result: ActionResult) -> [String: Any] {
        var payload: [String: Any] = [
            "status": result.success ? "ok" : "error",
            "method": result.method.rawValue,
        ]
        if let message = result.message { payload["message"] = message }
        if let value = result.value { payload["value"] = value }
        if result.animating == true { payload["animating"] = true }
        if let delta = result.interfaceDelta {
            payload["delta"] = deltaDictionary(delta)
        }

        if let screenName = result.screenName { payload["screenName"] = screenName }

        if !result.success {
            payload["errorClass"] = Self.actionErrorClass(result)
        }

        return payload
    }

    static func expectationResultDict(_ result: ExpectationResult) -> [String: Any] {
        var dict: [String: Any] = ["met": result.met]
        if let actual = result.actual { dict["actual"] = actual }
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(result.expectation),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            dict["expected"] = obj
        }
        return dict
    }

    private static func actionErrorClass(_ result: ActionResult) -> String {
        (result.errorKind ?? .actionFailed).rawValue
    }

    private func recordingJsonDict(path: String, payload: RecordingPayload) -> [String: Any] {
        var dict: [String: Any] = [
            "status": "ok",
            "path": path,
            "width": payload.width,
            "height": payload.height,
            "duration": payload.duration,
            "frameCount": payload.frameCount,
            "fps": payload.fps,
            "stopReason": payload.stopReason.rawValue,
            "interactionCount": payload.interactionLog?.count ?? 0,
        ]
        if let logDicts = encodeInteractionLog(payload.interactionLog) {
            dict["interactionLog"] = logDicts
        }
        return dict
    }

    private func recordingDataJsonDict(_ payload: RecordingPayload) -> [String: Any] {
        var dict: [String: Any] = [
            "status": "ok",
            "videoData": payload.videoData,
            "width": payload.width,
            "height": payload.height,
            "duration": payload.duration,
            "frameCount": payload.frameCount,
            "fps": payload.fps,
            "stopReason": payload.stopReason.rawValue,
            "interactionCount": payload.interactionLog?.count ?? 0,
        ]
        if let logDicts = encodeInteractionLog(payload.interactionLog) {
            dict["interactionLog"] = logDicts
        }
        return dict
    }

    private func encodeInteractionLog(_ events: [InteractionEvent]?) -> [[String: Any]]? {
        guard let events, !events.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(events),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return array
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

    // MARK: - Compact Text Format (Token-Efficient)

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
            return targets.keys.sorted().map { name in
                let isDefault = name == defaultTarget ? " *" : ""
                return "\(name): \(targets[name]!.device)\(isDefault)"
            }.joined(separator: "\n")
        case .sessionLog, .archiveResult:
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
        default:
            return ""
        }
    }

    private func compactActionResult(_ result: ActionResult, expectation: ExpectationResult?) -> String {
        guard result.success else {
            if let search = result.scrollSearchResult {
                return Self.compactScrollSearchNotFound(search, screenName: result.screenName)
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
        if let screenName = result.screenName {
            text = "\(screenName) | \(text)"
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

    private static func compactScrollSearchNotFound(_ search: ScrollSearchResult, screenName: String?) -> String {
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
        if let screenName {
            text = "\(screenName) | \(text)"
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
        if let lastScreen = stepSummaries.last(where: { $0.screenName != nil })?.screenName {
            text = "\(lastScreen) | \(text)"
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

    // MARK: - JSON Dictionary Helpers

    private func interfaceDictionary(_ interface: Interface, detail: InterfaceDetail = .full) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var payload: [String: Any] = [
            "timestamp": formatter.string(from: interface.timestamp),
            "elements": interface.elements.map { elementDictionary($0, detail: detail) }
        ]
        if detail == .full, let tree = interface.tree {
            payload["tree"] = tree.map(elementNodeDictionary)
        }
        payload["screenDescription"] = interface.screenDescription
        return payload
    }

    private func elementDictionary(_ element: HeistElement, detail: InterfaceDetail = .full) -> [String: Any] {
        var payload: [String: Any] = [
            "heistId": element.heistId,
            "traits": element.traits.map(\.rawValue),
        ]
        // Only include non-obvious actions (activate is implied by button trait)
        let meaningfulActions = Self.meaningfulActions(element)
        if !meaningfulActions.isEmpty {
            payload["actions"] = meaningfulActions.map(\.description)
        }
        if let label = element.label { payload["label"] = label }
        if let value = element.value { payload["value"] = value }
        if let identifier = element.identifier { payload["identifier"] = identifier }

        // Geometry and extended fields only in full detail
        if detail == .full {
            payload["frameX"] = element.frameX
            payload["frameY"] = element.frameY
            payload["frameWidth"] = element.frameWidth
            payload["frameHeight"] = element.frameHeight
            payload["activationPointX"] = element.activationPointX
            payload["activationPointY"] = element.activationPointY
            if let hint = element.hint { payload["hint"] = hint }
            if let customContent = element.customContent {
                payload["customContent"] = customContent.map {
                    [
                        "label": $0.label,
                        "value": $0.value,
                        "isImportant": $0.isImportant
                    ]
                }
            }
        }
        return payload
    }

    /// Actions that aren't implied by the element's traits.
    /// `activate` is implied by `.button`; `increment`/`decrement` by `.adjustable`.
    private static func meaningfulActions(_ element: HeistElement) -> [ElementAction] {
        element.actions.filter { action in
            switch action {
            case .activate: return !element.traits.contains(.button)
            case .increment, .decrement: return !element.traits.contains(.adjustable)
            case .custom: return true
            }
        }
    }

    private func elementNodeDictionary(_ node: ElementNode) -> [String: Any] {
        switch node {
        case .element(let order):
            return ["element": ["order": order]]
        case .container(let group, let children):
            return [
                "container": [
                    "_0": groupDictionary(group),
                    "children": children.map(elementNodeDictionary)
                ]
            ]
        }
    }

    private func groupDictionary(_ group: Group) -> [String: Any] {
        var payload: [String: Any] = [
            "type": group.type.rawValue,
            "frameX": group.frameX,
            "frameY": group.frameY,
            "frameWidth": group.frameWidth,
            "frameHeight": group.frameHeight
        ]
        if let label = group.label { payload["label"] = label }
        if let value = group.value { payload["value"] = value }
        if let identifier = group.identifier { payload["identifier"] = identifier }
        return payload
    }

    /// Delta dictionaries are always summary-level — geometry changes are filtered out.
    /// Callers who need full geometry should use `get_interface --detail full`.
    private func deltaDictionary(_ delta: InterfaceDelta) -> [String: Any] {
        var payload: [String: Any] = [
            "kind": delta.kind.rawValue,
            "elementCount": delta.elementCount,
        ]
        if let added = delta.added {
            payload["added"] = added.map { elementDictionary($0, detail: .summary) }
        }
        if let removed = delta.removed {
            payload["removed"] = removed
        }
        if let updated = delta.updated {
            // Omit geometry changes (frame/activationPoint) — layout shifts are structural noise
            let filtered: [ElementUpdate] = updated.compactMap { update in
                let meaningful = update.changes.filter { !$0.property.isGeometry }
                return meaningful.isEmpty ? nil : ElementUpdate(heistId: update.heistId, changes: meaningful)
            }
            if !filtered.isEmpty {
                payload["updated"] = filtered.map { update -> [String: Any] in
                    [
                        "heistId": update.heistId,
                        "changes": update.changes.map { change -> [String: Any] in
                            var entry: [String: Any] = ["property": change.property.rawValue]
                            if let old = change.old { entry["old"] = old }
                            if let new = change.new { entry["new"] = new }
                            return entry
                        },
                    ]
                }
            }
        }
        if let newInterface = delta.newInterface {
            payload["newInterface"] = interfaceDictionary(newInterface, detail: .summary)
        }
        return payload
    }
}

// MARK: - Token Telemetry

extension TheFence {

    public func applyTelemetry(to text: String) -> String {
        guard telemetryEnabled else { return text }
        let responseTokens = tokenMeter.record(text)
        return text + "\n" + tokenMeter.formatFooter(responseTokens: responseTokens)
    }

    public func telemetryDict(for text: String) -> [String: Any]? {
        guard telemetryEnabled else { return nil }
        let responseTokens = tokenMeter.record(text)
        return [
            "responseTokens": responseTokens,
            "cumulativeTokens": tokenMeter.cumulativeTokens,
            "responseCount": tokenMeter.responseCount,
        ]
    }
}
