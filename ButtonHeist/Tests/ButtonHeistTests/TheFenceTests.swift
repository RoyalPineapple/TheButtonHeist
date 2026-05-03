import XCTest
@testable import ButtonHeist
import TheScore

final class TheFenceTests: XCTestCase {

    // MARK: - Command Enum

    // MARK: - Element Matcher Validation

    @ButtonHeistActor
    func testElementMatcherRejectsUnknownTrait() async {
        let fence = TheFence()
        let args: [String: Any] = ["traits": ["madeUpTrait"]]
        XCTAssertThrowsError(try fence.elementMatcher(args)) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Unknown trait 'madeUpTrait'"))
        }
    }

    @ButtonHeistActor
    func testElementMatcherRejectsUnknownExcludeTrait() async {
        let fence = TheFence()
        let args: [String: Any] = ["excludeTraits": ["bogus"]]
        XCTAssertThrowsError(try fence.elementMatcher(args)) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Unknown excludeTrait 'bogus'"))
        }
    }

    @ButtonHeistActor
    func testElementMatcherAcceptsKnownTraits() async throws {
        let fence = TheFence()
        let args: [String: Any] = ["traits": ["button", "header"], "excludeTraits": ["selected"]]
        let matcher = try fence.elementMatcher(args)
        XCTAssertEqual(matcher.traits, [.button, .header])
        XCTAssertEqual(matcher.excludeTraits, [.selected])
    }

    // MARK: - Command Enum

    func testCommandCaseCount() {
        XCTAssertEqual(TheFence.Command.allCases.count, 42)
    }

    func testCommandRawValuesMatchWireFormat() {
        let expected: [TheFence.Command: String] = [
            .help: "help",
            .status: "status",
            .quit: "quit",
            .exit: "exit",
            .listDevices: "list_devices",
            .getInterface: "get_interface",
            .getScreen: "get_screen",
            .waitForChange: "wait_for_change",
            .oneFingerTap: "one_finger_tap",
            .longPress: "long_press",
            .swipe: "swipe",
            .drag: "drag",
            .pinch: "pinch",
            .rotate: "rotate",
            .twoFingerTap: "two_finger_tap",
            .drawPath: "draw_path",
            .drawBezier: "draw_bezier",
            .scroll: "scroll",
            .scrollToVisible: "scroll_to_visible",
            .elementSearch: "element_search",
            .scrollToEdge: "scroll_to_edge",
            .activate: "activate",
            .increment: "increment",
            .decrement: "decrement",
            .performCustomAction: "perform_custom_action",
            .typeText: "type_text",
            .editAction: "edit_action",
            .setPasteboard: "set_pasteboard",
            .getPasteboard: "get_pasteboard",
            .waitFor: "wait_for",
            .dismissKeyboard: "dismiss_keyboard",
            .startRecording: "start_recording",
            .stopRecording: "stop_recording",
            .runBatch: "run_batch",
            .getSessionState: "get_session_state",
            .connect: "connect",
            .listTargets: "list_targets",
            .getSessionLog: "get_session_log",
            .archiveSession: "archive_session",
            .startHeist: "start_heist",
            .stopHeist: "stop_heist",
            .playHeist: "play_heist",
        ]
        XCTAssertEqual(expected.count, TheFence.Command.allCases.count)
        for (command, wire) in expected {
            XCTAssertEqual(command.rawValue, wire)
        }
    }

    // MARK: - FenceResponse Human Formatting

    func testOkResponseFormatting() {
        let response = FenceResponse.ok(message: "done")
        XCTAssertEqual(response.humanFormatted(), "done")
    }

    func testErrorResponseFormatting() {
        let response = FenceResponse.error("something broke")
        XCTAssertEqual(response.humanFormatted(), "Error: something broke")
    }

    func testHelpResponseFormatting() {
        let response = FenceResponse.help(commands: ["one_finger_tap", "swipe"])
        let formatted = response.humanFormatted()
        XCTAssertTrue(formatted.contains("one_finger_tap"))
        XCTAssertTrue(formatted.contains("swipe"))
        XCTAssertTrue(formatted.hasPrefix("Commands:"))
    }

    func testStatusResponseConnected() {
        let response = FenceResponse.status(connected: true, deviceName: "TestApp")
        XCTAssertEqual(response.humanFormatted(), "Connected to TestApp")
    }

    func testStatusResponseDisconnected() {
        let response = FenceResponse.status(connected: false, deviceName: nil)
        XCTAssertEqual(response.humanFormatted(), "Not connected")
    }

    func testDevicesResponseEmpty() {
        let response = FenceResponse.devices([])
        XCTAssertEqual(response.humanFormatted(), "No devices found")
    }

    // MARK: - FenceResponse JSON Serialization

    func testOkResponseJSON() {
        let response = FenceResponse.ok(message: "done")
        let json = response.jsonDict()
        XCTAssertEqual(json?["status"] as? String, "ok")
        XCTAssertEqual(json?["message"] as? String, "done")
    }

    func testErrorResponseJSON() {
        let response = FenceResponse.error("failed")
        let json = response.jsonDict()
        XCTAssertEqual(json?["status"] as? String, "error")
        XCTAssertEqual(json?["message"] as? String, "failed")
    }

    func testHelpResponseJSON() {
        let response = FenceResponse.help(commands: ["one_finger_tap", "swipe"])
        let json = response.jsonDict()
        XCTAssertEqual(json?["status"] as? String, "ok")
        let commands = json?["commands"] as? [String]
        XCTAssertEqual(commands, ["one_finger_tap", "swipe"])
    }

    func testStatusResponseJSON() {
        let response = FenceResponse.status(connected: true, deviceName: "MyApp")
        let json = response.jsonDict()
        XCTAssertEqual(json?["connected"] as? Bool, true)
        XCTAssertEqual(json?["device"] as? String, "MyApp")
    }

    func testScreenshotResponseJSON() {
        let response = FenceResponse.screenshot(path: "/tmp/shot.png", width: 390, height: 844)
        let json = response.jsonDict()
        XCTAssertEqual(json?["status"] as? String, "ok")
        XCTAssertEqual(json?["path"] as? String, "/tmp/shot.png")
        XCTAssertEqual(json?["width"] as? Double, 390)
        XCTAssertEqual(json?["height"] as? Double, 844)
    }

    func testFullInterfaceJSONNestsElementsInContainers() {
        let title = HeistElement(
            heistId: "settings_title",
            description: "Settings",
            label: "Settings",
            value: nil,
            identifier: nil,
            traits: [.header],
            frameX: 0,
            frameY: 0,
            frameWidth: 390,
            frameHeight: 44,
            actions: []
        )
        let wifi = HeistElement(
            heistId: "wifi_toggle",
            description: "Wi-Fi",
            label: "Wi-Fi",
            value: "On",
            identifier: nil,
            hint: "Double tap to toggle",
            traits: [.button],
            frameX: 0,
            frameY: 44,
            frameWidth: 390,
            frameHeight: 44,
            actions: [.activate]
        )
        let group = Group(
            type: .list,
            label: "Settings list",
            value: nil,
            identifier: nil,
            frameX: 0,
            frameY: 44,
            frameWidth: 390,
            frameHeight: 600
        )
        let interface = Interface(
            timestamp: Date(),
            elements: [title, wifi],
            tree: [
                .element(order: 0),
                .container(group, children: [.element(order: 1)]),
            ]
        )

        let response = FenceResponse.interface(interface, detail: .full)
        let json = response.jsonDict()!
        let interfaceDict = json["interface"] as! [String: Any]
        let tree = interfaceDict["tree"] as! [[String: Any]]
        XCTAssertNil(interfaceDict["elements"])

        let titleElement = tree[0]["element"] as! [String: Any]
        XCTAssertEqual(titleElement["order"] as? Int, 0)
        XCTAssertEqual(titleElement["heistId"] as? String, "settings_title")

        let container = tree[1]["container"] as! [String: Any]
        XCTAssertEqual(container["type"] as? String, "list")
        XCTAssertEqual(container["frameY"] as? Double, 44)
        XCTAssertNil(container["_0"])

        let children = container["children"] as! [[String: Any]]
        let nestedElement = children[0]["element"] as! [String: Any]
        XCTAssertEqual(nestedElement["order"] as? Int, 1)
        XCTAssertEqual(nestedElement["heistId"] as? String, "wifi_toggle")
        XCTAssertEqual(nestedElement["hint"] as? String, "Double tap to toggle")
        XCTAssertEqual(nestedElement["frameY"] as? Double, 44)
    }

    func testSummaryInterfaceJSONKeepsSemanticsAndOmitsGeometry() {
        let element = HeistElement(
            heistId: "wifi_toggle",
            description: "Wi-Fi",
            label: "Wi-Fi",
            value: "On",
            identifier: "wifi",
            hint: "Double tap to toggle",
            traits: [.button],
            frameX: 0,
            frameY: 44,
            frameWidth: 390,
            frameHeight: 44,
            actions: [.activate]
        )
        let group = Group(
            type: .scrollable,
            label: nil,
            value: "390x1200",
            identifier: nil,
            frameX: 0,
            frameY: 44,
            frameWidth: 390,
            frameHeight: 600
        )
        let interface = Interface(
            timestamp: Date(),
            elements: [element],
            tree: [.container(group, children: [.element(order: 0)])]
        )

        let response = FenceResponse.interface(interface, detail: .summary)
        let json = response.jsonDict()!
        let interfaceDict = json["interface"] as! [String: Any]
        XCTAssertNil(interfaceDict["elements"])

        let tree = interfaceDict["tree"] as! [[String: Any]]
        let container = tree[0]["container"] as! [String: Any]
        XCTAssertEqual(container["type"] as? String, "scrollable")
        XCTAssertEqual(container["value"] as? String, "390x1200")
        XCTAssertNil(container["frameY"])

        let children = container["children"] as! [[String: Any]]
        let nestedElement = children[0]["element"] as! [String: Any]
        XCTAssertEqual(nestedElement["heistId"] as? String, "wifi_toggle")
        XCTAssertEqual(nestedElement["identifier"] as? String, "wifi")
        XCTAssertEqual(nestedElement["hint"] as? String, "Double tap to toggle")
        XCTAssertNil(nestedElement["frameY"])
        XCTAssertNil(nestedElement["activationPointY"])
    }

    func testCompactInterfaceUsesTreeAndSemanticFields() {
        let element = HeistElement(
            heistId: "wifi_toggle",
            description: "Wi-Fi",
            label: "Wi-Fi",
            value: "On",
            identifier: "wifi",
            hint: "Double tap to toggle",
            traits: [.button],
            frameX: 0,
            frameY: 44,
            frameWidth: 390,
            frameHeight: 44,
            actions: [.activate]
        )
        let group = Group(
            type: .scrollable,
            label: nil,
            value: "390x1200",
            identifier: nil,
            frameX: 0,
            frameY: 44,
            frameWidth: 390,
            frameHeight: 600
        )
        let interface = Interface(
            timestamp: Date(),
            elements: [element],
            tree: [.container(group, children: [.element(order: 0)])]
        )

        let text = FenceResponse.interface(interface, detail: .summary).compactFormatted()
        XCTAssertTrue(text.contains("<scrollable = \"390x1200\">"))
        XCTAssertTrue(text.contains("  [0] wifi_toggle id=\"wifi\" \"Wi-Fi\" = \"On\" [button] hint=\"Double tap to toggle\""))
        XCTAssertFalse(text.contains("frame"))
    }

    func testFullCompactInterfaceIncludesGeometry() {
        let element = HeistElement(
            heistId: "wifi_toggle",
            description: "Wi-Fi",
            label: "Wi-Fi",
            value: "On",
            identifier: "wifi",
            hint: "Double tap to toggle",
            traits: [.button],
            frameX: 0,
            frameY: 44,
            frameWidth: 390,
            frameHeight: 44,
            activationPointX: 195,
            activationPointY: 66,
            actions: [.activate]
        )
        let group = Group(
            type: .scrollable,
            label: nil,
            value: "390x1200",
            identifier: nil,
            frameX: 0,
            frameY: 44,
            frameWidth: 390,
            frameHeight: 600
        )
        let interface = Interface(
            timestamp: Date(),
            elements: [element],
            tree: [.container(group, children: [.element(order: 0)])]
        )

        let text = FenceResponse.interface(interface, detail: .full).compactFormatted()
        XCTAssertTrue(text.contains("<scrollable = \"390x1200\" frame=(0,44,390,600)>"))
        XCTAssertTrue(text.contains("frame=(0,44,390,44)"))
        XCTAssertTrue(text.contains("activation=(195,66)"))
    }

    // MARK: - FenceResponse: Action with Expectation (Human Formatting)

    func testActionWithExpectationMetFormatting() {
        let result = ActionResult(success: true, method: .activate)
        let expectation = ExpectationResult(met: true, expectation: .screenChanged, actual: "screenChanged")
        let response = FenceResponse.action(result: result, expectation: expectation)
        let text = response.humanFormatted()
        XCTAssertTrue(text.contains("[expectation met]"))
    }

    func testActionWithExpectationFailedFormatting() {
        let result = ActionResult(success: true, method: .activate, interfaceDelta: InterfaceDelta(kind: .noChange, elementCount: 5))
        let expectation = ExpectationResult(met: false, expectation: .screenChanged, actual: "noChange")
        let response = FenceResponse.action(result: result, expectation: expectation)
        let text = response.humanFormatted()
        XCTAssertTrue(text.contains("[expectation FAILED"))
        XCTAssertTrue(text.contains("noChange"))
    }

    func testActionWithDeliveryFailureFormatting() {
        let result = ActionResult(success: false, method: .activate, message: "not found")
        let expectation = ExpectationResult(met: false, expectation: nil, actual: "not found")
        let response = FenceResponse.action(result: result, expectation: expectation)
        let text = response.humanFormatted()
        XCTAssertTrue(text.contains("[expectation FAILED"))
        XCTAssertTrue(text.contains("delivery"))
    }

    func testActionWithoutExpectationFormatting() {
        let result = ActionResult(success: true, method: .activate)
        let response = FenceResponse.action(result: result)
        let text = response.humanFormatted()
        XCTAssertFalse(text.contains("expectation"))
    }

    // MARK: - FenceResponse: Action with Expectation (JSON)

    func testActionWithExpectationMetJSON() {
        let result = ActionResult(success: true, method: .activate)
        let expectation = ExpectationResult(met: true, expectation: .screenChanged, actual: "screenChanged")
        let response = FenceResponse.action(result: result, expectation: expectation)
        let json = response.jsonDict()!
        XCTAssertEqual(json["status"] as? String, "ok")
        let expDict = json["expectation"] as? [String: Any]
        XCTAssertNotNil(expDict)
        XCTAssertEqual(expDict?["met"] as? Bool, true)
        XCTAssertEqual(expDict?["actual"] as? String, "screenChanged")
    }

    func testActionWithExpectationFailedJSON() {
        let result = ActionResult(success: true, method: .activate)
        let expectation = ExpectationResult(met: false, expectation: .screenChanged, actual: "noChange")
        let response = FenceResponse.action(result: result, expectation: expectation)
        let json = response.jsonDict()!
        XCTAssertEqual(json["status"] as? String, "expectation_failed")
        let expDict = json["expectation"] as? [String: Any]
        XCTAssertEqual(expDict?["met"] as? Bool, false)
    }

    func testActionWithoutExpectationJSON() {
        let result = ActionResult(success: true, method: .activate)
        let response = FenceResponse.action(result: result)
        let json = response.jsonDict()!
        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertNil(json["expectation"])
    }

    // MARK: - FenceResponse.expectationResultDict

    func testExpectationResultDictMet() {
        let result = ExpectationResult(met: true, expectation: .elementsChanged, actual: "elementsChanged")
        let dict = FenceResponse.expectationResultDict(result)
        XCTAssertEqual(dict["met"] as? Bool, true)
        XCTAssertEqual(dict["actual"] as? String, "elementsChanged")
        XCTAssertNotNil(dict["expected"])
    }

    func testExpectationResultDictDelivery() {
        let result = ExpectationResult(met: true, expectation: nil, actual: "delivered")
        let dict = FenceResponse.expectationResultDict(result)
        XCTAssertEqual(dict["met"] as? Bool, true)
        XCTAssertEqual(dict["actual"] as? String, "delivered")
        XCTAssertNil(dict["expected"])
    }

    func testExpectationResultDictElementUpdatedExpectation() {
        let result = ExpectationResult(met: false, expectation: .elementUpdated(newValue: "hello"), actual: "counter: value: world → goodbye")
        let dict = FenceResponse.expectationResultDict(result)
        XCTAssertEqual(dict["met"] as? Bool, false)
        XCTAssertEqual(dict["actual"] as? String, "counter: value: world → goodbye")
        // "expected" should be the JSON-encoded ActionExpectation
        let expected = dict["expected"]
        XCTAssertNotNil(expected)
    }

    // MARK: - FenceResponse: Batch with Expectations

    func testBatchWithExpectationsFormatting() {
        let response = FenceResponse.batch(
            results: [["status": "ok"], ["status": "ok"]],
            completedSteps: 2, failedIndex: nil, totalTimingMs: 100,
            expectationsChecked: 2, expectationsMet: 1
        )
        let text = response.humanFormatted()
        XCTAssertTrue(text.contains("2 step(s) completed"))
        XCTAssertTrue(text.contains("[expectations: 1/2 met]"))
    }

    func testBatchWithoutExpectationsFormatting() {
        let response = FenceResponse.batch(
            results: [["status": "ok"]],
            completedSteps: 1, failedIndex: nil, totalTimingMs: 50
        )
        let text = response.humanFormatted()
        XCTAssertTrue(text.contains("1 step(s) completed"))
        XCTAssertFalse(text.contains("expectations"))
    }

    func testBatchWithFailedIndexFormatting() {
        let response = FenceResponse.batch(
            results: [["status": "ok"], ["status": "error"]],
            completedSteps: 2, failedIndex: 1, totalTimingMs: 80
        )
        let text = response.humanFormatted()
        XCTAssertTrue(text.contains("(failed at step 1)"))
    }

    func testBatchWithExpectationsJSON() {
        let response = FenceResponse.batch(
            results: [["status": "ok"]],
            completedSteps: 1, failedIndex: nil, totalTimingMs: 50,
            expectationsChecked: 3, expectationsMet: 2
        )
        let json = response.jsonDict()!
        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertEqual(json["completedSteps"] as? Int, 1)
        let expectations = json["expectations"] as? [String: Any]
        XCTAssertNotNil(expectations)
        XCTAssertEqual(expectations?["checked"] as? Int, 3)
        XCTAssertEqual(expectations?["met"] as? Int, 2)
        XCTAssertEqual(expectations?["allMet"] as? Bool, false)
    }

    func testBatchWithoutExpectationsJSON() {
        let response = FenceResponse.batch(
            results: [["status": "ok"]],
            completedSteps: 1, failedIndex: nil, totalTimingMs: 50
        )
        let json = response.jsonDict()!
        XCTAssertNil(json["expectations"])
    }

    func testBatchAllExpectationsMetJSON() {
        let response = FenceResponse.batch(
            results: [], completedSteps: 0, failedIndex: nil, totalTimingMs: 0,
            expectationsChecked: 2, expectationsMet: 2
        )
        let json = response.jsonDict()!
        let expectations = json["expectations"] as? [String: Any]
        XCTAssertEqual(expectations?["allMet"] as? Bool, true)
    }

    // MARK: - Compact Delta Geometry Filtering

    func testCompactDeltaOmitsFrameChanges() {
        let delta = InterfaceDelta(
            kind: .elementsChanged,
            elementCount: 3,
            updated: [
                ElementUpdate(heistId: "okBtn", changes: [
                    PropertyChange(property: .value, old: "0", new: "1"),
                    PropertyChange(property: .frame, old: "10,20,100,44", new: "10,25,100,44"),
                ]),
            ]
        )
        let output = FenceResponse.compactDelta(delta, method: "tap")
        XCTAssertTrue(output.contains("value"), "Value change should appear")
        XCTAssertFalse(output.contains("frame"), "Frame change should be filtered")
    }

    func testCompactDeltaOmitsActivationPointChanges() {
        let delta = InterfaceDelta(
            kind: .elementsChanged,
            elementCount: 2,
            updated: [
                ElementUpdate(heistId: "slider", changes: [
                    PropertyChange(property: .activationPoint, old: "50,22", new: "55,22"),
                ]),
            ]
        )
        let output = FenceResponse.compactDelta(delta, method: "drag")
        XCTAssertFalse(output.contains("activationPoint"), "ActivationPoint should be filtered")
        XCTAssertFalse(output.contains("~"), "No ~ lines when only geometry changed")
    }

    func testCompactDeltaKeepsNonGeometryChanges() {
        let delta = InterfaceDelta(
            kind: .elementsChanged,
            elementCount: 4,
            updated: [
                ElementUpdate(heistId: "toggle", changes: [
                    PropertyChange(property: .value, old: "off", new: "on"),
                    PropertyChange(property: .traits, old: "button", new: "button, selected"),
                    PropertyChange(property: .frame, old: "0,0,100,44", new: "0,5,100,44"),
                ]),
            ]
        )
        let output = FenceResponse.compactDelta(delta, method: "tap")
        XCTAssertTrue(output.contains("value"))
        XCTAssertTrue(output.contains("traits"))
        XCTAssertFalse(output.contains("frame"))
    }

    // MARK: - ElementProperty.isGeometry

    func testIsGeometryClassification() {
        XCTAssertTrue(ElementProperty.frame.isGeometry)
        XCTAssertTrue(ElementProperty.activationPoint.isGeometry)
        XCTAssertFalse(ElementProperty.label.isGeometry)
        XCTAssertFalse(ElementProperty.value.isGeometry)
        XCTAssertFalse(ElementProperty.traits.isGeometry)
        XCTAssertFalse(ElementProperty.hint.isGeometry)
        XCTAssertFalse(ElementProperty.actions.isGeometry)
    }

    // MARK: - JSON Delta Geometry Filtering

    func testActionJsonDeltaOmitsGeometryByDefault() {
        let delta = InterfaceDelta(
            kind: .elementsChanged,
            elementCount: 2,
            updated: [
                ElementUpdate(heistId: "label1", changes: [
                    PropertyChange(property: .frame, old: "0,0,100,44", new: "0,10,100,44"),
                    PropertyChange(property: .value, old: "a", new: "b"),
                ]),
            ]
        )
        let result = ActionResult(success: true, method: .activate, interfaceDelta: delta)
        let response = FenceResponse.action(result: result)
        let json = response.jsonDict()!
        let deltaDict = json["delta"] as! [String: Any]
        let updated = deltaDict["updated"] as! [[String: Any]]
        XCTAssertEqual(updated.count, 1)
        let changes = updated[0]["changes"] as! [[String: Any]]
        let properties = changes.map { $0["property"] as! String }
        XCTAssertTrue(properties.contains("value"))
        XCTAssertFalse(properties.contains("frame"))
    }

    func testActionJsonDeltaDropsGeometryOnlyUpdates() {
        let delta = InterfaceDelta(
            kind: .elementsChanged,
            elementCount: 3,
            updated: [
                ElementUpdate(heistId: "img", changes: [
                    PropertyChange(property: .frame, old: "0,0,50,50", new: "0,5,50,50"),
                    PropertyChange(property: .activationPoint, old: "25,25", new: "25,30"),
                ]),
            ]
        )
        let result = ActionResult(success: true, method: .activate, interfaceDelta: delta)
        let response = FenceResponse.action(result: result)
        let json = response.jsonDict()!
        let deltaDict = json["delta"] as! [String: Any]
        XCTAssertNil(deltaDict["updated"], "Geometry-only updates should be dropped entirely")
    }

    // MARK: - FenceError

    func testFenceErrorDescriptions() {
        XCTAssertNotNil(FenceError.noDeviceFound.errorDescription)
        XCTAssertNotNil(FenceError.connectionTimeout.errorDescription)
        XCTAssertNotNil(FenceError.notConnected.errorDescription)
        XCTAssertNotNil(FenceError.actionTimeout.errorDescription)
        XCTAssertNotNil(FenceError.invalidRequest("bad").errorDescription)
        XCTAssertNotNil(FenceError.connectionFailed("refused").errorDescription)
        XCTAssertNotNil(FenceError.sessionLocked("busy").errorDescription)
        XCTAssertNotNil(FenceError.authFailed("denied").errorDescription)
    }

    func testActionTimeoutErrorDescriptionExplainsLikelyBusyApp() {
        let description = FenceError.actionTimeout.errorDescription ?? ""

        XCTAssertTrue(description.contains("waiting for a response"))
        XCTAssertTrue(description.contains("main thread"))
        XCTAssertTrue(description.contains("connection is preserved"))
    }

    @ButtonHeistActor
    func testDisconnectCancelsPendingActionWaitWithReason() async {
        let fence = TheFence()

        let waitTask = Task { @ButtonHeistActor in
            try await fence.waitForActionResult(requestId: "pending", timeout: 10)
        }
        await Task.yield()

        fence.handoff.onDisconnected?(.serverClosed)

        do {
            _ = try await waitTask.value
            XCTFail("Expected pending wait to fail")
        } catch FenceError.connectionFailed(let message) {
            XCTAssertTrue(message.contains("Connection closed by server"))
        } catch {
            XCTFail("Expected connectionFailed, got \(error)")
        }
    }

    @ButtonHeistActor
    func testDisconnectCancelsPendingRecordingWaitWithReason() async {
        let fence = TheFence()

        let waitTask = Task { @ButtonHeistActor in
            try await fence.waitForRecording(timeout: 10)
        }
        await Task.yield()

        fence.handoff.onDisconnected?(.serverClosed)

        do {
            _ = try await waitTask.value
            XCTFail("Expected pending recording wait to fail")
        } catch FenceError.connectionFailed(let message) {
            XCTAssertTrue(message.contains("Connection closed by server"))
        } catch {
            XCTFail("Expected connectionFailed, got \(error)")
        }
    }

    func testNoMatchingDeviceError() {
        let error = FenceError.noMatchingDevice(filter: "MyApp", available: ["OtherApp"])
        XCTAssertTrue(error.errorDescription?.contains("MyApp") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("OtherApp") ?? false)
    }

    func testNoMatchingDeviceErrorEmptyAvailable() {
        let error = FenceError.noMatchingDevice(filter: "MyApp", available: [])
        XCTAssertTrue(error.errorDescription?.contains("(none)") ?? false)
    }

    // MARK: - Timeouts

    func testTimeoutConstants() {
        XCTAssertEqual(Timeouts.actionSeconds, 15)
        XCTAssertEqual(Timeouts.longActionSeconds, 30)
    }

    // MARK: - TheFence execute (error cases)

    @ButtonHeistActor
    func testExecuteWithMissingCommand() async {
        let fence = TheFence()
        do {
            _ = try await fence.execute(request: [:])
            XCTFail("Expected FenceError.invalidRequest")
        } catch let error as FenceError {
            if case .invalidRequest = error {
                // Expected
            } else {
                XCTFail("Expected invalidRequest, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    @ButtonHeistActor
    func testExecuteHelp() async throws {
        let fence = TheFence()
        let response = try await fence.execute(request: ["command": "help"])
        if case .help(let commands) = response {
            XCTAssertFalse(commands.isEmpty)
            XCTAssertTrue(commands.contains("one_finger_tap"))
        } else {
            XCTFail("Expected help response, got \(response)")
        }
    }

    @ButtonHeistActor
    func testExecuteQuit() async throws {
        let fence = TheFence()
        let response = try await fence.execute(request: ["command": "quit"])
        if case .ok(let message) = response {
            XCTAssertEqual(message, "bye")
        } else {
            XCTFail("Expected ok(bye), got \(response)")
        }
    }

    @ButtonHeistActor
    func testGetSessionStateDoesNotConnectWhenDisconnected() async throws {
        let device = DiscoveredDevice(
            id: "mock-device",
            name: "MockApp#test",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 1),
            certFingerprint: "sha256:mock"
        )
        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [device]
        let mockConnection = MockConnection()

        let fence = TheFence()
        fence.handoff.makeDiscovery = { mockDiscovery }
        fence.handoff.makeConnection = { _, _, _ in mockConnection }

        let response = try await fence.execute(request: ["command": "get_session_state"])

        if case .sessionState(let payload) = response {
            XCTAssertEqual(payload["connected"] as? Bool, false)
        } else {
            XCTFail("Expected sessionState response, got \(response)")
        }

        XCTAssertEqual(mockDiscovery.startCount, 0)
        XCTAssertEqual(mockConnection.connectCount, 0)
    }

    // MARK: - BookKeeper Command Dispatch

    @ButtonHeistActor
    func testExecuteGetSessionLogReturnsErrorWhenIdle() async throws {
        let fence = TheFence()
        let response = try await fence.execute(request: ["command": "get_session_log"])
        if case .error(let message) = response {
            XCTAssertTrue(message.contains("No active session"))
        } else {
            XCTFail("Expected error response when no session active, got \(response)")
        }
    }

    @ButtonHeistActor
    func testExecuteArchiveSessionReturnsErrorWhenIdle() async throws {
        let fence = TheFence()
        do {
            _ = try await fence.execute(request: ["command": "archive_session"])
            XCTFail("Expected error for archive_session when idle")
        } catch let error as BookKeeperError {
            if case .invalidPhase = error {
                // expected — archiveSession requires closed phase
            } else {
                XCTFail("Expected invalidPhase, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testExecuteArchiveSessionAutoClosesActiveSession() async throws {
        let fence = TheFence()
        try fence.bookKeeper.beginSession(identifier: "archive-auto-close")
        try fence.bookKeeper.logCommand(requestId: "r1", command: .status, arguments: [:])

        let response = try await fence.execute(request: ["command": "archive_session"])

        guard case .archiveResult(let path, let manifest) = response else {
            return XCTFail("Expected archiveResult response, got \(response)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        // 2 = the explicit status call above + the archive_session request,
        // which execute() logs before dispatching to the handler.
        XCTAssertEqual(manifest.commandCount, 2)
        if case .archived = fence.bookKeeper.phase {
            // expected
        } else {
            XCTFail("Expected archived phase after archive_session, got \(fence.bookKeeper.phase)")
        }

        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Wait Method Tests

    @ButtonHeistActor
    func testWaitForRecordingSuccess() async throws {
        let fence = TheFence()
        let expectedPayload = RecordingPayload(
            videoData: "dGVzdA==", width: 390, height: 844,
            duration: 2.0, frameCount: 16, fps: 8,
            startTime: Date(), endTime: Date(), stopReason: .manual
        )

        Task { @ButtonHeistActor in
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
            fence.handoff.onRecording?(expectedPayload)
        }

        let result = try await fence.waitForRecording(timeout: 1.0)
        XCTAssertEqual(result.videoData, expectedPayload.videoData)
        XCTAssertEqual(result.width, expectedPayload.width)
        XCTAssertEqual(result.duration, expectedPayload.duration)
    }

    @ButtonHeistActor
    func testWaitForRecordingServerError() async throws {
        let fence = TheFence()

        Task { @ButtonHeistActor in
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
            fence.handoff.onRecordingError?("disk full")
        }

        do {
            _ = try await fence.waitForRecording(timeout: 1.0)
            XCTFail("Expected FenceError.actionFailed to be thrown")
        } catch let error as FenceError {
            if case .actionFailed(let msg) = error {
                XCTAssertTrue(msg.contains("disk full"), "Expected message to contain 'disk full', got: \(msg)")
            } else {
                XCTFail("Expected FenceError.actionFailed, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testWaitForRecordingTimeout() async throws {
        let fence = TheFence()

        do {
            _ = try await fence.waitForRecording(timeout: 0.05)
            XCTFail("Expected FenceError.actionTimeout to be thrown")
        } catch let error as FenceError {
            guard case .actionTimeout = error else {
                return XCTFail("Expected FenceError.actionTimeout, got \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testWaitForRecordingRestoresCallbacks() async throws {
        let fence = TheFence()
        XCTAssertNil(fence.handoff.onRecording)
        XCTAssertNil(fence.handoff.onRecordingError)

        do {
            _ = try await fence.waitForRecording(timeout: 0.05)
        } catch {
            // Expected timeout
        }

        XCTAssertNil(fence.handoff.onRecording, "onRecording should be restored to nil after waitForRecording")
        XCTAssertNil(fence.handoff.onRecordingError, "onRecordingError should be restored to nil after waitForRecording")
    }

    @ButtonHeistActor
    func testWaitForRecordingRejectsConcurrentWaiters() async {
        let fence = TheFence()

        let firstWait = Task { @ButtonHeistActor in
            try await fence.waitForRecording(timeout: 5.0)
        }
        await Task.yield()

        do {
            _ = try await fence.waitForRecording(timeout: 0.1)
            XCTFail("Expected invalidRequest for concurrent waitForRecording")
        } catch let error as FenceError {
            guard case .invalidRequest(let message) = error else {
                return XCTFail("Expected invalidRequest, got \(error)")
            }
            XCTAssertTrue(
                message.contains("already waiting for completion"),
                "Expected concurrent wait message, got: \(message)"
            )
        } catch {
            XCTFail("Expected FenceError.invalidRequest, got \(error)")
        }

        firstWait.cancel()
        do {
            _ = try await firstWait.value
            XCTFail("Expected first waiter cancellation")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    @ButtonHeistActor
    func testListDevicesFiltersOutUnreachableDevicesWithoutConnecting() async throws {
        let reachableDevice = DiscoveredDevice(
            id: "reachable-device",
            name: "ReachableApp#live",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 1),
            certFingerprint: "sha256:reachable"
        )
        let staleDevice = DiscoveredDevice(
            id: "stale-device",
            name: "StaleApp#dead",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 2),
            certFingerprint: "sha256:stale"
        )

        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [reachableDevice, staleDevice]
        let mockConnection = MockConnection()

        let fence = TheFence()
        fence.handoff.makeDiscovery = { mockDiscovery }
        fence.handoff.makeConnection = { _, _, _ in mockConnection }

        let previousFactory = makeReachabilityConnection
        makeReachabilityConnection = { device in
            let connection = MockConnection()
            connection.emitTransportReadyOnConnect = true
            if device.id == reachableDevice.id {
                connection.autoResponse = { message in
                    switch message {
                    case .status:
                        return .status(StatusPayload(
                            identity: StatusIdentity(
                                appName: "ReachableApp",
                                bundleIdentifier: "com.test.reachable",
                                appBuild: "1",
                                deviceName: "Simulator",
                                systemVersion: "18.5",
                                buttonHeistVersion: "5.0"
                            ),
                            session: StatusSession(active: false, watchersAllowed: false, activeConnections: 0)
                        ))
                    default:
                        XCTFail("Unexpected probe message: \(message)")
                        return .error("unexpected")
                    }
                }
            }
            return connection
        }
        defer { makeReachabilityConnection = previousFactory }

        let response = try await fence.execute(request: ["command": "list_devices"])

        if case .devices(let devices) = response {
            XCTAssertEqual(devices, [reachableDevice])
        } else {
            XCTFail("Expected devices response, got \(response)")
        }

        XCTAssertEqual(mockDiscovery.startCount, 1)
        XCTAssertEqual(mockDiscovery.stopCount, 1)
        XCTAssertEqual(mockConnection.connectCount, 0)
    }

    // MARK: - Background Delta

    @ButtonHeistActor
    func testDrainBackgroundDeltaReturnsNilWhenEmpty() async {
        let fence = TheFence()
        XCTAssertNil(fence.drainBackgroundDelta())
    }

    @ButtonHeistActor
    func testDrainBackgroundDeltaClearsAfterRead() async {
        let fence = TheFence()
        // Simulate a background delta arriving via the handoff callback
        let delta = InterfaceDelta(kind: .screenChanged, elementCount: 7)
        fence.handoff.onBackgroundDelta?(delta)

        let first = fence.drainBackgroundDelta()
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.kind, .screenChanged)
        XCTAssertEqual(first?.elementCount, 7)

        let second = fence.drainBackgroundDelta()
        XCTAssertNil(second)
    }

    @ButtonHeistActor
    func testExpectationShortCircuitOnBackgroundDelta() async throws {
        let device = DiscoveredDevice(
            id: "mock-device",
            name: "MockApp#test",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 1),
            certFingerprint: "sha256:mock"
        )
        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [device]
        let mockConnection = MockConnection()
        mockConnection.serverInfo = ServerInfo(
            protocolVersion: protocolVersion,
            appName: "MockApp", bundleIdentifier: "com.test",
            deviceName: "Sim", systemVersion: "18.0",
            screenWidth: 390, screenHeight: 844
        )

        let fence = TheFence()
        fence.handoff.makeDiscovery = { mockDiscovery }
        fence.handoff.makeConnection = { _, _, _ in mockConnection }

        // Simulate a screen-changed background delta
        let element = HeistElement(
            description: "Button", label: "New Order", value: nil, identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44, actions: [.activate]
        )
        let fullInterface = Interface(timestamp: Date(), elements: [element])
        let delta = InterfaceDelta(
            kind: .screenChanged, elementCount: 1, newInterface: fullInterface
        )
        fence.handoff.onBackgroundDelta?(delta)

        // Execute an action with expect=screen_changed — should short-circuit
        let response = try await fence.execute(request: [
            "command": "activate",
            "heistId": "stale_button",
            "expect": "screen_changed",
        ])

        // Should return success with "already met" rather than elementNotFound
        if case .action(let result, let expectation) = response {
            XCTAssertTrue(result.success)
            XCTAssertEqual(result.message, "expectation already met by background change")
            XCTAssertNotNil(expectation)
            XCTAssertEqual(expectation?.met, true)
            XCTAssertEqual(mockDiscovery.startCount, 0, "Short-circuit should avoid discovery")
            XCTAssertEqual(mockConnection.connectCount, 0, "Short-circuit should avoid connection")
        } else {
            XCTFail("Expected action response, got \(response)")
        }
    }

    @ButtonHeistActor
    func testNoShortCircuitWithoutExpectation() async throws {
        let fence = TheFence()

        // Background delta present but no expectation on the action
        let delta = InterfaceDelta(kind: .screenChanged, elementCount: 3)
        fence.handoff.onBackgroundDelta?(delta)

        // Action without expect — should NOT short-circuit, should try to connect
        do {
            _ = try await fence.execute(request: [
                "command": "activate",
                "heistId": "some_button",
            ])
            XCTFail("Expected connection error")
        } catch {
            // Expected — no connection, but the point is it didn't short-circuit
        }
    }

    // MARK: - Action Timeout Preserves Connection

    /// An action timeout means "this single command took too long" — it does not
    /// mean the connection is dead. The keepalive task (TheHandoff) is the sole
    /// liveness signal. A 15s action timeout used to call `forceDisconnect`,
    /// killing a healthy connection and forcing a reconnect cycle for every
    /// slow-settling screen transition. That behavior is gone.
    @ButtonHeistActor
    func testActionTimeoutDoesNotForceDisconnect() async throws {
        let device = DiscoveredDevice(
            id: "timeout-device",
            name: "MockApp#timeout",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 1),
            certFingerprint: "sha256:mock"
        )
        let mockConnection = MockConnection()
        let fence = TheFence()
        fence.handoff.makeConnection = { _, _, _ in mockConnection }
        fence.handoff.connect(to: device)

        XCTAssertTrue(fence.handoff.isConnected, "Precondition: handoff should be connected")
        XCTAssertTrue(mockConnection.isConnected, "Precondition: underlying connection should be live")

        let activate = ClientMessage.activate(.heistId("never-answered"))
        do {
            _ = try await fence.sendAndAwaitAction(activate, timeout: 0.05)
            XCTFail("Expected FenceError.actionTimeout to be thrown")
        } catch let error as FenceError {
            guard case .actionTimeout = error else {
                return XCTFail("Expected .actionTimeout, got \(error)")
            }
        }

        XCTAssertTrue(
            fence.handoff.isConnected,
            "Action timeout must not tear down the handoff — keepalive owns liveness"
        )
        XCTAssertTrue(
            mockConnection.isConnected,
            "Underlying NWConnection-equivalent must not be disconnected on action timeout"
        )
    }

    /// After an action times out, the next action on the same socket should go
    /// straight through. No reconnect cycle, no extra discovery, no new
    /// connection — the existing socket is reused.
    @ButtonHeistActor
    func testSubsequentActionAfterTimeoutReusesConnection() async throws {
        let device = DiscoveredDevice(
            id: "reuse-device",
            name: "MockApp#reuse",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 1),
            certFingerprint: "sha256:mock"
        )
        let mockConnection = MockConnection()
        let fence = TheFence()
        fence.handoff.makeConnection = { _, _, _ in mockConnection }
        fence.handoff.connect(to: device)

        let connectCountAfterInitial = mockConnection.connectCount

        do {
            _ = try await fence.sendAndAwaitAction(.activate(.heistId("first")), timeout: 0.05)
            XCTFail("Expected first action to time out")
        } catch let error as FenceError {
            guard case .actionTimeout = error else {
                return XCTFail("Expected .actionTimeout, got \(error)")
            }
        }

        XCTAssertEqual(
            mockConnection.connectCount,
            connectCountAfterInitial,
            "No reconnect should occur after an action timeout"
        )
        XCTAssertTrue(
            fence.handoff.isConnected,
            "Handoff must still report connected so a follow-up action can be sent"
        )

        // The next send must reach the live socket. A force-disconnect would
        // have flipped isConnected to false and the next sendAndAwait would
        // throw .notConnected before even hitting the wire.
        let sendCountBefore = mockConnection.sent.count
        do {
            _ = try await fence.sendAndAwaitAction(.activate(.heistId("second")), timeout: 0.05)
        } catch let error as FenceError {
            guard case .actionTimeout = error else {
                return XCTFail("Second action should also time out (no auto-response wired), got \(error)")
            }
        }
        XCTAssertEqual(
            mockConnection.sent.count,
            sendCountBefore + 1,
            "Second action must have been sent on the same connection — proves no reconnect detour"
        )
    }
}
