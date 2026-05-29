import XCTest
import AccessibilitySnapshotModel
import ButtonHeist
import Network
import TheScore

final class FenceResponseTests: XCTestCase {

    // MARK: - Human Formatting Tests

    func testOkHumanFormatting() {
        let response = FenceResponse.ok(message: "bye")
        XCTAssertEqual(response.humanFormatted(), "bye")
    }

    func testErrorHumanFormatting() {
        let response = FenceResponse.error("Something went wrong")
        XCTAssertEqual(response.humanFormatted(), "Error: Something went wrong")
    }

    func testHelpHumanFormatting() {
        let response = FenceResponse.help(commands: ["one_finger_tap", "swipe", "get_interface"])
        let output = response.humanFormatted()
        XCTAssertTrue(output.hasPrefix("Commands:\n"))
        XCTAssertTrue(output.contains("  one_finger_tap"))
        XCTAssertTrue(output.contains("  swipe"))
        XCTAssertTrue(output.contains("  get_interface"))
    }

    func testStatusConnectedHumanFormatting() {
        let response = FenceResponse.status(connected: true, deviceName: "TestApp (iPhone 16)")
        XCTAssertEqual(response.humanFormatted(), "Connected to TestApp (iPhone 16)")
    }

    func testStatusDisconnectedHumanFormatting() {
        let response = FenceResponse.status(connected: false, deviceName: nil)
        XCTAssertEqual(response.humanFormatted(), "Not connected")
    }

    func testDevicesEmptyHumanFormatting() {
        let response = FenceResponse.devices([])
        XCTAssertEqual(response.humanFormatted(), "No devices found")
    }

    func testDevicesHumanFormatting() {
        let device = makeDevice(name: "TestApp-iPhone 16#a1b2c3d4")
        let response = FenceResponse.devices([device])
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("1 device(s):"))
        XCTAssertTrue(output.contains("[0]"))
        XCTAssertTrue(output.contains("a1b2c3d4"))
        XCTAssertTrue(output.contains("TestApp"))
    }

    func testInterfaceEmptyHumanFormatting() {
        let iface = Interface(timestamp: Date(), tree: [])
        let response = FenceResponse.interface(iface)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("0 elements"))
        XCTAssertTrue(output.contains("(no elements)"))
    }

    func testInterfaceWithElementsHumanFormatting() {
        let element = HeistElement(
            description: "Button", label: "Submit",
            value: nil, identifier: "submitBtn",
            frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
        let iface = makeInterface(elements: [element], timestamp: Date())
        let response = FenceResponse.interface(iface)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("1 elements"))
        XCTAssertTrue(output.contains("Submit"))
        XCTAssertTrue(output.contains("ID: submitBtn"))
    }

    func testActionSuccessHumanFormatting() {
        let result = ActionResult(success: true, method: .syntheticTap)
        let response = FenceResponse.action(command: .oneFingerTap, result: result)
        let output = response.humanFormatted()
        XCTAssertTrue(output.hasPrefix("✓"))
        XCTAssertTrue(output.contains("one_finger_tap"))
    }

    func testActionSuccessWithValueHumanFormatting() {
        let result = ActionResult(success: true, method: .typeText, payload: .value("Hello"))
        let response = FenceResponse.action(command: .typeText, result: result)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("value: \"Hello\""))
    }

    func testActionSuccessAnimatingHumanFormatting() {
        let result = ActionResult(success: true, method: .syntheticTap, animating: true)
        let response = FenceResponse.action(command: .oneFingerTap, result: result)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("(still animating)"))
    }

    func testActionFailureHumanFormatting() {
        let result = ActionResult(success: false, method: .elementNotFound, message: "No element at order 99")
        let response = FenceResponse.action(command: .activate, result: result)
        let output = response.humanFormatted()
        XCTAssertTrue(output.hasPrefix("Error:"))
        XCTAssertTrue(output.contains("No element at order 99"))
    }

    func testScreenshotHumanFormatting() {
        let response = FenceResponse.screenshot(
            path: "/tmp/screen.png",
            payload: ScreenPayload(pngData: "abc123", width: 393, height: 852, interface: Interface(timestamp: Date(), tree: []))
        )
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("/tmp/screen.png"))
        XCTAssertTrue(output.contains("393 × 852"))
    }

    func testScreenshotDataHumanFormatting() {
        let response = FenceResponse.screenshotData(
            payload: ScreenPayload(pngData: "abc123", width: 393, height: 852, interface: Interface(timestamp: Date(), tree: []))
        )
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("393 × 852"))
        XCTAssertTrue(output.contains("abc123"))
    }

    func testRecordingHumanFormatting() {
        let payload = makeRecordingPayload(stopReason: .inactivity)
        let response = FenceResponse.recording(path: "/tmp/rec.mp4", payload: payload)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("/tmp/rec.mp4"))
        XCTAssertTrue(output.contains("390×844"))
        XCTAssertTrue(output.contains("5.0s"))
        XCTAssertTrue(output.contains("40 frames"))
        XCTAssertTrue(output.contains("inactivity"))
    }

    func testRecordingDataHumanFormatting() {
        let payload = makeRecordingPayload(stopReason: .manual)
        let response = FenceResponse.recordingData(payload: payload)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("390×844"))
        XCTAssertTrue(output.contains("5.0s"))
        XCTAssertTrue(output.contains("40 frames"))
        XCTAssertTrue(output.contains("manual"))
    }

    // MARK: - JSON Formatting Tests

    func testOkJsonFormatting() {
        let response = FenceResponse.ok(message: "bye")
        let dict = publicJSONObject(response)
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertEqual(dict["message"] as? String, "bye")
    }

    func testErrorJsonFormatting() {
        let response = FenceResponse.error("fail")
        let dict = publicJSONObject(response)
        XCTAssertEqual(dict["status"] as? String, "error")
        XCTAssertEqual(dict["message"] as? String, "fail")
    }

    func testHelpJsonFormatting() {
        let response = FenceResponse.help(commands: ["one_finger_tap", "swipe"])
        let dict = publicJSONObject(response)
        XCTAssertEqual(dict["status"] as? String, "ok")
        let commands = dict["commands"] as? [String]
        XCTAssertEqual(commands, ["one_finger_tap", "swipe"])
    }

    func testStatusJsonFormatting() {
        let response = FenceResponse.status(connected: true, deviceName: "MyApp")
        let dict = publicJSONObject(response)
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertEqual(dict["connected"] as? Bool, true)
        XCTAssertEqual(dict["device"] as? String, "MyApp")
    }

    func testStatusDisconnectedJsonFormatting() {
        let response = FenceResponse.status(connected: false, deviceName: nil)
        let dict = publicJSONObject(response)
        XCTAssertEqual(dict["connected"] as? Bool, false)
        XCTAssertNil(dict["device"])
    }

    func testDevicesJsonFormatting() {
        let device = makeDevice(name: "TestApp-iPhone#abc123", simulatorUDID: "DEAD-BEEF")
        let response = FenceResponse.devices([device])
        let dict = publicJSONObject(response)
        XCTAssertEqual(dict["status"] as? String, "ok")
        let devices = dict["devices"] as? [[String: Any]]
        XCTAssertEqual(devices?.count, 1)
        XCTAssertEqual(devices?.first?["name"] as? String, "TestApp-iPhone#abc123")
        XCTAssertEqual(devices?.first?["simulatorUDID"] as? String, "DEAD-BEEF")
    }

    func testInterfaceJsonFormatting() {
        let element = HeistElement(
            description: "Button", label: "OK",
            value: nil, identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44, actions: []
        )
        let iface = makeInterface(elements: [element], timestamp: Date())
        let response = FenceResponse.interface(iface)
        let dict = publicJSONObject(response)
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertNotNil(dict["interface"])
    }

    func testActionSuccessJsonFormatting() {
        let result = ActionResult(success: true, method: .syntheticTap, payload: .value("Hello"))
        let response = FenceResponse.action(command: .oneFingerTap, result: result)
        let dict = publicJSONObject(response)
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertEqual(dict["method"] as? String, "one_finger_tap")
        XCTAssertEqual(dict["value"] as? String, "Hello")
    }

    func testActionFailureJsonFormatting() {
        let result = ActionResult(success: false, method: .elementNotFound, message: "Not found")
        let response = FenceResponse.action(command: .activate, result: result)
        let dict = publicJSONObject(response)
        XCTAssertEqual(dict["status"] as? String, "error")
        XCTAssertEqual(dict["method"] as? String, "activate")
        XCTAssertEqual(dict["message"] as? String, "Not found")
    }

    func testActionAnimatingJsonFormatting() {
        let result = ActionResult(success: true, method: .syntheticTap, animating: true)
        let response = FenceResponse.action(command: .activate, result: result)
        let dict = publicJSONObject(response)
        XCTAssertEqual(dict["animating"] as? Bool, true)
    }

    func testScreenshotJsonFormatting() {
        let response = FenceResponse.screenshot(
            path: "/tmp/s.png",
            payload: ScreenPayload(pngData: "abc123", width: 393, height: 852, interface: Interface(timestamp: Date(), tree: []))
        )
        let dict = publicJSONObject(response)
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertEqual(dict["path"] as? String, "/tmp/s.png")
        XCTAssertEqual(dict["width"] as? Double, 393)
        XCTAssertEqual(dict["height"] as? Double, 852)
    }

    func testScreenshotDataJsonFormatting() {
        let response = FenceResponse.screenshotData(
            payload: ScreenPayload(pngData: "base64data", width: 393, height: 852, interface: Interface(timestamp: Date(), tree: []))
        )
        let dict = publicJSONObject(response)
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertEqual(dict["pngData"] as? String, "base64data")
    }

    func testRecordingJsonFormatting() {
        let payload = makeRecordingPayload(stopReason: .maxDuration)
        let response = FenceResponse.recording(path: "/tmp/rec.mp4", payload: payload)
        let dict = publicJSONObject(response)
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertEqual(dict["path"] as? String, "/tmp/rec.mp4")
        XCTAssertEqual(dict["width"] as? Int, 390)
        XCTAssertEqual(dict["height"] as? Int, 844)
        XCTAssertEqual(dict["duration"] as? Double, 5.0)
        XCTAssertEqual(dict["frameCount"] as? Int, 40)
        XCTAssertEqual(dict["fps"] as? Int, 8)
        XCTAssertEqual(dict["stopReason"] as? String, "maxDuration")
    }

    func testRecordingDataJsonFormatting() {
        let payload = makeRecordingPayload(stopReason: .fileSizeLimit)
        let response = FenceResponse.recordingData(payload: payload)
        let dict = publicJSONObject(response)
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertEqual(dict["videoData"] as? String, "AAAAIGZ0eXBpc29t")
        XCTAssertEqual(dict["width"] as? Int, 390)
        XCTAssertEqual(dict["stopReason"] as? String, "fileSizeLimit")
    }

    // MARK: - Interaction Count Tests

    func testRecordingWithInteractionsHumanFormatting() {
        let payload = makeRecordingPayloadWithInteractions(count: 5)
        let response = FenceResponse.recording(path: "/tmp/rec.mp4", payload: payload)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("Interactions: 5"))
    }

    func testRecordingDataWithInteractionsHumanFormatting() {
        let payload = makeRecordingPayloadWithInteractions(count: 3)
        let response = FenceResponse.recordingData(payload: payload)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("Interactions: 3"))
    }

    func testRecordingWithoutInteractionsShowsZeroInteractionLine() {
        let payload = makeRecordingPayload(stopReason: .manual)
        let response = FenceResponse.recording(path: "/tmp/rec.mp4", payload: payload)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("Interactions: 0"))
    }

    func testRecordingJsonInteractionCount() {
        let payload = makeRecordingPayloadWithInteractions(count: 7)
        let response = FenceResponse.recording(path: "/tmp/rec.mp4", payload: payload)
        let dict = publicJSONObject(response)
        XCTAssertEqual(dict["interactionCount"] as? Int, 7)
    }

    func testRecordingJsonZeroInteractionCount() {
        let payload = makeRecordingPayload(stopReason: .manual)
        let response = FenceResponse.recording(path: "/tmp/rec.mp4", payload: payload)
        let dict = publicJSONObject(response)
        XCTAssertEqual(dict["interactionCount"] as? Int, 0)
    }

    func testRecordingJsonIncludesInteractionLog() {
        let payload = makeRecordingPayloadWithInteractions(count: 3)
        let response = FenceResponse.recordingExpanded(
            path: "/tmp/rec.mp4",
            payload: payload,
            options: RecordingResponseOptions(includeInteractionLog: true)
        )
        let dict = publicJSONObject(response)
        let log = dict["interactionLog"] as? [[String: Any]]
        XCTAssertNotNil(log)
        XCTAssertEqual(log?.count, 3)
    }

    func testRecordingJsonOmitsInteractionLogUnlessExplicitlyRequested() {
        let payload = makeRecordingPayloadWithInteractions(count: 3)
        let response = FenceResponse.recording(path: "/tmp/rec.mp4", payload: payload)
        let dict = publicJSONObject(response)
        XCTAssertEqual(dict["interactionCount"] as? Int, 3)
        XCTAssertNil(dict["interactionLog"])
    }

    func testRecordingExpandedJsonIncludesInlineVideoWhenExplicitlyRequested() {
        let payload = makeRecordingPayloadWithInteractions(count: 2)
        let response = FenceResponse.recordingExpanded(
            path: "/tmp/rec.mp4",
            payload: payload,
            options: RecordingResponseOptions(inlineData: true, includeInteractionLog: true)
        )
        let dict = publicJSONObject(response)
        XCTAssertEqual(dict["path"] as? String, "/tmp/rec.mp4")
        XCTAssertEqual(dict["videoData"] as? String, "AAAAIGZ0eXBpc29t")
        XCTAssertEqual((dict["interactionLog"] as? [[String: Any]])?.count, 2)
    }

    func testRecordingJsonOmitsInteractionLogWhenNil() {
        let payload = makeRecordingPayload(stopReason: .manual)
        let response = FenceResponse.recording(path: "/tmp/rec.mp4", payload: payload)
        let dict = publicJSONObject(response)
        XCTAssertNil(dict["interactionLog"])
    }

    // MARK: - Helpers

    private func makeDevice(name: String, simulatorUDID: String? = nil) -> DiscoveredDevice {
        DiscoveredDevice(
            id: UUID().uuidString,
            name: name,
            endpoint: .hostPort(host: "127.0.0.1", port: 9999),
            simulatorUDID: simulatorUDID
        )
    }

    private func makeElement(heistId: String, label: String) -> HeistElement {
        HeistElement(
            heistId: heistId,
            description: label,
            label: label,
            value: nil,
            identifier: nil,
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: []
        )
    }

    private func makeInterface(elements: [HeistElement], timestamp: Date) -> Interface {
        let tree = elements.enumerated().map { index, element in
            AccessibilityHierarchy.element(makeAccessibilityElement(element), traversalIndex: index)
        }
        let annotations = InterfaceAnnotations(elements: elements.enumerated().map { index, element in
            InterfaceElementAnnotation(
                path: TreePath([index]),
                heistId: element.heistId,
                actions: element.actions
            )
        })
        return Interface(timestamp: timestamp, tree: tree, annotations: annotations)
    }

    private func makeTreeInsertion(index: Int, heistId: String, label: String) -> TreeInsertion {
        let element = makeElement(heistId: heistId, label: label)
        return TreeInsertion(
            location: TreeLocation(parentId: nil, index: index),
            node: .element(makeAccessibilityElement(element), traversalIndex: 0),
            annotations: InterfaceAnnotations(elements: [
                InterfaceElementAnnotation(
                    path: .root,
                    heistId: element.heistId,
                    actions: element.actions
                ),
            ])
        )
    }

    private func makeAccessibilityElement(_ element: HeistElement) -> AccessibilityElement {
        AccessibilityElement(
            description: element.description,
            label: element.label,
            value: element.value,
            traits: AccessibilityTraits.fromNames(element.traits.map(\.rawValue)),
            identifier: element.identifier,
            hint: element.hint,
            userInputLabels: nil,
            shape: .frame(AccessibilityRect(
                x: element.frameX,
                y: element.frameY,
                width: element.frameWidth,
                height: element.frameHeight
            )),
            activationPoint: AccessibilityPoint(x: element.activationPointX, y: element.activationPointY),
            usesDefaultActivationPoint: true,
            customActions: [],
            customContent: element.customContent?.map {
                AccessibilityElement.CustomContent(label: $0.label, value: $0.value, isImportant: $0.isImportant)
            } ?? [],
            customRotors: element.rotors?.map { AccessibilityElement.CustomRotor(name: $0.name) } ?? [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: element.respondsToUserInteraction
        )
    }

    private func makeRecordingPayload(stopReason: RecordingPayload.StopReason) -> RecordingPayload {
        let start = Date()
        return RecordingPayload(
            videoData: "AAAAIGZ0eXBpc29t",
            width: 390,
            height: 844,
            duration: 5.0,
            frameCount: 40,
            fps: 8,
            startTime: start,
            endTime: start.addingTimeInterval(5.0),
            stopReason: stopReason
        )
    }

    private func makeRecordingPayloadWithInteractions(count: Int) -> RecordingPayload {
        let start = Date()
        let events = (0..<count).map { i in
            InteractionEvent(
                timestamp: Double(i),
                command: .activate(.matcher(ElementMatcher(label: "element_\(i)"))),
                result: ActionResult(success: true, method: .activate)
            )
        }
        return RecordingPayload(
            videoData: "AAAAIGZ0eXBpc29t",
            width: 390,
            height: 844,
            duration: 5.0,
            frameCount: 40,
            fps: 8,
            startTime: start,
            endTime: start.addingTimeInterval(5.0),
            stopReason: .manual,
            interactionLog: events
        )
    }
}

private func publicJSONObject(
    _ response: FenceResponse,
    file: StaticString = #filePath,
    line: UInt = #line
) -> [String: Any] {
    do {
        let object = try JSONSerialization.jsonObject(with: try response.jsonData())
        guard let dict = object as? [String: Any] else {
            XCTFail("Expected public JSON object for \(response)", file: file, line: line)
            return [:]
        }
        return dict
    } catch {
        XCTFail("Failed to decode public JSON for \(response): \(error)", file: file, line: line)
        return [:]
    }
}
