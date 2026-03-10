import Foundation
import TheScore

public enum FenceResponse {
    case ok(message: String)
    case error(String)
    case help(commands: [String])
    case status(connected: Bool, deviceName: String?)
    case devices([DiscoveredDevice])
    case interface(Interface)
    case action(result: ActionResult)
    case screenshot(path: String, width: Double, height: Double)
    case screenshotData(pngData: String, width: Double, height: Double)
    case recording(path: String, payload: RecordingPayload)
    case recordingData(payload: RecordingPayload)

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
        case .interface(let interface):
            return formatInterface(interface)
        case .action(let result):
            return formatActionResult(result)
        case .screenshot(let path, let width, let height):
            return "✓ Screenshot saved: \(path)  (\(Int(width)) × \(Int(height)))"
        case .screenshotData(let pngData, let width, let height):
            return "✓ Screenshot captured (\(Int(width)) × \(Int(height))) — base64 PNG follows\n\(pngData)"
        case .recording(let path, let payload):
            return formatRecordingHuman(path: path, payload: payload)
        case .recordingData(let payload):
            return formatRecordingDataHuman(payload)
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
            case .device: typeLabel = "device"
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
        case .interface(let interface):
            return ["status": "ok", "interface": interfaceDictionary(interface)]
        case .action(let result):
            return actionJsonDict(result)
        case .screenshot(let path, let width, let height):
            return ["status": "ok", "path": path, "width": width, "height": height]
        case .screenshotData(let pngData, let width, let height):
            return ["status": "ok", "pngData": pngData, "width": width, "height": height]
        case .recording(let path, let payload):
            return recordingJsonDict(path: path, payload: payload)
        case .recordingData(let payload):
            return recordingDataJsonDict(payload)
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
        return payload
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

    // MARK: - JSON Dictionary Helpers

    private func interfaceDictionary(_ interface: Interface) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var payload: [String: Any] = [
            "timestamp": formatter.string(from: interface.timestamp),
            "elements": interface.elements.map(elementDictionary)
        ]
        if let tree = interface.tree {
            payload["tree"] = tree.map(elementNodeDictionary)
        }
        return payload
    }

    private func elementDictionary(_ element: HeistElement) -> [String: Any] {
        var payload: [String: Any] = [
            "order": element.order,
            "description": element.description,
            "traits": element.traits,
            "frameX": element.frameX,
            "frameY": element.frameY,
            "frameWidth": element.frameWidth,
            "frameHeight": element.frameHeight,
            "activationPointX": element.activationPointX,
            "activationPointY": element.activationPointY,
            "respondsToUserInteraction": element.respondsToUserInteraction,
            "actions": element.actions.map(\.description),
        ]
        if let label = element.label { payload["label"] = label }
        if let value = element.value { payload["value"] = value }
        if let identifier = element.identifier { payload["identifier"] = identifier }
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
            payload["added"] = added.map(elementDictionary)
        }
        if let removedOrders = delta.removedOrders {
            payload["removedOrders"] = removedOrders
        }
        if let valueChanges = delta.valueChanges {
            payload["valueChanges"] = valueChanges.map { change in
                var valuePayload: [String: Any] = ["order": change.order]
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
