import Foundation
import ButtonHeist
import TheScore

// MARK: - Session Response

enum SessionResponse {
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

    // MARK: Human formatting

    func humanFormatted() -> String {
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
            } else {
                return "Not connected"
            }

        case .devices(let devices):
            if devices.isEmpty { return "No devices found" }
            var out = "\(devices.count) device(s):\n"
            for (i, d) in devices.enumerated() {
                let id = d.shortId ?? "----"
                out += "  [\(i)] \(id)  \(d.appName)  (\(d.deviceName))\n"
            }
            return out.trimmingCharacters(in: .newlines)

        case .interface(let iface):
            return formatInterface(iface)

        case .action(let result):
            return formatActionResult(result)

        case .screenshot(let path, let width, let height):
            return "✓ Screenshot saved: \(path)  (\(Int(width)) × \(Int(height)))"

        case .screenshotData(let pngData, let width, let height):
            return "✓ Screenshot captured (\(Int(width)) × \(Int(height))) — base64 PNG follows\n\(pngData)"

        case .recording(let path, let payload):
            let dur = String(format: "%.1f", payload.duration)
            return "✓ Recording saved: \(path)  " +
                "(\(payload.width)×\(payload.height), \(dur)s, " +
                "\(payload.frameCount) frames, \(payload.stopReason.rawValue))"

        case .recordingData(let payload):
            let sizeKB = payload.videoData.count * 3 / 4 / 1024
            let dur = String(format: "%.1f", payload.duration)
            return "✓ Recording captured " +
                "(\(payload.width)×\(payload.height), \(dur)s, " +
                "\(payload.frameCount) frames, ~\(sizeKB)KB, \(payload.stopReason.rawValue))"
        }
    }

    private func formatInterface(_ iface: Interface) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium

        var out = "\(iface.elements.count) elements (\(formatter.string(from: iface.timestamp)))\n"
        out += String(repeating: "-", count: 60) + "\n"

        if iface.elements.isEmpty {
            out += "  (no elements)\n"
        } else {
            for element in iface.elements {
                out += formatElement(element)
            }
        }

        out += String(repeating: "-", count: 60)
        return out
    }

    private func formatElement(_ element: HeistElement) -> String {
        var out = ""
        let index = String(format: "  [%2d]", element.order)
        let label = element.label ?? element.description
        out += "\(index) \(label)\n"

        if let value = element.value, !value.isEmpty {
            out += "       Value: \(value)\n"
        }
        if let id = element.identifier, !id.isEmpty {
            out += "       ID: \(id)\n"
        }
        if !element.actions.isEmpty {
            out += "       Actions: \(element.actions.map(\.description).joined(separator: ", "))\n"
        }
        out += "       Frame: (\(Int(element.frameX)), \(Int(element.frameY))) \(Int(element.frameWidth))×\(Int(element.frameHeight))\n"
        return out
    }

    private func formatActionResult(_ result: ActionResult) -> String {
        if result.success {
            var out = "✓ \(result.method.rawValue)"
            if let value = result.value {
                out += "  value: \"\(value)\""
            }
            if let delta = result.interfaceDelta {
                out += "  \(formatDelta(delta))"
            }
            if result.animating == true {
                out += "  (still animating)"
            }
            return out
        } else {
            return "Error: \(result.message ?? result.method.rawValue)"
        }
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

    // MARK: JSON formatting

    func jsonDict() -> [String: Any]? {
        switch self {
        case .ok(let message):
            return ["status": "ok", "message": message]

        case .error(let message):
            return ["status": "error", "message": message]

        case .help(let commands):
            return ["status": "ok", "commands": commands]

        case .status(let connected, let deviceName):
            var d: [String: Any] = ["status": "ok", "connected": connected]
            if let name = deviceName { d["device"] = name }
            return d

        case .devices(let devices):
            let infos: [[String: Any]] = devices.map { d in
                var info: [String: Any] = [
                    "name": d.name,
                    "appName": d.appName,
                    "deviceName": d.deviceName,
                ]
                if let sid = d.shortId { info["shortId"] = sid }
                if let udid = d.simulatorUDID { info["simulatorUDID"] = udid }
                if let vid = d.vendorIdentifier { info["vendorIdentifier"] = vid }
                return info
            }
            return ["status": "ok", "devices": infos]

        case .interface(let iface):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(iface),
                  let ifaceObj = try? JSONSerialization.jsonObject(with: data) else { return nil }
            return ["status": "ok", "interface": ifaceObj]

        case .action(let result):
            var d: [String: Any] = [
                "status": result.success ? "ok" : "error",
                "method": result.method.rawValue,
            ]
            if let msg = result.message { d["message"] = msg }
            if let value = result.value { d["value"] = value }
            if result.animating == true { d["animating"] = true }
            if let delta = result.interfaceDelta {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                if let data = try? encoder.encode(delta),
                   let deltaObj = try? JSONSerialization.jsonObject(with: data) {
                    d["delta"] = deltaObj
                }
            }
            return d

        case .screenshot(let path, let width, let height):
            return ["status": "ok", "path": path, "width": width, "height": height]

        case .screenshotData(let pngData, let width, let height):
            return ["status": "ok", "pngData": pngData, "width": width, "height": height]

        case .recording(let path, let payload):
            return [
                "status": "ok",
                "path": path,
                "width": payload.width,
                "height": payload.height,
                "duration": payload.duration,
                "frameCount": payload.frameCount,
                "fps": payload.fps,
                "stopReason": payload.stopReason.rawValue,
            ]

        case .recordingData(let payload):
            return [
                "status": "ok",
                "videoData": payload.videoData,
                "width": payload.width,
                "height": payload.height,
                "duration": payload.duration,
                "frameCount": payload.frameCount,
                "fps": payload.fps,
                "stopReason": payload.stopReason.rawValue,
            ]
        }
    }
}
