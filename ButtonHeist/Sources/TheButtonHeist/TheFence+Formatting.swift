import Foundation
import TheScore

public enum FenceResponse {
    case ok(message: String)
    case error(String)
    case help(commands: [String])
    case status(connected: Bool, deviceName: String?)
    case devices([DiscoveredDevice])
    case interface(Interface, detail: String = "summary")
    case action(result: ActionResult, expectation: ExpectationResult? = nil)
    case screenshot(path: String, width: Double, height: Double)
    case screenshotData(pngData: String, width: Double, height: Double)
    case recording(path: String, payload: RecordingPayload)
    case recordingData(payload: RecordingPayload)
    case batch(results: [[String: Any]], completedSteps: Int, failedIndex: Int?, totalTimingMs: Int, expectationsChecked: Int = 0, expectationsMet: Int = 0)
    case sessionState(payload: [String: Any])

    /// Extract the ActionResult if this response wraps one (for expectation checking).
    var actionResult: ActionResult? {
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
        case .interface(let interface, _):
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
        case .batch(_, let completedSteps, let failedIndex, let totalTimingMs, let checked, let met):
            var text = "Batch: \(completedSteps) step(s) completed in \(totalTimingMs)ms"
            if let idx = failedIndex { text += " (failed at step \(idx))" }
            if checked > 0 { text += " [expectations: \(met)/\(checked) met]" }
            return text
        case .sessionState(let payload):
            let connected = payload["connected"] as? Bool ?? false
            let device = payload["deviceName"] as? String ?? "unknown"
            return connected ? "Session: connected to \(device)" : "Session: not connected"
        }
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
        case .interface(let interface, let detail):
            return ["status": "ok", "detail": detail, "interface": interfaceDictionary(interface, detail: detail)]
        case .action(let result, let expectation):
            var dict = actionJsonDict(result)
            if let expectation {
                dict["expectation"] = Self.expectationResultDict(expectation)
                if !expectation.met {
                    dict["status"] = "expectation_failed"
                }
            }
            return dict
        case .screenshot(let path, let width, let height):
            return ["status": "ok", "path": path, "width": width, "height": height]
        case .screenshotData(let pngData, let width, let height):
            return ["status": "ok", "pngData": pngData, "width": width, "height": height]
        case .recording(let path, let payload):
            return recordingJsonDict(path: path, payload: payload)
        case .recordingData(let payload):
            return recordingDataJsonDict(payload)
        case .batch(let results, let completedSteps, let failedIndex, let totalTimingMs, let checked, let met):
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
            return dict
        case .sessionState(let payload):
            return payload
        }
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

        if let elementLabel = result.elementLabel { payload["elementLabel"] = elementLabel }
        if let elementValue = result.elementValue { payload["elementValue"] = elementValue }
        if let elementTraits = result.elementTraits { payload["elementTraits"] = elementTraits }

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
        let msg = (result.message ?? "").lowercased()
        if msg.contains("not found") || msg.contains("no element") { return "elementNotFound" }
        if msg.contains("timeout") || msg.contains("timed out") { return "timeout" }
        if msg.contains("not supported") || msg.contains("unsupported") { return "unsupported" }
        if msg.contains("keyboard") || msg.contains("first responder") { return "inputError" }
        return "actionFailed"
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
            for element in interface.elements {
                output += formatElement(element)
            }
        }
        output += String(repeating: "-", count: 60)
        return output
    }

    private func formatElement(_ element: HeistElement) -> String {
        var output = ""
        let index = String(format: "  [%2d]", element.order)
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
        case .valuesChanged:
            let count = delta.valueChanges?.count ?? 0
            return "[\(delta.elementCount) elements, \(count) value\(count == 1 ? "" : "s") changed]"
        case .elementsChanged:
            let added = delta.added?.count ?? 0
            let removed = delta.removedOrders?.count ?? 0
            var parts: [String] = ["\(delta.elementCount) elements"]
            if added > 0 { parts.append("+\(added) added") }
            if removed > 0 { parts.append("-\(removed) removed") }
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
        case .interface(let interface, _):
            return Self.compactInterface(interface)
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
        case .batch(_, let completedSteps, let failedIndex, let totalTimingMs, let checked, let met):
            var text = "batch: \(completedSteps) steps in \(totalTimingMs)ms"
            if let idx = failedIndex { text += " (failed at \(idx))" }
            if checked > 0 { text += " [expectations: \(met)/\(checked)]" }
            return text
        case .sessionState(let payload):
            let connected = payload["connected"] as? Bool ?? false
            return connected ? "session: connected" : "session: not connected"
        }
    }

    private func compactActionResult(_ result: ActionResult, expectation: ExpectationResult?) -> String {
        guard result.success else {
            return "error: \(result.message ?? result.method.rawValue)"
        }
        var text: String
        if let delta = result.interfaceDelta {
            text = Self.compactDelta(delta, method: result.method.rawValue)
        } else {
            text = "\(result.method.rawValue): ok"
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

    /// Compact one-line-per-element format for LLM agents.
    /// Geometry is omitted by default — agents can request it via `get_interface --detail full`.
    public static func compactElementLine(_ element: HeistElement) -> String {
        var parts: [String] = []
        parts.append("[\(element.order)]")
        parts.append(element.heistId)

        if let label = element.label {
            parts.append("\"\(label)\"")
        }
        if let value = element.value, !value.isEmpty {
            parts.append("= \"\(value)\"")
        }

        let meaningful = element.traits.filter { $0 != "staticText" }
        if !meaningful.isEmpty {
            parts.append("[\(meaningful.joined(separator: ", "))]")
        }

        let actions = element.actions.map(\.description)
            .filter { $0 != "activate" || element.traits.contains("button") == false }
        if !actions.isEmpty {
            parts.append("{\(actions.joined(separator: ", "))}")
        }

        return parts.joined(separator: " ")
    }

    public static func compactInterface(_ interface: Interface) -> String {
        var lines: [String] = ["\(interface.elements.count) elements"]
        for element in interface.elements {
            lines.append(compactElementLine(element))
        }
        return lines.joined(separator: "\n")
    }

    public static func compactDelta(_ delta: InterfaceDelta, method: String) -> String {
        switch delta.kind {
        case .noChange:
            return "\(method): no change"

        case .valuesChanged:
            var lines: [String] = ["\(method): values changed"]
            for change in delta.valueChanges ?? [] {
                let ref = change.heistId ?? change.identifier ?? "[\(change.order)]"
                let old = change.oldValue ?? "nil"
                let new = change.newValue ?? "nil"
                lines.append("  \(ref): \"\(old)\" → \"\(new)\"")
            }
            return lines.joined(separator: "\n")

        case .elementsChanged:
            var lines: [String] = ["\(method): layout changed (\(delta.elementCount) elements)"]
            if let added = delta.added, !added.isEmpty {
                for el in added {
                    lines.append("  + \(compactElementLine(el))")
                }
            }
            if let removed = delta.removedHeistIds, !removed.isEmpty {
                for id in removed {
                    lines.append("  - \(id)")
                }
            } else if let removedOrders = delta.removedOrders, !removedOrders.isEmpty {
                for order in removedOrders {
                    lines.append("  - [\(order)]")
                }
            }
            if let changes = delta.valueChanges, !changes.isEmpty {
                for change in changes {
                    let ref = change.heistId ?? change.identifier ?? "[\(change.order)]"
                    lines.append("  ~ \(ref): \"\(change.oldValue ?? "nil")\" → \"\(change.newValue ?? "nil")\"")
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

    private func interfaceDictionary(_ interface: Interface, detail: String = "full") -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var payload: [String: Any] = [
            "timestamp": formatter.string(from: interface.timestamp),
            "elements": interface.elements.map { elementDictionary($0, detail: detail) }
        ]
        if detail == "full", let tree = interface.tree {
            payload["tree"] = tree.map(elementNodeDictionary)
        }
        return payload
    }

    private func elementDictionary(_ element: HeistElement, detail: String = "full") -> [String: Any] {
        var payload: [String: Any] = [
            "heistId": element.heistId,
            "order": element.order,
            "description": element.description,
            "traits": element.traits,
            "actions": element.actions.map(\.description),
        ]
        if let label = element.label { payload["label"] = label }
        if let value = element.value { payload["value"] = value }
        if let identifier = element.identifier { payload["identifier"] = identifier }

        // Geometry and extended fields only in full detail
        if detail == "full" {
            payload["frameX"] = element.frameX
            payload["frameY"] = element.frameY
            payload["frameWidth"] = element.frameWidth
            payload["frameHeight"] = element.frameHeight
            payload["activationPointX"] = element.activationPointX
            payload["activationPointY"] = element.activationPointY
            payload["respondsToUserInteraction"] = element.respondsToUserInteraction
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
            "type": group.type,
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

    private func deltaDictionary(_ delta: InterfaceDelta) -> [String: Any] {
        var payload: [String: Any] = [
            "kind": delta.kind.rawValue,
            "elementCount": delta.elementCount
        ]
        if let added = delta.added {
            payload["added"] = added.map { elementDictionary($0) }
        }
        if let removedOrders = delta.removedOrders {
            payload["removedOrders"] = removedOrders
        }
        if let removedHeistIds = delta.removedHeistIds {
            payload["removedHeistIds"] = removedHeistIds
        }
        if let valueChanges = delta.valueChanges {
            payload["valueChanges"] = valueChanges.map { change in
                var valuePayload: [String: Any] = ["order": change.order]
                if let heistId = change.heistId { valuePayload["heistId"] = heistId }
                if let identifier = change.identifier { valuePayload["identifier"] = identifier }
                if let oldValue = change.oldValue { valuePayload["oldValue"] = oldValue }
                if let newValue = change.newValue { valuePayload["newValue"] = newValue }
                return valuePayload
            }
        }
        if let newInterface = delta.newInterface {
            payload["newInterface"] = interfaceDictionary(newInterface)
        }
        return payload
    }
}
