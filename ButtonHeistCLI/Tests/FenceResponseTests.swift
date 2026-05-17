import XCTest
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
        let iface = Interface(timestamp: Date(), tree: [.element(element)])
        let response = FenceResponse.interface(iface)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("1 elements"))
        XCTAssertTrue(output.contains("Submit"))
        XCTAssertTrue(output.contains("ID: submitBtn"))
    }

    func testActionSuccessHumanFormatting() {
        let result = ActionResult(success: true, method: .syntheticTap)
        let response = FenceResponse.action(result: result)
        let output = response.humanFormatted()
        XCTAssertTrue(output.hasPrefix("✓"))
        XCTAssertTrue(output.contains("syntheticTap"))
    }

    func testActionSuccessWithValueHumanFormatting() {
        let result = ActionResult(success: true, method: .typeText, payload: .value("Hello"))
        let response = FenceResponse.action(result: result)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("value: \"Hello\""))
    }

    func testActionSuccessWithDeltaHumanFormatting() {
        let delta: AccessibilityTrace.Delta = .noChange(.init(elementCount: 5))
        let result = ActionResult(success: true, method: .syntheticTap, accessibilityDelta: delta)
        let response = FenceResponse.action(result: result)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("[5 elements, no change]"))
    }

    func testActionSuccessAnimatingHumanFormatting() {
        let result = ActionResult(success: true, method: .syntheticTap, animating: true)
        let response = FenceResponse.action(result: result)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("(still animating)"))
    }

    func testActionFailureHumanFormatting() {
        let result = ActionResult(success: false, method: .elementNotFound, message: "No element at order 99")
        let response = FenceResponse.action(result: result)
        let output = response.humanFormatted()
        XCTAssertTrue(output.hasPrefix("Error:"))
        XCTAssertTrue(output.contains("No element at order 99"))
    }

    func testScreenshotHumanFormatting() {
        let response = FenceResponse.screenshot(path: "/tmp/screen.png", width: 393, height: 852)
        let output = response.humanFormatted()
        XCTAssertTrue(output.contains("/tmp/screen.png"))
        XCTAssertTrue(output.contains("393 × 852"))
    }

    func testScreenshotDataHumanFormatting() {
        let response = FenceResponse.screenshotData(pngData: "abc123", width: 393, height: 852)
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

    // MARK: - Delta Formatting Tests

    func testDeltaNoChangeFormatting() {
        let delta: AccessibilityTrace.Delta = .noChange(.init(elementCount: 10))
        let result = ActionResult(success: true, method: .syntheticTap, accessibilityDelta: delta)
        let output = FenceResponse.action(result: result).humanFormatted()
        XCTAssertTrue(output.contains("[10 elements, no change]"))
    }

    func testDeltaElementUpdatedFormatting() {
        let updated = [ElementUpdate(heistId: "slider", changes: [PropertyChange(property: .value, old: "50", new: "75")])]
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 8, edits: ElementEdits(updated: updated)))
        let result = ActionResult(success: true, method: .increment, accessibilityDelta: delta)
        let output = FenceResponse.action(result: result).humanFormatted()
        XCTAssertTrue(output.contains("~1 updated"))
    }

    func testDeltaMultipleUpdatesFormatting() {
        let updated = [
            ElementUpdate(heistId: "a", changes: [PropertyChange(property: .value, old: "A", new: "B")]),
            ElementUpdate(heistId: "b", changes: [PropertyChange(property: .value, old: "C", new: "D")]),
        ]
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: updated)))
        let result = ActionResult(success: true, method: .syntheticTap, accessibilityDelta: delta)
        let output = FenceResponse.action(result: result).humanFormatted()
        XCTAssertTrue(output.contains("~2 updated"))
    }

    func testDeltaElementsChangedFormatting() {
        let added = [HeistElement(
            description: "New", label: "New Button",
            value: nil, identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44, actions: []
        )]
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 6, edits: ElementEdits(added: added, removed: ["old_1", "old_2"])))
        let result = ActionResult(success: true, method: .syntheticTap, accessibilityDelta: delta)
        let output = FenceResponse.action(result: result).humanFormatted()
        XCTAssertTrue(output.contains("+1 added"))
        XCTAssertTrue(output.contains("-2 removed"))
    }

    func testDeltaStructuralFormatting() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits(treeInserted: [
                TreeInsertion(
                    location: TreeLocation(parentId: nil, index: 1),
                    node: .element(makeElement(heistId: "new_row", label: "New Row"))
                ),
            ], treeRemoved: [
                TreeRemoval(
                    ref: TreeNodeRef(id: "old_row", kind: .element),
                    location: TreeLocation(parentId: nil, index: 2)
                ),
            ], treeMoved: [
                TreeMove(
                    ref: TreeNodeRef(id: "moved_row", kind: .element),
                    from: TreeLocation(parentId: nil, index: 0),
                    to: TreeLocation(parentId: nil, index: 3)
                ),
            ])))
        let result = ActionResult(success: true, method: .syntheticTap, accessibilityDelta: delta)
        let output = FenceResponse.action(result: result).humanFormatted()

        XCTAssertTrue(output.contains("+1 tree inserted"))
        XCTAssertTrue(output.contains("-1 tree removed"))
        XCTAssertTrue(output.contains("↕1 moved"))
    }

    func testCompactDeltaSummarizesStructuralChangesWithoutTreeInternals() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits(treeInserted: [
                TreeInsertion(
                    location: TreeLocation(parentId: nil, index: 1),
                    node: .element(makeElement(heistId: "new_row", label: "New Row"))
                ),
            ], treeRemoved: [
                TreeRemoval(
                    ref: TreeNodeRef(id: "old_row", kind: .element),
                    location: TreeLocation(parentId: "parent_row", index: 2)
                ),
            ], treeMoved: [
                TreeMove(
                    ref: TreeNodeRef(id: "moved_row", kind: .element),
                    from: TreeLocation(parentId: nil, index: 0),
                    to: TreeLocation(parentId: "parent_row", index: 3)
                ),
            ])))
        let result = ActionResult(success: true, method: .syntheticTap, accessibilityDelta: delta)
        let output = FenceResponse.action(result: result).compactFormatted()

        XCTAssertTrue(output.contains("hierarchy changed (+1, -1, moved 1)"))
        XCTAssertFalse(output.contains("root["))
        XCTAssertFalse(output.contains("parent_row["))
        XCTAssertFalse(output.contains("moved_row:"))
    }

    func testDeltaScreenChangedFormatting() {
        let delta: AccessibilityTrace.Delta = .screenChanged(.init(
            elementCount: 12,
            newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        ))
        let result = ActionResult(success: true, method: .syntheticTap, accessibilityDelta: delta)
        let output = FenceResponse.action(result: result).humanFormatted()
        XCTAssertTrue(output.contains("[12 elements, screen changed]"))
    }

    // MARK: - JSON Formatting Tests

    func testOkJsonFormatting() {
        let response = FenceResponse.ok(message: "bye")
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertEqual(dict["message"] as? String, "bye")
    }

    func testErrorJsonFormatting() {
        let response = FenceResponse.error("fail")
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "error")
        XCTAssertEqual(dict["message"] as? String, "fail")
    }

    func testHelpJsonFormatting() {
        let response = FenceResponse.help(commands: ["one_finger_tap", "swipe"])
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "ok")
        let commands = dict["commands"] as? [String]
        XCTAssertEqual(commands, ["one_finger_tap", "swipe"])
    }

    func testStatusJsonFormatting() {
        let response = FenceResponse.status(connected: true, deviceName: "MyApp")
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertEqual(dict["connected"] as? Bool, true)
        XCTAssertEqual(dict["device"] as? String, "MyApp")
    }

    func testStatusDisconnectedJsonFormatting() {
        let response = FenceResponse.status(connected: false, deviceName: nil)
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["connected"] as? Bool, false)
        XCTAssertNil(dict["device"])
    }

    func testDevicesJsonFormatting() {
        let device = makeDevice(name: "TestApp-iPhone#abc123", simulatorUDID: "DEAD-BEEF")
        let response = FenceResponse.devices([device])
        let dict = response.jsonDict()!
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
        let iface = Interface(timestamp: Date(), tree: [.element(element)])
        let response = FenceResponse.interface(iface)
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertNotNil(dict["interface"])
    }

    func testActionSuccessJsonFormatting() {
        let result = ActionResult(success: true, method: .syntheticTap, payload: .value("Hello"))
        let response = FenceResponse.action(result: result)
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertEqual(dict["method"] as? String, "syntheticTap")
        XCTAssertEqual(dict["value"] as? String, "Hello")
    }

    func testActionFailureJsonFormatting() {
        let result = ActionResult(success: false, method: .elementNotFound, message: "Not found")
        let response = FenceResponse.action(result: result)
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "error")
        XCTAssertEqual(dict["method"] as? String, "elementNotFound")
        XCTAssertEqual(dict["message"] as? String, "Not found")
    }

    func testActionWithDeltaJsonFormatting() {
        let delta: AccessibilityTrace.Delta = .noChange(.init(elementCount: 5))
        let result = ActionResult(success: true, method: .syntheticTap, accessibilityDelta: delta)
        let response = FenceResponse.action(result: result)
        let dict = response.jsonDict()!
        XCTAssertNotNil(dict["delta"])
    }

    func testActionWithStructuralDeltaJsonFormatting() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits(treeInserted: [
                TreeInsertion(
                    location: TreeLocation(parentId: nil, index: 1),
                    node: .element(makeElement(heistId: "new_row", label: "New Row"))
                ),
            ], treeRemoved: [
                TreeRemoval(
                    ref: TreeNodeRef(id: "old_row", kind: .element),
                    location: TreeLocation(parentId: nil, index: 2)
                ),
            ], treeMoved: [
                TreeMove(
                    ref: TreeNodeRef(id: "moved_row", kind: .element),
                    from: TreeLocation(parentId: nil, index: 0),
                    to: TreeLocation(parentId: nil, index: 3)
                ),
            ])))
        let result = ActionResult(success: true, method: .syntheticTap, accessibilityDelta: delta)
        let response = FenceResponse.action(result: result)
        let dict = response.jsonDict()!
        let deltaDict = dict["delta"] as? [String: Any]
        let editsDict = deltaDict?["edits"] as? [String: Any]

        XCTAssertEqual((editsDict?["treeInserted"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((editsDict?["treeRemoved"] as? [[String: Any]])?.count, 1)
        let moved = editsDict?["treeMoved"] as? [[String: Any]]
        XCTAssertEqual(moved?.count, 1)
        let ref = moved?.first?["ref"] as? [String: Any]
        XCTAssertEqual(ref?["id"] as? String, "moved_row")
        let to = moved?.first?["to"] as? [String: Any]
        XCTAssertEqual(to?["index"] as? Int, 3)
    }

    func testActionAnimatingJsonFormatting() {
        let result = ActionResult(success: true, method: .syntheticTap, animating: true)
        let response = FenceResponse.action(result: result)
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["animating"] as? Bool, true)
    }

    func testScreenshotJsonFormatting() {
        let response = FenceResponse.screenshot(path: "/tmp/s.png", width: 393, height: 852)
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertEqual(dict["path"] as? String, "/tmp/s.png")
        XCTAssertEqual(dict["width"] as? Double, 393)
        XCTAssertEqual(dict["height"] as? Double, 852)
    }

    func testScreenshotDataJsonFormatting() {
        let response = FenceResponse.screenshotData(pngData: "base64data", width: 393, height: 852)
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["status"] as? String, "ok")
        XCTAssertEqual(dict["pngData"] as? String, "base64data")
    }

    func testRecordingJsonFormatting() {
        let payload = makeRecordingPayload(stopReason: .maxDuration)
        let response = FenceResponse.recording(path: "/tmp/rec.mp4", payload: payload)
        let dict = response.jsonDict()!
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
        let dict = response.jsonDict()!
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

    func testRecordingWithoutInteractionsNoInteractionLine() {
        let payload = makeRecordingPayload(stopReason: .manual)
        let response = FenceResponse.recording(path: "/tmp/rec.mp4", payload: payload)
        let output = response.humanFormatted()
        XCTAssertFalse(output.contains("Interactions:"))
    }

    func testRecordingJsonInteractionCount() {
        let payload = makeRecordingPayloadWithInteractions(count: 7)
        let response = FenceResponse.recording(path: "/tmp/rec.mp4", payload: payload)
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["interactionCount"] as? Int, 7)
    }

    func testRecordingJsonZeroInteractionCount() {
        let payload = makeRecordingPayload(stopReason: .manual)
        let response = FenceResponse.recording(path: "/tmp/rec.mp4", payload: payload)
        let dict = response.jsonDict()!
        XCTAssertEqual(dict["interactionCount"] as? Int, 0)
    }

    func testRecordingJsonIncludesInteractionLog() {
        let payload = makeRecordingPayloadWithInteractions(count: 3)
        let response = FenceResponse.recording(path: "/tmp/rec.mp4", payload: payload)
        let dict = response.jsonDict()!
        let log = dict["interactionLog"] as? [[String: Any]]
        XCTAssertNotNil(log)
        XCTAssertEqual(log?.count, 3)
    }

    func testRecordingJsonOmitsInteractionLogWhenNil() {
        let payload = makeRecordingPayload(stopReason: .manual)
        let response = FenceResponse.recording(path: "/tmp/rec.mp4", payload: payload)
        let dict = response.jsonDict()!
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
                result: ActionResult(success: true, method: .activate, accessibilityDelta: .noChange(.init(elementCount: 0)))
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
