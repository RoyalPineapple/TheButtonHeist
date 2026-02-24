import XCTest
import ButtonHeist
import Network

// We can't import the executable, so we duplicate SessionResponse for testing.
// This tests the same formatting logic that's in SessionCommand.swift.

final class SessionResponseTests: XCTestCase {

    // MARK: - Human Formatting Tests

    func testOkHumanFormatting() {
        let response = SessionResponse.ok(message: "bye")
        XCTAssertEqual(response.humanFormatted(), "bye")
    }

    func testErrorHumanFormatting() {
        let response = SessionResponse.error("Something went wrong")
        XCTAssertEqual(response.humanFormatted(), "Error: Something went wrong")
    }

    func testHelpHumanFormatting() {
        let response = SessionResponse.help(commands: ["tap", "swipe", "get_interface"])
        let output = response.humanFormatted()
        XCTAssertTrue(output.hasPrefix("Commands:\n"))
        XCTAssertTrue(output.contains("  tap"))
        XCTAssertTrue(output.contains("  swipe"))
        XCTAssertTrue(output.contains("  get_interface"))
    }

    func testStatusConnectedHumanFormatting() {
        let response = SessionResponse.status(connected: true, deviceName: "TestApp (iPhone 16)")
        XCTAssertEqual(response.humanFormatted(), "Connected to TestApp (iPhone 16)")
    }

    func testStatusDisconnectedHumanFormatting() {
        let response = SessionResponse.status(connected: false, deviceName: nil)
        XCTAssertEqual(response.humanFormatted(), "Not connected")
    }

    func testDevicesEmptyHumanFormatting() {
        let response = SessionResponse.devices([])
        XCTAssertEqual(response.humanFormatted(), "No devices found")
    }

    func testDevicesHumanFormatting() {
        let device = makeDevice(name: "TestApp-iPhone 16#a1b2c3d4")
        let response = SessionResponse.devices([device])
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("1 device(s):"))
        XCTAssertTrue(output.contains("[0]"))
        XCTAssertTrue(output.contains("a1b2c3d4"))
        XCTAssertTrue(output.contains("TestApp"))
    }

    func testInterfaceEmptyHumanFormatting() {
        let iface = Interface(timestamp: Date(), elements: [])
        let response = SessionResponse.interface(iface)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("0 elements"))
        XCTAssertTrue(output.contains("(no elements)"))
    }

    func testInterfaceWithElementsHumanFormatting() {
        let element = HeistElement(
            order: 0, description: "Button", label: "Submit",
            value: nil, identifier: "submitBtn",
            frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
        let iface = Interface(timestamp: Date(), elements: [element])
        let response = SessionResponse.interface(iface)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("1 elements"))
        XCTAssertTrue(output.contains("Submit"))
        XCTAssertTrue(output.contains("ID: submitBtn"))
    }

    func testActionSuccessHumanFormatting() {
        let result = ActionResult(success: true, method: .syntheticTap)
        let response = SessionResponse.action(result: result)
        let output = response.humanFormatted()
        XCTAssertTrue(output.hasPrefix("✓"))
        XCTAssertTrue(output.contains("syntheticTap"))
    }

    func testActionSuccessWithValueHumanFormatting() {
        let result = ActionResult(success: true, method: .typeText, value: "Hello")
        let response = SessionResponse.action(result: result)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("value: \"Hello\""))
    }

    func testActionSuccessWithDeltaHumanFormatting() {
        let delta = InterfaceDelta(kind: .noChange, elementCount: 5)
        let result = ActionResult(success: true, method: .syntheticTap, interfaceDelta: delta)
        let response = SessionResponse.action(result: result)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("[5 elements, no change]"))
    }

    func testActionSuccessAnimatingHumanFormatting() {
        let result = ActionResult(success: true, method: .syntheticTap, animating: true)
        let response = SessionResponse.action(result: result)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("(still animating)"))
    }

    func testActionFailureHumanFormatting() {
        let result = ActionResult(success: false, method: .elementNotFound, message: "No element at order 99")
        let response = SessionResponse.action(result: result)
        let output = response.humanFormatted()
        XCTAssertTrue(output.hasPrefix("Error:"))
        XCTAssertTrue(output.contains("No element at order 99"))
    }

    func testScreenshotHumanFormatting() {
        let response = SessionResponse.screenshot(path: "/tmp/screen.png", width: 393, height: 852)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("/tmp/screen.png"))
        XCTAssertTrue(output.contains("393 × 852"))
    }

    func testScreenshotDataHumanFormatting() {
        let response = SessionResponse.screenshotData(pngData: "abc123", width: 393, height: 852)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("393 × 852"))
        XCTAssertTrue(output.contains("abc123"))
    }

    // MARK: - Delta Formatting Tests

    func testDeltaNoChangeFormatting() {
        let delta = InterfaceDelta(kind: .noChange, elementCount: 10)
        let result = ActionResult(success: true, method: .syntheticTap, interfaceDelta: delta)
        let output = SessionResponse.action(result: result).humanFormatted()
        XCTAssertTrue(output.contains("[10 elements, no change]"))
    }

    func testDeltaValuesChangedFormatting() {
        let changes = [ValueChange(order: 0, identifier: nil, oldValue: "50", newValue: "75")]
        let delta = InterfaceDelta(kind: .valuesChanged, elementCount: 8, valueChanges: changes)
        let result = ActionResult(success: true, method: .increment, interfaceDelta: delta)
        let output = SessionResponse.action(result: result).humanFormatted()
        XCTAssertTrue(output.contains("[8 elements, 1 value changed]"))
    }

    func testDeltaMultipleValuesChangedFormatting() {
        let changes = [
            ValueChange(order: 0, identifier: nil, oldValue: "A", newValue: "B"),
            ValueChange(order: 1, identifier: nil, oldValue: "C", newValue: "D"),
        ]
        let delta = InterfaceDelta(kind: .valuesChanged, elementCount: 5, valueChanges: changes)
        let result = ActionResult(success: true, method: .syntheticTap, interfaceDelta: delta)
        let output = SessionResponse.action(result: result).humanFormatted()
        XCTAssertTrue(output.contains("[5 elements, 2 values changed]"))
    }

    func testDeltaElementsChangedFormatting() {
        let added = [HeistElement(
            order: 3, description: "New", label: "New Button",
            value: nil, identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44, actions: []
        )]
        let delta = InterfaceDelta(kind: .elementsChanged, elementCount: 6, added: added, removedOrders: [1, 2])
        let result = ActionResult(success: true, method: .syntheticTap, interfaceDelta: delta)
        let output = SessionResponse.action(result: result).humanFormatted()
        XCTAssertTrue(output.contains("+1 added"))
        XCTAssertTrue(output.contains("-2 removed"))
    }

    func testDeltaScreenChangedFormatting() {
        let delta = InterfaceDelta(kind: .screenChanged, elementCount: 12)
        let result = ActionResult(success: true, method: .syntheticTap, interfaceDelta: delta)
        let output = SessionResponse.action(result: result).humanFormatted()
        XCTAssertTrue(output.contains("[12 elements, screen changed]"))
    }

    // MARK: - JSON Formatting Tests

    func testOkJsonFormatting() {
        let response = SessionResponse.ok(message: "bye")
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertEqual(dict["message"] as? String, "bye")
    }

    func testErrorJsonFormatting() {
        let response = SessionResponse.error("fail")
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "error")
        XCTAssertEqual(dict["message"] as? String, "fail")
    }

    func testHelpJsonFormatting() {
        let response = SessionResponse.help(commands: ["tap", "swipe"])
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "ok")
        let commands = dict["commands"] as? [String]
        XCTAssertEqual(commands, ["tap", "swipe"])
    }

    func testStatusJsonFormatting() {
        let response = SessionResponse.status(connected: true, deviceName: "MyApp")
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertEqual(dict["connected"] as? Bool, true)
        XCTAssertEqual(dict["device"] as? String, "MyApp")
    }

    func testStatusDisconnectedJsonFormatting() {
        let response = SessionResponse.status(connected: false, deviceName: nil)
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["connected"] as? Bool, false)
        XCTAssertNil(dict["device"])
    }

    func testDevicesJsonFormatting() {
        let device = makeDevice(name: "TestApp-iPhone#abc123", simulatorUDID: "DEAD-BEEF")
        let response = SessionResponse.devices([device])
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "ok")
        let devices = dict["devices"] as? [[String: Any]]
        XCTAssertEqual(devices?.count, 1)
        XCTAssertEqual(devices?.first?["name"] as? String, "TestApp-iPhone#abc123")
        XCTAssertEqual(devices?.first?["simulatorUDID"] as? String, "DEAD-BEEF")
    }

    func testInterfaceJsonFormatting() {
        let element = HeistElement(
            order: 0, description: "Button", label: "OK",
            value: nil, identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44, actions: []
        )
        let iface = Interface(timestamp: Date(), elements: [element])
        let response = SessionResponse.interface(iface)
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertNotNil(dict["interface"])
    }

    func testActionSuccessJsonFormatting() {
        let result = ActionResult(success: true, method: .syntheticTap, value: "Hello")
        let response = SessionResponse.action(result: result)
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertEqual(dict["method"] as? String, "syntheticTap")
        XCTAssertEqual(dict["value"] as? String, "Hello")
    }

    func testActionFailureJsonFormatting() {
        let result = ActionResult(success: false, method: .elementNotFound, message: "Not found")
        let response = SessionResponse.action(result: result)
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "error")
        XCTAssertEqual(dict["method"] as? String, "elementNotFound")
        XCTAssertEqual(dict["message"] as? String, "Not found")
    }

    func testActionWithDeltaJsonFormatting() {
        let delta = InterfaceDelta(kind: .noChange, elementCount: 5)
        let result = ActionResult(success: true, method: .syntheticTap, interfaceDelta: delta)
        let response = SessionResponse.action(result: result)
        let dict = response.jsonDict()!
        XCTAssertNotNil(dict["delta"])
    }

    func testActionAnimatingJsonFormatting() {
        let result = ActionResult(success: true, method: .syntheticTap, animating: true)
        let response = SessionResponse.action(result: result)
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["animating"] as? Bool, true)
    }

    func testScreenshotJsonFormatting() {
        let response = SessionResponse.screenshot(path: "/tmp/s.png", width: 393, height: 852)
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertEqual(dict["path"] as? String, "/tmp/s.png")
        XCTAssertEqual(dict["width"] as? Double, 393)
        XCTAssertEqual(dict["height"] as? Double, 852)
    }

    func testScreenshotDataJsonFormatting() {
        let response = SessionResponse.screenshotData(pngData: "base64data", width: 393, height: 852)
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertEqual(dict["pngData"] as? String, "base64data")
    }

    // MARK: - Helpers

    private func makeDevice(name: String, simulatorUDID: String? = nil) -> DiscoveredDevice {
        DiscoveredDevice(
            id: UUID().uuidString,
            name: name,
            endpoint: .hostPort(host: "127.0.0.1", port: 1455),
            simulatorUDID: simulatorUDID
        )
    }
}

// MARK: - SessionResponse (copied from SessionCommand.swift for testing)

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
            return devicesDict(devices)
        case .interface(let iface):
            return interfaceDict(iface)
        case .action(let result):
            return actionDict(result)
        case .screenshot(let path, let width, let height):
            return ["status": "ok", "path": path, "width": width, "height": height]
        case .screenshotData(let pngData, let width, let height):
            return ["status": "ok", "pngData": pngData, "width": width, "height": height]
        }
    }

    private func devicesDict(_ devices: [DiscoveredDevice]) -> [String: Any] {
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
    }

    private func interfaceDict(_ iface: Interface) -> [String: Any]? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(iface),
              let ifaceObj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return ["status": "ok", "interface": ifaceObj]
    }

    private func actionDict(_ result: ActionResult) -> [String: Any] {
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
    }
}
