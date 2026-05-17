import XCTest
@testable import ButtonHeist
import TheScore

final class TheFenceTests: XCTestCase {

    // MARK: - Command Enum

    // MARK: - Element Matcher Validation

    @ButtonHeistActor
    func testElementMatcherRejectsUnknownTrait() async {
        let fence = TheFence(configuration: .init())
        let args: [String: Any] = ["traits": ["madeUpTrait"]]
        let expectedError = "schema validation failed for traits[0]: observed string \"madeUpTrait\"; " +
            "expected enum one of \(HeistTrait.allCases.map(\.rawValue).joined(separator: ", "))"
        XCTAssertThrowsError(try fence.elementMatcher(args)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                expectedError
            )
        }
    }

    @ButtonHeistActor
    func testElementMatcherRejectsUnknownExcludeTrait() async {
        let fence = TheFence(configuration: .init())
        let args: [String: Any] = ["excludeTraits": ["bogus"]]
        let expectedError = "schema validation failed for excludeTraits[0]: observed string \"bogus\"; " +
            "expected enum one of \(HeistTrait.allCases.map(\.rawValue).joined(separator: ", "))"
        XCTAssertThrowsError(try fence.elementMatcher(args)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                expectedError
            )
        }
    }

    @ButtonHeistActor
    func testElementMatcherAcceptsKnownTraits() async throws {
        let fence = TheFence(configuration: .init())
        let args: [String: Any] = ["traits": ["button", "header"], "excludeTraits": ["selected"]]
        let matcher = try fence.elementMatcher(args)
        XCTAssertEqual(matcher.traits, [.button, .header])
        XCTAssertEqual(matcher.excludeTraits, [.selected])
    }

    // MARK: - Command Enum

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
            .rotor: "rotor",
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

    func testFenceErrorDisplayMessageDoesNotSerializeFailureDetails() {
        let message = FenceError.connectionTimeout.displayMessage

        XCTAssertTrue(message.contains("Connection timed out"))
        XCTAssertTrue(message.contains("Hint:"))
        XCTAssertFalse(message.contains("Code: setup.timeout"))
        XCTAssertFalse(message.contains("retryable: true"))
    }

    func testFenceErrorFailureDetailsAreTyped() {
        let details = FenceError.connectionTimeout.failureDetails

        XCTAssertEqual(details.errorCode, "setup.timeout")
        XCTAssertEqual(details.phase, .setup)
        XCTAssertTrue(details.retryable)
        XCTAssertEqual(details.hint, "Is the app running? Check 'buttonheist list' to see available devices.")
    }

    func testCompactErrorResponseIncludesFailureDetailsConcisely() {
        let response = FenceResponse.failure(FenceError.actionTimeout)
        let text = response.compactFormatted()

        XCTAssertTrue(text.contains("error[request.timeout request retryable=true]"))
        XCTAssertTrue(text.contains("Command timed out"))
        XCTAssertTrue(text.contains("hint: The app may be busy"))
        XCTAssertTrue(text.contains("The connection is preserved; retry the command on the same session."))
        XCTAssertFalse(text.contains("The connection is preserved — retry"))
        XCTAssertFalse(text.contains("Code: request.timeout"))
    }

    func testCompactErrorResponsePreservesDelimitedHint() {
        let response = FenceResponse.error(
            "failed",
            details: FailureDetails(
                errorCode: "request.failed",
                phase: .request,
                retryable: false,
                hint: "retry | inspect logs"
            )
        )
        let text = response.compactFormatted()

        XCTAssertTrue(text.contains("error[request.failed request retryable=false]: failed"))
        XCTAssertTrue(text.contains("hint: retry | inspect logs"))
    }

    func testCompactSessionStateDistinguishesFailedFromDisconnected() {
        let failed = FenceResponse.sessionState(payload: [
            "status": "ok",
            "connected": false,
            "phase": "failed",
            "lastFailure": [
                "errorCode": "session.locked",
                "hint": "Reconnect after the active client releases the session.",
            ],
        ])
        let disconnected = FenceResponse.sessionState(payload: [
            "status": "ok",
            "connected": false,
            "phase": "disconnected",
        ])

        XCTAssertEqual(
            failed.compactFormatted(),
            "session: failed (session.locked): Reconnect after the active client releases the session."
        )
        XCTAssertEqual(disconnected.compactFormatted(), "session: not connected")
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

    func testErrorResponseJSONIncludesFailureDetailsWhenPresent() {
        let response = FenceResponse.failure(FenceError.authFailed("bad token"))
        let json = response.jsonDict()

        XCTAssertEqual(json?["status"] as? String, "error")
        let message = json?["message"] as? String
        XCTAssertTrue(message?.contains("Auth failed: bad token") == true)
        XCTAssertFalse(message?.contains("Retry without --token") == true)
        XCTAssertFalse(message?.contains("Code: auth.failed") == true)
        XCTAssertEqual(json?["errorCode"] as? String, "auth.failed")
        XCTAssertEqual(json?["phase"] as? String, "auth")
        XCTAssertEqual(json?["retryable"] as? Bool, false)
        XCTAssertEqual(json?["hint"] as? String, "Retry without --token to request a fresh session.")
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
        let containerInfo = ContainerInfo(
            type: .list,
            frameX: 0,
            frameY: 44,
            frameWidth: 390,
            frameHeight: 600
        )
        let interface = Interface(
            timestamp: Date(),
            tree: [
                .element(title),
                .container(containerInfo, children: [.element(wifi)]),
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

    func testSummaryInterfaceJSONKeepsIdentityAndDropsHeavyFields() {
        // Summary is the thin payload contract for agents polling the
        // interface: identity fields (heistId, label, value, identifier,
        // traits, actions) only. Heavy semantics (hint, customContent) and
        // geometry (frame*, activationPoint*) require `detail = full`.
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
            customContent: [
                HeistCustomContent(label: "Signal", value: "Strong", isImportant: true)
            ],
            actions: [.activate]
        )
        let containerInfo = ContainerInfo(
            type: .scrollable(contentWidth: 390, contentHeight: 1200),
            frameX: 0,
            frameY: 44,
            frameWidth: 390,
            frameHeight: 600
        )
        let interface = Interface(
            timestamp: Date(),
            tree: [.container(containerInfo, children: [.element(element)])]
        )

        let response = FenceResponse.interface(interface, detail: .summary)
        let json = response.jsonDict()!
        let interfaceDict = json["interface"] as! [String: Any]
        XCTAssertNil(interfaceDict["elements"])

        let tree = interfaceDict["tree"] as! [[String: Any]]
        let container = tree[0]["container"] as! [String: Any]
        XCTAssertEqual(container["type"] as? String, "scrollable")
        XCTAssertEqual(container["contentWidth"] as? Double, 390)
        XCTAssertEqual(container["contentHeight"] as? Double, 1200)
        XCTAssertNil(container["frameY"])

        let children = container["children"] as! [[String: Any]]
        let nestedElement = children[0]["element"] as! [String: Any]
        XCTAssertEqual(nestedElement["heistId"] as? String, "wifi_toggle")
        XCTAssertEqual(nestedElement["identifier"] as? String, "wifi")
        XCTAssertEqual(nestedElement["label"] as? String, "Wi-Fi")
        XCTAssertEqual(nestedElement["value"] as? String, "On")
        // Heavy semantics and geometry are full-only.
        XCTAssertNil(nestedElement["hint"])
        XCTAssertNil(nestedElement["customContent"])
        XCTAssertNil(nestedElement["frameY"])
        XCTAssertNil(nestedElement["activationPointY"])
    }

    func testFullInterfaceJSONIncludesHintAndCustomContent() {
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
            customContent: [
                HeistCustomContent(label: "Signal", value: "Strong", isImportant: true),
                HeistCustomContent(label: "Network", value: "Home", isImportant: false),
            ],
            actions: [.activate]
        )
        let interface = Interface(timestamp: Date(), tree: [.element(element)])

        let response = FenceResponse.interface(interface, detail: .full)
        let json = response.jsonDict()!
        let interfaceDict = json["interface"] as! [String: Any]
        let tree = interfaceDict["tree"] as! [[String: Any]]
        let nestedElement = tree[0]["element"] as! [String: Any]

        XCTAssertEqual(nestedElement["hint"] as? String, "Double tap to toggle")
        let customContent = nestedElement["customContent"] as? [String: Any]
        XCTAssertNotNil(customContent)
        XCTAssertNotNil(customContent?["important"])
        XCTAssertNotNil(customContent?["default"])
        XCTAssertEqual(nestedElement["frameY"] as? Double, 44)
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
        let containerInfo = ContainerInfo(
            type: .scrollable(contentWidth: 390, contentHeight: 1200),
            frameX: 0,
            frameY: 44,
            frameWidth: 390,
            frameHeight: 600
        )
        let interface = Interface(
            timestamp: Date(),
            tree: [.container(containerInfo, children: [.element(element)])]
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
        let containerInfo = ContainerInfo(
            type: .scrollable(contentWidth: 390, contentHeight: 1200),
            frameX: 0,
            frameY: 44,
            frameWidth: 390,
            frameHeight: 600
        )
        let interface = Interface(
            timestamp: Date(),
            tree: [.container(containerInfo, children: [.element(element)])]
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
        let result = ActionResult(success: true, method: .activate, accessibilityDelta: .noChange(.init(elementCount: 5)))
        let expectation = ExpectationResult(met: false, expectation: .screenChanged, actual: "noChange")
        let response = FenceResponse.action(result: result, expectation: expectation)
        let text = response.humanFormatted()
        XCTAssertTrue(text.contains("[expectation FAILED"))
        XCTAssertTrue(text.contains("noChange"))
    }

    func testCompactScreenChangedExpectationFailureIncludesGuidance() {
        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityDelta: .elementsChanged(.init(elementCount: 5, edits: ElementEdits()))
        )
        let expectation = ExpectationResult(met: false, expectation: .screenChanged, actual: "elementsChanged")
        let response = FenceResponse.action(result: result, expectation: expectation)
        let text = response.compactFormatted()

        XCTAssertTrue(text.contains("[expectation FAILED: got elementsChanged]"))
        XCTAssertTrue(text.contains("hint: screen_changed requires a screen-level transition"))
        XCTAssertTrue(text.contains("use elements_changed for same-screen element updates"))
    }

    func testActionWithDeliveryFailureFormatting() {
        let result = ActionResult(success: false, method: .activate, message: "not found")
        let expectation = ExpectationResult(met: false, expectation: nil, actual: "not found")
        let response = FenceResponse.action(result: result, expectation: expectation)
        let text = response.humanFormatted()
        XCTAssertTrue(text.contains("[expectation FAILED"))
        XCTAssertTrue(text.contains("delivery"))
    }

    func testCompactFailedActionIncludesMethodAndElementNotFoundKind() {
        let result = ActionResult(
            success: false,
            method: .activate,
            message: "No element matching label \"Buy\"",
            errorKind: .elementNotFound
        )

        let text = FenceResponse.action(result: result).compactFormatted()

        XCTAssertEqual(text, "activate: error[elementNotFound]: No element matching label \"Buy\"")
    }

    func testCompactFailedActionIncludesMethodAndTimeoutKind() {
        let result = ActionResult(
            success: false,
            method: .waitFor,
            message: "Timed out after 2.0s waiting for element",
            errorKind: .timeout,
            screenId: "checkout"
        )

        let text = FenceResponse.action(result: result).compactFormatted()

        XCTAssertEqual(text, "checkout | waitFor: error[timeout]: Timed out after 2.0s waiting for element")
    }

    func testCompactTreeUnavailableActionUsesLocalDiagnosticCode() {
        let result = ActionResult(
            success: false,
            method: .waitFor,
            message: "Could not access accessibility tree: no traversable app windows",
            errorKind: .actionFailed
        )

        let text = FenceResponse.action(result: result).compactFormatted()

        XCTAssertEqual(
            text,
            "waitFor: error[request.accessibility_tree_unavailable]: Could not access accessibility tree: no traversable app windows"
        )
    }

    func testActionWithoutExpectationFormatting() {
        let result = ActionResult(success: true, method: .activate)
        let response = FenceResponse.action(result: result)
        let text = response.humanFormatted()
        XCTAssertFalse(text.contains("expectation"))
    }

    func testCompactElementSearchFormattingUsesElementSearchCommandName() {
        let foundElement = HeistElement(
            heistId: "long_list_button",
            description: "Long List",
            label: "Long List",
            value: nil,
            identifier: nil,
            traits: [.button],
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: [.activate]
        )
        let search = ScrollSearchResult(
            scrollCount: 1,
            uniqueElementsSeen: 29,
            exhaustive: false,
            foundElement: foundElement
        )
        let result = ActionResult(
            success: true,
            method: .elementSearch,
            payload: .scrollSearch(search)
        )

        let text = FenceResponse.action(result: result).compactFormatted()

        XCTAssertTrue(text.contains("element_search: found after 1 scrolls (29 unique elements seen)"))
        XCTAssertTrue(text.contains("long_list_button \"Long List\" [button]"))
        XCTAssertFalse(text.contains("scroll_to_visible"))
    }

    func testCompactElementSearchFailureFormattingUsesElementSearchCommandName() {
        let search = ScrollSearchResult(
            scrollCount: 3,
            uniqueElementsSeen: 42,
            exhaustive: false
        )
        let result = ActionResult(
            success: false,
            method: .elementSearch,
            payload: .scrollSearch(search),
            screenId: "buttonheist_demo"
        )

        let text = FenceResponse.action(result: result).compactFormatted()

        XCTAssertEqual(text, "buttonheist_demo | element_search: error[elementNotFound]: not found after 3 scrolls (42 unique elements seen)")
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

    func testTreeUnavailableActionJSONIncludesLocalDiagnosticDetails() {
        let result = ActionResult(
            success: false,
            method: .explore,
            message: "Could not access accessibility tree: no traversable app windows",
            errorKind: .actionFailed
        )
        let response = FenceResponse.action(result: result)

        let json = response.jsonDict()!

        XCTAssertEqual(json["status"] as? String, "error")
        XCTAssertEqual(json["errorClass"] as? String, "actionFailed")
        XCTAssertEqual(json["errorCode"] as? String, "request.accessibility_tree_unavailable")
        XCTAssertEqual(json["phase"] as? String, "request")
        XCTAssertEqual(json["retryable"] as? Bool, true)
        XCTAssertTrue((json["hint"] as? String)?.contains("traversable app window") == true)
    }

    func testTreeUnavailableActionWithNilErrorKindStillUsesLocalDiagnosticDetails() {
        let result = ActionResult(
            success: false,
            method: .waitFor,
            message: "Could not access accessibility tree: no traversable app windows",
            errorKind: nil
        )

        let details = FenceResponse.actionFailureDetails(result)
        let compact = FenceResponse.action(result: result).compactFormatted()
        let json = FenceResponse.action(result: result).jsonDict()!

        XCTAssertEqual(details?.errorCode, "request.accessibility_tree_unavailable")
        XCTAssertEqual(
            compact,
            "waitFor: error[request.accessibility_tree_unavailable]: Could not access accessibility tree: no traversable app windows"
        )
        XCTAssertEqual(json["errorClass"] as? String, "actionFailed")
        XCTAssertEqual(json["errorCode"] as? String, "request.accessibility_tree_unavailable")
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
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 3, edits: ElementEdits(updated: [
                ElementUpdate(heistId: "okBtn", changes: [
                    PropertyChange(property: .value, old: "0", new: "1"),
                    PropertyChange(property: .frame, old: "10,20,100,44", new: "10,25,100,44"),
                ]),
            ])))
        let output = FenceResponse.compactDelta(delta, method: "tap")
        XCTAssertTrue(output.contains("value"), "Value change should appear")
        XCTAssertFalse(output.contains("frame"), "Frame change should be filtered")
    }

    func testCompactDeltaOmitsActivationPointChanges() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 2, edits: ElementEdits(updated: [
                ElementUpdate(heistId: "slider", changes: [
                    PropertyChange(property: .activationPoint, old: "50,22", new: "55,22"),
                ]),
            ])))
        let output = FenceResponse.compactDelta(delta, method: "drag")
        XCTAssertFalse(output.contains("activationPoint"), "ActivationPoint should be filtered")
        XCTAssertFalse(output.contains("~"), "No ~ lines when only geometry changed")
    }

    func testCompactDeltaKeepsNonGeometryChanges() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 4, edits: ElementEdits(updated: [
                ElementUpdate(heistId: "toggle", changes: [
                    PropertyChange(property: .value, old: "off", new: "on"),
                    PropertyChange(property: .traits, old: "button", new: "button, selected"),
                    PropertyChange(property: .frame, old: "0,0,100,44", new: "0,5,100,44"),
                ]),
            ])))
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
        XCTAssertFalse(ElementProperty.rotors.isGeometry)
    }

    // MARK: - JSON Delta Geometry Filtering

    func testActionJsonDeltaOmitsGeometryByDefault() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 2, edits: ElementEdits(updated: [
                ElementUpdate(heistId: "label1", changes: [
                    PropertyChange(property: .frame, old: "0,0,100,44", new: "0,10,100,44"),
                    PropertyChange(property: .value, old: "a", new: "b"),
                ]),
            ])))
        let result = ActionResult(success: true, method: .activate, accessibilityDelta: delta)
        let response = FenceResponse.action(result: result)
        let json = response.jsonDict()!
        let deltaDict = json["delta"] as! [String: Any]
        let editsDict = deltaDict["edits"] as! [String: Any]
        let updated = editsDict["updated"] as! [[String: Any]]
        XCTAssertEqual(updated.count, 1)
        let changes = updated[0]["changes"] as! [[String: Any]]
        let properties = changes.map { $0["property"] as! String }
        XCTAssertTrue(properties.contains("value"))
        XCTAssertFalse(properties.contains("frame"))
    }

    func testActionJsonDeltaDropsGeometryOnlyUpdates() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 3, edits: ElementEdits(updated: [
                ElementUpdate(heistId: "img", changes: [
                    PropertyChange(property: .frame, old: "0,0,50,50", new: "0,5,50,50"),
                    PropertyChange(property: .activationPoint, old: "25,25", new: "25,30"),
                ]),
            ])))
        let result = ActionResult(success: true, method: .activate, accessibilityDelta: delta)
        let response = FenceResponse.action(result: result)
        let json = response.jsonDict()!
        let deltaDict = json["delta"] as! [String: Any]
        // Geometry-only updates are dropped — and with no other edits, the
        // entire `edits` key is omitted from the delta dictionary.
        XCTAssertNil(deltaDict["edits"], "Geometry-only updates should be dropped entirely")
    }

    func testActionJsonDeltaIncludesCaptureEdge() {
        let edge = AccessibilityTrace.CaptureEdge(
            before: AccessibilityTrace.CaptureRef(sequence: 1, hash: "sha256:before"),
            after: AccessibilityTrace.CaptureRef(sequence: 2, hash: "sha256:after")
        )
        let delta = AccessibilityTrace.Delta.noChange(.init(elementCount: 3, captureEdge: edge))
        let result = ActionResult(success: true, method: .activate, accessibilityDelta: delta)
        let response = FenceResponse.action(result: result)
        let json = response.jsonDict()!
        let deltaDict = json["delta"] as! [String: Any]
        let edgeDict = deltaDict["captureEdge"] as! [String: Any]
        let before = edgeDict["before"] as! [String: Any]
        let after = edgeDict["after"] as! [String: Any]

        XCTAssertEqual(before["sequence"] as? Int, 1)
        XCTAssertEqual(before["hash"] as? String, "sha256:before")
        XCTAssertEqual(after["sequence"] as? Int, 2)
        XCTAssertEqual(after["hash"] as? String, "sha256:after")
    }

    // MARK: - JSON Delta Tree Insertion Shape

    /// Pin the wire shape of `deltaNodeDictionary` so the `folded()`
    /// catamorphism refactor (and any future rewrite) can't silently regress.
    /// Tree insertions are serialized at summary detail: identity fields are
    /// kept, heavy semantics (hint, customContent) and geometry are dropped,
    /// and nested containers recurse through the same fold.
    func testActionResultDeltaInsertionPreservesNodeShape() {
        let leafElement = HeistElement(
            heistId: "child_leaf",
            description: "Leaf",
            label: "Leaf",
            value: "v",
            identifier: "leaf_id",
            hint: "should be dropped",
            traits: [.button],
            frameX: 0,
            frameY: 100,
            frameWidth: 50,
            frameHeight: 30,
            customContent: [
                HeistCustomContent(label: "Drop", value: "Me", isImportant: true)
            ],
            actions: [.custom("Inspect")]
        )
        let nestedContainerInfo = ContainerInfo(
            type: .list,
            frameX: 0,
            frameY: 0,
            frameWidth: 200,
            frameHeight: 400
        )
        let outerContainerInfo = ContainerInfo(
            type: .semanticGroup(label: "Outer", value: nil, identifier: nil),
            frameX: 0,
            frameY: 0,
            frameWidth: 300,
            frameHeight: 500
        )
        let outerNode: InterfaceNode = .container(outerContainerInfo, children: [
            .element(leafElement),
            .container(nestedContainerInfo, children: [
                .element(leafElement),
            ]),
        ])

        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(
            elementCount: 3,
            edits: ElementEdits(treeInserted: [
                TreeInsertion(
                    location: TreeLocation(parentId: nil, index: 0),
                    node: outerNode
                ),
            ])
        ))
        let result = ActionResult(success: true, method: .activate, accessibilityDelta: delta)
        let response = FenceResponse.action(result: result)
        let json = response.jsonDict()!

        let deltaDict = json["delta"] as! [String: Any]
        let editsDict = deltaDict["edits"] as! [String: Any]
        let treeInserted = editsDict["treeInserted"] as! [[String: Any]]
        XCTAssertEqual(treeInserted.count, 1)

        let insertion = treeInserted[0]
        XCTAssertNotNil(insertion["location"], "TreeInsertion carries a location wrapper")
        let nodeDict = insertion["node"] as! [String: Any]

        // Top-level node is a container: `{"container": {type, children, …}}`.
        let outerContainer = nodeDict["container"] as! [String: Any]
        XCTAssertEqual(outerContainer["type"] as? String, "semanticGroup")
        XCTAssertEqual(outerContainer["label"] as? String, "Outer")
        // Summary detail: container frames are dropped.
        XCTAssertNil(outerContainer["frameX"])
        XCTAssertNil(outerContainer["frameWidth"])

        let outerChildren = outerContainer["children"] as! [[String: Any]]
        XCTAssertEqual(outerChildren.count, 2)

        // Child 0: leaf element keyed under "element".
        let childElement = outerChildren[0]["element"] as! [String: Any]
        XCTAssertEqual(childElement["heistId"] as? String, "child_leaf")
        XCTAssertEqual(childElement["label"] as? String, "Leaf")
        XCTAssertEqual(childElement["value"] as? String, "v")
        XCTAssertEqual(childElement["identifier"] as? String, "leaf_id")
        XCTAssertNotNil(childElement["traits"])
        XCTAssertNotNil(childElement["actions"])
        // Summary drops heavy semantics and geometry.
        XCTAssertNil(childElement["hint"])
        XCTAssertNil(childElement["customContent"])
        XCTAssertNil(childElement["frameX"])
        XCTAssertNil(childElement["frameY"])
        XCTAssertNil(childElement["frameWidth"])
        XCTAssertNil(childElement["frameHeight"])
        XCTAssertNil(childElement["activationPointX"])
        XCTAssertNil(childElement["activationPointY"])
        // Delta nodes carry no traversal-order index.
        XCTAssertNil(childElement["order"])

        // Child 1: nested container recurses through the same fold.
        let nestedContainer = outerChildren[1]["container"] as! [String: Any]
        XCTAssertEqual(nestedContainer["type"] as? String, "list")
        XCTAssertNil(nestedContainer["frameX"])
        let nestedChildren = nestedContainer["children"] as! [[String: Any]]
        XCTAssertEqual(nestedChildren.count, 1)
        let nestedLeaf = nestedChildren[0]["element"] as! [String: Any]
        XCTAssertEqual(nestedLeaf["heistId"] as? String, "child_leaf")
        XCTAssertNil(nestedLeaf["hint"])
        XCTAssertNil(nestedLeaf["frameX"])
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
        XCTAssertNotNil(FenceError.serverError(ServerError(kind: .general, message: "boom")).errorDescription)
    }

    func testActionTimeoutErrorDescriptionExplainsLikelyBusyApp() {
        let description = FenceError.actionTimeout.errorDescription ?? ""

        XCTAssertTrue(description.contains("waiting for a response"))
        XCTAssertTrue(description.contains("main thread"))
        XCTAssertTrue(description.contains("connection is preserved"))
    }

    func testActionTimeoutCoreMessageLeavesRecoveryGuidanceInHint() {
        XCTAssertEqual(
            FenceError.actionTimeout.coreMessage,
            "Command timed out waiting for a response from the app."
        )
        XCTAssertFalse(FenceError.actionTimeout.coreMessage.contains("main thread"))
        XCTAssertTrue(FenceError.actionTimeout.failureDetails.hint?.contains("main thread") == true)
        XCTAssertTrue(FenceError.actionTimeout.failureDetails.hint?.contains("same session") == true)
    }

    func testSessionLockedFormattingIncludesDiagnosticsAndRecovery() {
        let payload = SessionLockedPayload(
            message: "Session is locked; owner driver id: driver-a; active connections: 0; remaining timeout: 8s.",
            activeConnections: 0
        )
        let response = FenceResponse.failure(FenceError.sessionLocked(payload.message))

        let compact = response.compactFormatted()
        XCTAssertTrue(compact.contains("owner driver id: driver-a"))
        XCTAssertTrue(compact.contains("active connections: 0"))
        XCTAssertTrue(compact.contains("remaining timeout: 8s"))
        XCTAssertTrue(compact.contains("hint: Wait for the current driver"))
        XCTAssertTrue(compact.contains("BUTTONHEIST_DRIVER_ID"))

        let json = response.jsonDict()
        XCTAssertEqual(json?["errorCode"] as? String, "session.locked")
        XCTAssertTrue((json?["message"] as? String)?.contains("owner driver id: driver-a") == true)
        XCTAssertTrue((json?["message"] as? String)?.contains("remaining timeout: 8s") == true)
        XCTAssertTrue((json?["hint"] as? String)?.contains("BUTTONHEIST_DRIVER_ID") == true)
    }

    func testFenceErrorTaxonomy() {
        let cases: [(FenceError, String, FailurePhase, Bool, String?)] = [
            (.invalidRequest("bad"), "request.invalid", .request, false, "Fix the request"),
            (.noDeviceFound, "discovery.no_device_found", .discovery, true, "Start the app"),
            (
                .noMatchingDevice(filter: "Demo", available: ["Other"]),
                "discovery.no_matching_device", .discovery, false, "Check the device filter"
            ),
            (.connectionTimeout, "setup.timeout", .setup, true, "buttonheist list"),
            (.connectionFailed("refused"), "connection.failed", .transport, true, "buttonheist list"),
            (
                .connectionFailure(ConnectionFailure(disconnectReason: .missingFingerprint)),
                "tls.missing_fingerprint", .tls, false, "TLS certificate fingerprint"
            ),
            (.sessionLocked("busy"), "session.locked", .session, true, "current driver"),
            (.authFailed("denied"), "auth.failed", .authentication, false, "without --token"),
            (.notConnected, "connection.not_connected", .request, true, "retry the command"),
            (.actionTimeout, "request.timeout", .request, true, "same session"),
            (.actionFailed("boom"), "request.action_failed", .request, false, nil),
        ]

        for (error, code, phase, retryable, hintFragment) in cases {
            XCTAssertEqual(error.errorCode, code)
            XCTAssertEqual(error.phase, phase)
            XCTAssertEqual(error.retryable, retryable)
            if let hintFragment {
                XCTAssertTrue(
                    error.hint?.contains(hintFragment) == true,
                    "Expected hint for \(error) to contain \(hintFragment), got \(String(describing: error.hint))"
                )
            } else {
                XCTAssertNil(error.hint)
            }
        }
    }

    func testServerErrorTaxonomyMapsErrorKind() {
        let cases: [(ErrorKind, String, FailurePhase, Bool, String?)] = [
            (.elementNotFound, "request.element_not_found", .request, false, "Refresh the interface"),
            (.timeout, "request.timeout", .request, true, "timed out"),
            (.unsupported, "request.unsupported", .request, false, "supported command"),
            (.inputError, "request.input_error", .request, false, "request input"),
            (.validationError, "request.validation_error", .request, false, "validation rules"),
            (.actionFailed, "request.action_failed", .request, false, nil),
            (.authFailure, "auth.failed", .authentication, false, "fresh session"),
            (.recording, "recording.failed", .recording, false, "recording error"),
            (.general, "server.general", .server, false, nil),
        ]

        for (kind, code, phase, retryable, hintFragment) in cases {
            let error = ServerError(kind: kind, message: "boom")
            XCTAssertEqual(error.errorCode, code)
            XCTAssertEqual(error.phase, phase)
            XCTAssertEqual(error.retryable, retryable)
            if let hintFragment {
                XCTAssertTrue(
                    error.hint?.contains(hintFragment) == true,
                    "Expected hint for \(kind) to contain \(hintFragment), got \(String(describing: error.hint))"
                )
            } else {
                XCTAssertNil(error.hint)
            }
        }
    }

    func testFenceErrorDistinguishesSetupAndRequestTimeoutTaxonomy() {
        let setupTimeout = FenceError(TheHandoff.ConnectionError.timeout)
        let requestTimeout = FenceError.actionTimeout

        XCTAssertEqual(setupTimeout.errorCode, "setup.timeout")
        XCTAssertEqual(setupTimeout.phase, .setup)
        XCTAssertEqual(requestTimeout.errorCode, "request.timeout")
        XCTAssertEqual(requestTimeout.phase, .request)
    }

    func testConnectionFailureFormattingPreservesDisconnectCause() {
        let response = FenceResponse.failure(FenceError(TheHandoff.ConnectionError.disconnected(.missingFingerprint)))

        let compact = response.compactFormatted()
        XCTAssertTrue(compact.contains("error[tls.missing_fingerprint tls retryable=false]"))
        XCTAssertTrue(compact.contains("connection failed in tls: observed No TLS fingerprint available"))
        XCTAssertTrue(compact.contains("hint: Use a loopback simulator target"))

        let json = response.jsonDict()
        XCTAssertEqual(json?["errorCode"] as? String, "tls.missing_fingerprint")
        XCTAssertEqual(json?["phase"] as? String, "tls")
        XCTAssertEqual(json?["retryable"] as? Bool, false)
        XCTAssertTrue((json?["message"] as? String)?.contains("connection failed in tls") == true)
    }

    @ButtonHeistActor
    func testDisconnectCancelsPendingActionWaitWithReason() async {
        let fence = TheFence(configuration: .init())

        let waitTask = Task { @ButtonHeistActor in
            try await fence.waitForActionResult(requestId: "pending", timeout: 10)
        }
        await Task.yield()

        fence.handoff.onDisconnected?(.serverClosed)

        do {
            _ = try await waitTask.value
            XCTFail("Expected pending wait to fail")
        } catch FenceError.connectionFailure(let failure) {
            XCTAssertEqual(failure.errorCode, "transport.server_closed")
            XCTAssertEqual(failure.phase, .transport)
            XCTAssertTrue(failure.retryable)
            XCTAssertTrue(failure.message.contains("Connection closed by server"))
        } catch {
            XCTFail("Expected connectionFailure, got \(error)")
        }
    }

    @ButtonHeistActor
    func testDisconnectCancelsPendingRecordingWaitWithReason() async {
        let fence = TheFence(configuration: .init())

        let waitTask = Task { @ButtonHeistActor in
            try await fence.waitForRecording(timeout: 10)
        }
        await Task.yield()

        fence.handoff.onDisconnected?(.serverClosed)

        do {
            _ = try await waitTask.value
            XCTFail("Expected pending recording wait to fail")
        } catch FenceError.connectionFailure(let failure) {
            XCTAssertEqual(failure.errorCode, "transport.server_closed")
            XCTAssertEqual(failure.phase, .transport)
            XCTAssertTrue(failure.retryable)
            XCTAssertTrue(failure.message.contains("Connection closed by server"))
        } catch {
            XCTFail("Expected connectionFailure, got \(error)")
        }
    }

    @ButtonHeistActor
    func testStopDisablesAutoReconnectPolicyAndCancelsTask() async {
        let fence = TheFence(configuration: .init())
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mockConnection = MockConnection()
        mockConnection.connectEventsOverride = [
            .connected,
            .disconnected(.serverClosed),
        ]
        fence.handoff.makeConnection = { _, _, _ in mockConnection }

        fence.handoff.setupAutoReconnect(filter: "MockApp")
        fence.handoff.connect(to: device)

        guard case .enabled(filter: "MockApp", reconnectTask: let reconnectTask?) = fence.handoff.reconnectPolicy else {
            return XCTFail("Expected reconnect task before stop")
        }

        fence.stop()

        XCTAssertTrue(reconnectTask.isCancelled)
        XCTAssertEqual(fence.handoff.reconnectPolicy, .disabled)
        assertDisconnected(fence.handoff.connectionPhase)
    }

    @ButtonHeistActor
    func testDisconnectClearsLastActionSessionState() async {
        let fence = TheFence(configuration: .init())
        fence.lastActionHistory = .completed(ActionResult(success: true, method: .activate))
        XCTAssertNotNil(fence.lastActionResult)

        fence.handoff.onDisconnected?(.serverClosed)

        XCTAssertNil(fence.lastActionResult)
        XCTAssertNil(fence.currentSessionState()["lastAction"])
    }

    @ButtonHeistActor
    func testSocketDisconnectCancelsInFlightSendAndAwaitAction() async {
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mockConnection = MockConnection()
        mockConnection.connectEventsOverride = [.connected]
        let fence = TheFence(configuration: .init())
        fence.handoff.makeConnection = { _, _, _ in mockConnection }
        fence.handoff.connect(to: device)

        let waitTask = Task { @ButtonHeistActor in
            try await fence.sendAndAwaitAction(.activate(.heistId("pending")), timeout: 10)
        }
        while mockConnection.sent.isEmpty {
            await Task.yield()
        }

        mockConnection.onEvent?(.disconnected(.serverClosed))

        do {
            _ = try await waitTask.value
            XCTFail("Expected in-flight action to fail")
        } catch FenceError.connectionFailure(let failure) {
            XCTAssertEqual(failure.errorCode, "transport.server_closed")
        } catch {
            XCTFail("Expected connectionFailure, got \(error)")
        }
    }

    @ButtonHeistActor
    func testClosedSendFailsPendingActionWithoutWaitingForTimeout() async {
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mockConnection = MockConnection()
        mockConnection.connectEventsOverride = [.connected]
        mockConnection.sendOutcome = .failed(.notConnected)
        let fence = TheFence(configuration: .init())
        fence.handoff.makeConnection = { _, _, _ in mockConnection }
        fence.handoff.connect(to: device)

        do {
            _ = try await fence.sendAndAwaitAction(.activate(.heistId("closed")), timeout: 0.2)
            XCTFail("Expected closed send to fail")
        } catch FenceError.notConnected {
            XCTAssertTrue(mockConnection.sent.isEmpty, "Closed sends must not be recorded as enqueued")
        } catch FenceError.actionTimeout {
            XCTFail("Closed sends must fail the pending tracker immediately instead of timing out")
        } catch {
            XCTFail("Expected notConnected, got \(error)")
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
    func testExecuteWithMissingCommandReturnsSchemaError() async throws {
        let fence = TheFence(configuration: .init())
        let response = try await fence.execute(request: [:])

        if case .error(let message, _) = response {
            XCTAssertEqual(message, "schema validation failed for command: observed missing; expected string")
        } else {
            XCTFail("Expected .error response, got \(response)")
        }
    }

    @ButtonHeistActor
    func testExecuteHelp() async throws {
        let fence = TheFence(configuration: .init())
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
        let fence = TheFence(configuration: .init())
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

        let fence = TheFence(configuration: .init())
        fence.handoff.makeDiscovery = { mockDiscovery }
        fence.handoff.makeConnection = { _, _, _ in mockConnection }

        let response = try await fence.execute(request: ["command": "get_session_state"])

        if case .sessionState(let payload) = response {
            XCTAssertEqual(payload["connected"] as? Bool, false)
            XCTAssertEqual(payload["phase"] as? String, "disconnected")
            XCTAssertNil(payload["lastFailure"])
        } else {
            XCTFail("Expected sessionState response, got \(response)")
        }

        XCTAssertEqual(mockDiscovery.startCount, 0)
        XCTAssertEqual(mockConnection.connectCount, 0)
    }

    @ButtonHeistActor
    func testGetSessionStateConnectedReportsPhaseAndPreservesPayloadFields() async throws {
        let mockConnection = MockConnection()
        mockConnection.serverInfo = TheFenceFixtures.testServerInfo

        let fence = TheFence(configuration: .init())
        fence.handoff.makeConnection = { _, _, _ in mockConnection }
        fence.handoff.connect(to: TheFenceFixtures.testDevice)

        let response = try await fence.execute(request: ["command": "get_session_state"])

        guard case .sessionState(let payload) = response else {
            return XCTFail("Expected sessionState response, got \(response)")
        }
        XCTAssertEqual(payload["connected"] as? Bool, true)
        XCTAssertEqual(payload["phase"] as? String, "connected")
        XCTAssertEqual(payload["deviceName"] as? String, "MockApp")
        XCTAssertEqual(payload["appName"] as? String, "MockApp")
        XCTAssertEqual(payload["connectionType"] as? String, "network")
        XCTAssertEqual(payload["isRecording"] as? Bool, false)
        XCTAssertEqual(payload["actionTimeoutSeconds"] as? TimeInterval, Timeouts.actionSeconds)
        XCTAssertEqual(payload["longActionTimeoutSeconds"] as? TimeInterval, Timeouts.longActionSeconds)
        XCTAssertNil(payload["lastFailure"])
    }

    @ButtonHeistActor
    func testRecordingPhaseIsFenceOwnedFromHandoffEvents() async throws {
        let mockConnection = MockConnection()
        mockConnection.serverInfo = TheFenceFixtures.testServerInfo

        let fence = TheFence(configuration: .init())
        fence.handoff.makeConnection = { _, _, _ in mockConnection }
        fence.handoff.connect(to: TheFenceFixtures.testDevice)

        fence.handoff.handleServerMessage(.recordingStarted, requestId: nil)
        let recordingState = try await fence.execute(request: ["command": "get_session_state"])
        guard case .sessionState(let recordingPayload) = recordingState else {
            return XCTFail("Expected sessionState response, got \(recordingState)")
        }
        XCTAssertEqual(recordingPayload["isRecording"] as? Bool, true)

        fence.handoff.handleServerMessage(.recordingStopped, requestId: nil)
        let stoppedState = try await fence.execute(request: ["command": "get_session_state"])
        guard case .sessionState(let stoppedPayload) = stoppedState else {
            return XCTFail("Expected sessionState response, got \(stoppedState)")
        }
        XCTAssertEqual(stoppedPayload["isRecording"] as? Bool, false)

        fence.handoff.handleServerMessage(.recordingStarted, requestId: nil)
        fence.handoff.handleServerMessage(.recording(RecordingPayload(
            videoData: "",
            width: 100,
            height: 200,
            duration: 1.0,
            frameCount: 10,
            fps: 10,
            startTime: Date(),
            endTime: Date(),
            stopReason: .manual
        )), requestId: nil)
        let completedState = try await fence.execute(request: ["command": "get_session_state"])
        guard case .sessionState(let completedPayload) = completedState else {
            return XCTFail("Expected sessionState response, got \(completedState)")
        }
        XCTAssertEqual(completedPayload["isRecording"] as? Bool, false)
    }

    @ButtonHeistActor
    func testDisconnectClearsFenceRecordingPhase() async throws {
        let mockConnection = MockConnection()
        mockConnection.serverInfo = TheFenceFixtures.testServerInfo

        let fence = TheFence(configuration: .init())
        fence.handoff.makeConnection = { _, _, _ in mockConnection }
        fence.handoff.connect(to: TheFenceFixtures.testDevice)
        fence.handoff.handleServerMessage(.recordingStarted, requestId: nil)

        mockConnection.onEvent?(.disconnected(.serverClosed))

        let response = try await fence.execute(request: ["command": "get_session_state"])
        guard case .sessionState(let payload) = response else {
            return XCTFail("Expected sessionState response, got \(response)")
        }
        XCTAssertEqual(payload["isRecording"] as? Bool, false)
        XCTAssertEqual(payload["connected"] as? Bool, false)
    }

    @ButtonHeistActor
    func testGetSessionStateFailedAuthReportsFailureDetails() async throws {
        let fence = TheFence(configuration: .init())
        fence.handoff.handleServerMessage(
            .error(ServerError(kind: .authFailure, message: "bad token")),
            requestId: nil
        )

        let response = try await fence.execute(request: ["command": "get_session_state"])

        guard case .sessionState(let payload) = response else {
            return XCTFail("Expected sessionState response, got \(response)")
        }
        XCTAssertEqual(payload["connected"] as? Bool, false)
        XCTAssertEqual(payload["phase"] as? String, "failed")
        let failure = try XCTUnwrap(payload["lastFailure"] as? [String: Any])
        XCTAssertEqual(failure["errorCode"] as? String, "auth.failed")
        XCTAssertEqual(failure["phase"] as? String, "auth")
        XCTAssertEqual(failure["retryable"] as? Bool, false)
        XCTAssertEqual(failure["message"] as? String, "Authentication failed: bad token")
        XCTAssertEqual(failure["hint"] as? String, "Retry without a token to request a fresh session.")
    }

    @ButtonHeistActor
    func testGetSessionStateDisconnectedWithKnownReasonReportsFailureDetails() async throws {
        let mockConnection = MockConnection()
        mockConnection.connectEventsOverride = [
            .connected,
            .disconnected(.serverClosed),
        ]

        let fence = TheFence(configuration: .init())
        fence.handoff.makeConnection = { _, _, _ in mockConnection }
        fence.handoff.connect(to: TheFenceFixtures.testDevice)

        let response = try await fence.execute(request: ["command": "get_session_state"])

        guard case .sessionState(let payload) = response else {
            return XCTFail("Expected sessionState response, got \(response)")
        }
        XCTAssertEqual(payload["connected"] as? Bool, false)
        XCTAssertEqual(payload["phase"] as? String, "disconnected")
        let failure = try XCTUnwrap(payload["lastFailure"] as? [String: Any])
        XCTAssertEqual(failure["errorCode"] as? String, "transport.server_closed")
        XCTAssertEqual(failure["phase"] as? String, "transport")
        XCTAssertEqual(failure["retryable"] as? Bool, true)
        XCTAssertEqual(failure["hint"] as? String, "Check that the app is still running and reachable, then retry.")
    }

    @ButtonHeistActor
    func testGetSessionStateSendsNoHierarchyObservationMessages() async throws {
        let mockConnection = MockConnection()
        mockConnection.serverInfo = TheFenceFixtures.testServerInfo

        let fence = TheFence(configuration: .init())
        fence.handoff.makeConnection = { _, _, _ in mockConnection }
        fence.handoff.connect(to: TheFenceFixtures.testDevice)
        mockConnection.sent.removeAll()

        _ = try await fence.execute(request: ["command": "get_session_state"])

        let hierarchyMessages = mockConnection.sent.filter { message, _ in
            switch message {
            case .requestInterface, .explore:
                return true
            default:
                return false
            }
        }
        XCTAssertTrue(hierarchyMessages.isEmpty)
    }

    // MARK: - BookKeeper Command Dispatch

    @ButtonHeistActor
    func testExecuteGetSessionLogReturnsErrorWhenIdle() async throws {
        let fence = TheFence(configuration: .init())
        let response = try await fence.execute(request: ["command": "get_session_log"])
        if case .error(let message, _) = response {
            XCTAssertTrue(message.contains("No active session"))
        } else {
            XCTFail("Expected error response when no session active, got \(response)")
        }
    }

    @ButtonHeistActor
    func testExecuteArchiveSessionReturnsErrorWhenIdle() async throws {
        let fence = TheFence(configuration: .init())
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
        let fence = TheFence(configuration: .init())
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
        let fence = TheFence(configuration: .init())
        let expectedPayload = RecordingPayload(
            videoData: "dGVzdA==", width: 390, height: 844,
            duration: 2.0, frameCount: 16, fps: 8,
            startTime: Date(), endTime: Date(), stopReason: .manual
        )

        // afterRegister fires synchronously once the tracker has registered the
        // recording callback — deliver the payload right then, no sleep needed.
        let result = try await fence.waitForRecording(timeout: 1.0) {
            fence.handoff.onRecordingEvent?(.completed(expectedPayload))
        }
        XCTAssertEqual(result.videoData, expectedPayload.videoData)
        XCTAssertEqual(result.width, expectedPayload.width)
        XCTAssertEqual(result.duration, expectedPayload.duration)
    }

    @ButtonHeistActor
    func testWaitForRecordingServerError() async throws {
        let fence = TheFence(configuration: .init())

        do {
            _ = try await fence.waitForRecording(timeout: 1.0) {
                fence.handoff.onRecordingEvent?(.failed("disk full"))
            }
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
    func testRequestScopedServerErrorFailsPendingActionWithoutDisconnecting() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { _ in
            .error(ServerError(kind: .general, message: "Response too large to send over the socket (20000001 bytes)"))
        }

        do {
            _ = try await fence.execute(request: ["command": "activate", "identifier": "button"])
            XCTFail("Expected FenceError.serverError")
        } catch {
            guard case FenceError.serverError(let serverError) = error else {
                return XCTFail("Expected serverError, got \(error)")
            }
            XCTAssertEqual(serverError.kind, .general)
            XCTAssertTrue(serverError.message.contains("Response too large"))
            XCTAssertEqual((error as? FenceError)?.errorCode, "server.general")
        }

        XCTAssertTrue(mockConn.isConnected)
    }

    @ButtonHeistActor
    func testWaitForRecordingTimeout() async throws {
        let fence = TheFence(configuration: .init())

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
    func testWaitForRecordingKeepsStableCallbacksAndExternalObserverActive() async throws {
        let fence = TheFence(configuration: .init())
        let expectedPayload = RecordingPayload(
            videoData: "dGVzdA==", width: 390, height: 844,
            duration: 2.0, frameCount: 16, fps: 8,
            startTime: Date(), endTime: Date(), stopReason: .manual
        )
        var observerPayload: RecordingPayload?
        let stableCallback = fence.handoff.onRecordingEvent
        fence.handoff.onRecordingEvent = { event in
            if case .completed(let payload) = event {
                observerPayload = payload
            }
            stableCallback?(event)
        }

        let result = try await fence.waitForRecording(timeout: 1.0) {
            fence.handoff.onRecordingEvent?(.completed(expectedPayload))
        }

        XCTAssertEqual(result.videoData, expectedPayload.videoData)
        XCTAssertEqual(observerPayload?.videoData, expectedPayload.videoData)
    }

    @ButtonHeistActor
    func testWaitForRecordingRejectsConcurrentWaiters() async {
        let fence = TheFence(configuration: .init())

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

    // MARK: - recordToCompletion

    @ButtonHeistActor
    func testStartRecordingWaitsForServerAcknowledgement() async throws {
        let (fence, mockConn) = makeConnectedFence()
        try await fence.start()
        mockConn.autoResponse = nil

        var didReturn = false
        var responseMessage: String?
        let task = Task { @ButtonHeistActor in
            let response = try await fence.execute(request: ["command": "start_recording"])
            guard case .ok(let message) = response else {
                didReturn = true
                return XCTFail("Expected .ok response, got \(response)")
            }
            responseMessage = message
            didReturn = true
        }

        var startSent = false
        for _ in 0..<200 {
            startSent = mockConn.sent.contains { sent in
                if case .startRecording = sent.0 { return true }
                return false
            }
            if startSent { break }
            await Task.yield()
        }

        XCTAssertTrue(startSent, "Expected start_recording to be sent")
        await Task.yield()
        XCTAssertFalse(didReturn, "start_recording should not return before recordingStarted arrives")

        fence.handoff.handleServerMessage(.recordingStarted, requestId: nil)

        try await task.value
        XCTAssertTrue(responseMessage?.contains("Recording started") == true)
        XCTAssertTrue(didReturn)
    }

    @ButtonHeistActor
    func testRecordToCompletionReturnsPayloadOnSuccess() async throws {
        let (fence, mockConn) = makeConnectedFence()
        try await fence.start()
        let expectedPayload = RecordingPayload(
            videoData: "dGVzdA==", width: 390, height: 844,
            duration: 2.0, frameCount: 16, fps: 8,
            startTime: Date(), endTime: Date(), stopReason: .manual
        )
        // When the start_recording message is observed, deliver the payload via
        // the recording callback so the wait resolves immediately.
        mockConn.autoResponse = { message in
            if case .startRecording = message {
                Task { @ButtonHeistActor in
                    for _ in 0..<200 where !fence.isWaitingForRecordingCompletion {
                        await Task.yield()
                    }
                    fence.handoff.onRecordingEvent?(.completed(expectedPayload))
                }
                return .recordingStarted
            }
            return .actionResult(ActionResult(success: true, method: .activate))
        }

        let result = try await fence.recordToCompletion(
            config: RecordingConfig(fps: 8, maxDuration: 60),
            timeout: 5.0
        )

        XCTAssertEqual(result.videoData, expectedPayload.videoData)
        XCTAssertEqual(result.duration, expectedPayload.duration)
        XCTAssertTrue(mockConn.sent.contains { sent in
            if case .startRecording = sent.0 { return true }
            return false
        }, "Expected startRecording to have been sent")
    }

    @ButtonHeistActor
    func testRecordToCompletionCancelMidWaitTriggersStop() async throws {
        let (fence, mockConn) = makeConnectedFence()
        try await fence.start()
        // Do not deliver a payload — the wait should hang until cancelled.
        mockConn.autoResponse = { _ in
            .recordingStarted
        }

        let task = Task { @ButtonHeistActor in
            try await fence.recordToCompletion(
                config: RecordingConfig(fps: 8, maxDuration: 60),
                timeout: 60.0
            )
        }

        // Wait until the completion callback has been registered — that's the
        // deterministic signal that the task has progressed past start
        // acknowledgement and into the recording wait.
        for _ in 0..<200 {
            if fence.isWaitingForRecordingCompletion { break }
            await Task.yield()
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let stopSent = mockConn.sent.contains { sent in
            if case .stopRecording = sent.0 { return true }
            return false
        }
        XCTAssertTrue(stopSent, "Expected stop_recording to be sent on cancel-mid-wait")
    }

    @ButtonHeistActor
    func testRecordToCompletionCancelMidStartDoesNotStop() async throws {
        let (fence, mockConn) = makeConnectedFence()
        try await fence.start()
        mockConn.autoResponse = { _ in
            .actionResult(ActionResult(success: true, method: .activate))
        }

        let task = Task { @ButtonHeistActor in
            try await fence.recordToCompletion(
                config: RecordingConfig(fps: 8, maxDuration: 60),
                timeout: 5.0
            )
        }
        // Cancel before the task gets to run — the cancellation check at the
        // top of recordToCompletion should fire before the start send.
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        // Pre-start cancellation must not send anything.
        let startSent = mockConn.sent.contains { sent in
            if case .startRecording = sent.0 { return true }
            return false
        }
        let stopSent = mockConn.sent.contains { sent in
            if case .stopRecording = sent.0 { return true }
            return false
        }
        XCTAssertFalse(startSent, "Expected no start_recording when cancelled before start")
        XCTAssertFalse(stopSent, "Expected no stop_recording when cancelled before start")
    }

    @ButtonHeistActor
    func testRecordToCompletionPropagatesStartAcknowledgementErrorsAndStops() async throws {
        let (fence, mockConn) = makeConnectedFence()
        try await fence.start()
        mockConn.autoResponse = { message in
            if case .startRecording = message {
                Task { @ButtonHeistActor in
                    fence.handoff.onRecordingEvent?(.failed("disk full"))
                }
            }
            return .actionResult(ActionResult(success: true, method: .activate))
        }

        do {
            _ = try await fence.recordToCompletion(
                config: RecordingConfig(fps: 8, maxDuration: 60),
                timeout: 5.0
            )
            XCTFail("Expected FenceError.actionFailed")
        } catch let error as FenceError {
            guard case .actionFailed(let message) = error else {
                return XCTFail("Expected actionFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("disk full"), "Expected message to mention 'disk full', got: \(message)")
        } catch {
            XCTFail("Expected FenceError.actionFailed, got \(error)")
        }

        let stopSent = mockConn.sent.contains { sent in
            if case .stopRecording = sent.0 { return true }
            return false
        }
        XCTAssertTrue(stopSent, "Expected stop_recording on start acknowledgement error")
    }

    @ButtonHeistActor
    func testRecordToCompletionPropagatesCompletionErrorsAndStops() async throws {
        let (fence, mockConn) = makeConnectedFence()
        try await fence.start()
        mockConn.autoResponse = { message in
            if case .startRecording = message {
                Task { @ButtonHeistActor in
                    for _ in 0..<200 where !fence.isWaitingForRecordingCompletion {
                        await Task.yield()
                    }
                    fence.handoff.onRecordingEvent?(.failed("disk full"))
                }
                return .recordingStarted
            }
            return .actionResult(ActionResult(success: true, method: .activate))
        }

        do {
            _ = try await fence.recordToCompletion(
                config: RecordingConfig(fps: 8, maxDuration: 60),
                timeout: 5.0
            )
            XCTFail("Expected FenceError.actionFailed")
        } catch let error as FenceError {
            guard case .actionFailed(let message) = error else {
                return XCTFail("Expected actionFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("disk full"), "Expected message to mention 'disk full', got: \(message)")
        } catch {
            XCTFail("Expected FenceError.actionFailed, got \(error)")
        }

        let stopSent = mockConn.sent.contains { sent in
            if case .stopRecording = sent.0 { return true }
            return false
        }
        XCTAssertTrue(stopSent, "Expected stop_recording on completion error")
    }

    @ButtonHeistActor
    func testDirectConnectTimeoutTearsDownAttempt() async {
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mockConnection = MockConnection()
        mockConnection.connectEventsOverride = []

        let fence = TheFence(configuration: .init(
            connectionTimeout: 0.05,
            autoReconnect: false,
            directDevice: device
        ))
        fence.handoff.makeConnection = { _, _, _ in mockConnection }

        do {
            try await fence.start()
            XCTFail("Expected connection timeout")
        } catch FenceError.connectionTimeout {
            // Expected.
        } catch {
            XCTFail("Expected connection timeout, got \(error)")
        }

        XCTAssertFalse(mockConnection.isConnected)
        assertDisconnected(fence.handoff.connectionPhase)
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

        let fence = TheFence(configuration: .init())
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
                        return .error(ServerError(kind: .general, message: "unexpected"))
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
        let fence = TheFence(configuration: .init())
        XCTAssertNil(fence.drainBackgroundDelta())
    }

    @ButtonHeistActor
    func testDrainBackgroundDeltaClearsAfterRead() async {
        let fence = TheFence(configuration: .init())
        // Simulate a background delta arriving via the handoff callback
        let delta: AccessibilityTrace.Delta = .screenChanged(.init(
            elementCount: 7,
            newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        ))
        fence.handoff.onBackgroundDelta?(delta)

        let first = fence.drainBackgroundDelta()
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.isScreenChanged, true)
        XCTAssertEqual(first?.elementCount, 7)

        let second = fence.drainBackgroundDelta()
        XCTAssertNil(second)
    }

    @ButtonHeistActor
    func testDrainBackgroundDeltaPreservesArrivalOrder() async {
        let fence = TheFence(configuration: .init())
        fence.handoff.onBackgroundDelta?(.elementsChanged(.init(elementCount: 2, edits: ElementEdits())))
        fence.handoff.onBackgroundDelta?(.screenChanged(.init(elementCount: 7, newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: []))))

        let first = fence.drainBackgroundDelta()
        XCTAssertEqual(first?.kindRawValue, "elementsChanged")
        XCTAssertEqual(first?.elementCount, 2)

        let second = fence.drainBackgroundDelta()
        XCTAssertEqual(second?.isScreenChanged, true)
        XCTAssertEqual(second?.elementCount, 7)

        XCTAssertNil(fence.drainBackgroundDelta())
    }

    @ButtonHeistActor
    func testDrainBackgroundDeltasReturnsAllQueuedDeltas() async {
        let fence = TheFence(configuration: .init())
        fence.handoff.onBackgroundDelta?(.elementsChanged(.init(elementCount: 2, edits: ElementEdits())))
        fence.handoff.onBackgroundDelta?(.screenChanged(.init(elementCount: 7, newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: []))))

        let deltas = fence.drainBackgroundDeltas()

        XCTAssertEqual(deltas.map(\.kindRawValue), ["elementsChanged", "screenChanged"])
        XCTAssertEqual(deltas.map(\.elementCount), [2, 7])
        XCTAssertNil(fence.drainBackgroundDelta())
    }

    @ButtonHeistActor
    func testBackgroundDeltaCompatibilityIsDerivedFromTraceReceipt() async {
        let fence = TheFence(configuration: .init())
        let before = makeReceiptTestInterface([
            makeReceiptTestElement(heistId: "status", label: "Status", value: "Old"),
        ])
        let after = makeReceiptTestInterface([
            makeReceiptTestElement(heistId: "status", label: "Status", value: "New"),
        ])
        let trace = makeReceiptTestTrace(before: before, after: after)
        let misleadingLegacyDelta: AccessibilityTrace.Delta = .screenChanged(.init(
            elementCount: 0,
            newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        ))

        fence.handoff.handleServerMessage(
            .pong,
            requestId: nil,
            backgroundAccessibilityDelta: misleadingLegacyDelta,
            accessibilityTrace: trace
        )

        let derived = fence.drainBackgroundDelta()
        guard case .elementsChanged(let payload)? = derived else {
            return XCTFail("Expected trace-derived elementsChanged delta, got \(String(describing: derived))")
        }
        XCTAssertEqual(payload.edits.updated.first?.heistId, "status")
        XCTAssertEqual(payload.edits.updated.first?.changes.first?.old, "Old")
        XCTAssertEqual(payload.edits.updated.first?.changes.first?.new, "New")
    }

    @ButtonHeistActor
    func testBackgroundExpectationMismatchDoesNotConsumeDelta() async throws {
        let (fence, _) = makeConnectedFence()
        fence.handoff.onBackgroundDelta?(.screenChanged(.init(elementCount: 7, newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: []))))

        let response = try await fence.execute(request: [
            "command": "activate",
            "heistId": "stale_button",
            "expect": [
                "type": "element_updated",
                "heistId": "counter",
                "property": "value",
                "newValue": "5",
            ],
        ])
        if case .action(_, let expectation) = response {
            XCTAssertEqual(expectation?.met, false)
        } else {
            XCTFail("Expected action response, got \(response)")
        }

        let queued = fence.drainBackgroundDelta()
        XCTAssertEqual(queued?.isScreenChanged, true)
        XCTAssertEqual(queued?.elementCount, 7)
        XCTAssertNil(fence.drainBackgroundDelta())
    }

    @ButtonHeistActor
    func testWaitForChangeExpectationConsumesOnlyMatchingDelta() async throws {
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
            appName: "MockApp", bundleIdentifier: "com.test",
            deviceName: "Sim", systemVersion: "18.0",
            screenWidth: 390, screenHeight: 844
        )

        let fence = TheFence(configuration: .init())
        fence.handoff.makeDiscovery = { mockDiscovery }
        fence.handoff.makeConnection = { _, _, _ in mockConnection }

        fence.handoff.onBackgroundDelta?(.elementsChanged(.init(elementCount: 2, edits: ElementEdits())))
        fence.handoff.onBackgroundDelta?(.screenChanged(.init(elementCount: 7, newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: []))))

        let response = try await fence.execute(request: [
            "command": "wait_for_change",
            "expect": ["type": "screen_changed"],
        ])

        if case .action(let result, let expectation) = response {
            XCTAssertTrue(result.success)
            XCTAssertEqual(result.accessibilityDelta?.isScreenChanged, true)
            XCTAssertEqual(expectation?.met, true)
            XCTAssertEqual(mockDiscovery.startCount, 0, "Short-circuit should avoid discovery")
            XCTAssertEqual(mockConnection.connectCount, 0, "Short-circuit should avoid connection")
        } else {
            XCTFail("Expected action response, got \(response)")
        }

        let remaining = fence.drainBackgroundDelta()
        XCTAssertEqual(remaining?.kindRawValue, "elementsChanged")
        XCTAssertEqual(remaining?.elementCount, 2)
        XCTAssertNil(fence.drainBackgroundDelta())
    }

    @ButtonHeistActor
    func testBackgroundDeltaQueueDropsOldestWhenCapacityExceeded() async {
        let fence = TheFence(configuration: .init())
        for count in 1...25 {
            fence.handoff.onBackgroundDelta?(.elementsChanged(.init(elementCount: count, edits: ElementEdits())))
        }

        let first = fence.drainBackgroundDelta()
        XCTAssertEqual(first?.elementCount, 6)

        for expectedCount in 7...25 {
            XCTAssertEqual(fence.drainBackgroundDelta()?.elementCount, expectedCount)
        }
        XCTAssertNil(fence.drainBackgroundDelta())
    }

    @ButtonHeistActor
    func testBackgroundDeltaQueueClearsOnDisconnect() async {
        let fence = TheFence(configuration: .init())
        fence.handoff.onBackgroundDelta?(.screenChanged(.init(elementCount: 7, newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: []))))

        fence.handoff.onDisconnected?(.serverClosed)

        XCTAssertNil(fence.drainBackgroundDelta())
    }

    @ButtonHeistActor
    func testWaitForChangeExpectationShortCircuitsOnBackgroundDelta() async throws {
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
            appName: "MockApp", bundleIdentifier: "com.test",
            deviceName: "Sim", systemVersion: "18.0",
            screenWidth: 390, screenHeight: 844
        )

        let fence = TheFence(configuration: .init())
        fence.handoff.makeDiscovery = { mockDiscovery }
        fence.handoff.makeConnection = { _, _, _ in mockConnection }

        // Simulate a screen-changed background delta
        let element = HeistElement(
            description: "Button", label: "New Order", value: nil, identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44, actions: [.activate]
        )
        let fullInterface = Interface(timestamp: Date(), tree: [.element(element)])
        let delta: AccessibilityTrace.Delta = .screenChanged(.init(elementCount: 1, newInterface: fullInterface))
        fence.handoff.onBackgroundDelta?(delta)

        // wait_for_change may satisfy a late call from a queued background delta.
        let response = try await fence.execute(request: [
            "command": "wait_for_change",
            "expect": ["type": "screen_changed"],
        ])

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
    func testQueuedBackgroundExpectationStillDispatchesAction() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { message in
            switch message {
            case .activate:
                return .actionResult(ActionResult(
                    success: true,
                    method: .activate,
                    accessibilityDelta: .noChange(.init(elementCount: 1))
                ))
            case .waitForChange:
                return .actionResult(ActionResult(
                    success: true,
                    method: .waitForChange,
                    message: "expectation already met by current state (0.0s)",
                    accessibilityDelta: .noChange(.init(elementCount: 1))
                ))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }
        fence.handoff.onBackgroundDelta?(.screenChanged(.init(
            elementCount: 7,
            newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        )))

        let response = try await fence.execute(request: [
            "command": "activate",
            "heistId": "stale_button",
            "expect": ["type": "screen_changed"],
        ])

        XCTAssertTrue(mockConn.sent.contains { sent, _ in
            if case .activate = sent { return true }
            return false
        }, "Action must dispatch even when a queued background delta already matches")
        if case .action(_, let expectation) = response {
            XCTAssertEqual(expectation?.met, true)
        } else {
            XCTFail("Expected action response, got \(response)")
        }

        let queued = fence.drainBackgroundDelta()
        XCTAssertEqual(queued?.isScreenChanged, true)
        XCTAssertEqual(queued?.elementCount, 7)
    }

    @ButtonHeistActor
    func testDelayedActionExpectationWaitsUntilMet() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let appeared = HeistElement(
            description: "Label", label: "Ready", value: nil, identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: []
        )
        mockConn.autoResponse = { message in
            switch message {
            case .activate:
                return .actionResult(ActionResult(
                    success: true,
                    method: .activate,
                    accessibilityDelta: .noChange(.init(elementCount: 1))
                ))
            case .waitForChange:
                return .actionResult(ActionResult(
                    success: true,
                    method: .waitForChange,
                    message: "expectation met after 0.1s",
                    accessibilityDelta: .elementsChanged(.init(
                        elementCount: 2,
                        edits: ElementEdits(added: [appeared])
                    ))
                ))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }

        let response = try await fence.execute(request: [
            "command": "activate",
            "heistId": "button",
            "expect": [
                "type": "element_appeared",
                "matcher": ["label": "Ready"],
            ],
        ])

        let sentNames = mockConn.sent.map { $0.0.canonicalName }
        XCTAssertTrue(sentNames.contains("activate"))
        XCTAssertTrue(sentNames.contains("wait_for_change"))
        if case .action(let result, let expectation) = response {
            XCTAssertEqual(result.method, .waitForChange)
            XCTAssertEqual(expectation?.met, true)
        } else {
            XCTFail("Expected action response, got \(response)")
        }
    }

    @ButtonHeistActor
    func testNeverSatisfiedActionExpectationReturnsLastWaitResult() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { message in
            switch message {
            case .activate:
                return .actionResult(ActionResult(
                    success: true,
                    method: .activate,
                    accessibilityDelta: .noChange(.init(elementCount: 1))
                ))
            case .waitForChange:
                return .actionResult(ActionResult(
                    success: false,
                    method: .waitForChange,
                    message: "expectation not met after 0.1s",
                    errorKind: .timeout,
                    accessibilityDelta: .elementsChanged(.init(elementCount: 3, edits: ElementEdits()))
                ))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }

        let response = try await fence.execute(request: [
            "command": "activate",
            "heistId": "button",
            "expect": ["type": "screen_changed"],
        ])

        if case .action(let result, let expectation) = response {
            XCTAssertFalse(result.success)
            XCTAssertEqual(result.method, .waitForChange)
            XCTAssertEqual(result.errorKind, .timeout)
            XCTAssertEqual(result.accessibilityDelta?.kindRawValue, "elementsChanged")
            XCTAssertEqual(expectation?.met, false)
            XCTAssertEqual(expectation?.actual, "expectation not met after 0.1s")
        } else {
            XCTFail("Expected action response, got \(response)")
        }
    }

    @ButtonHeistActor
    func testClientSideActionExpectationTimeoutReturnsInitialActionResult() async throws {
        let (fence, mockConn) = makeConnectedFence(configuration: .init(postActionExpectationTimeoutBuffer: 0))
        mockConn.autoResponse = { message in
            switch message {
            case .activate:
                mockConn.autoResponse = nil
                return .actionResult(ActionResult(
                    success: true,
                    method: .activate,
                    accessibilityDelta: .noChange(.init(elementCount: 1))
                ))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }

        let response = try await fence.execute(request: [
            "command": "activate",
            "heistId": "button",
            "timeout": 0.01,
            "expect": ["type": "screen_changed"],
        ])

        if case .action(let result, let expectation) = response {
            XCTAssertTrue(result.success)
            XCTAssertEqual(result.method, .activate)
            XCTAssertEqual(expectation?.met, false)
        } else {
            XCTFail("Expected action response, got \(response)")
        }
    }

    @ButtonHeistActor
    func testImmediateActionExpectationDoesNotWaitForChange() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { message in
            switch message {
            case .activate:
                return .actionResult(ActionResult(
                    success: true,
                    method: .activate,
                    accessibilityDelta: .screenChanged(.init(
                        elementCount: 1,
                        newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
                    ))
                ))
            case .waitForChange:
                XCTFail("Immediate expectation should not send wait_for_change")
                return .actionResult(ActionResult(success: false, method: .waitForChange))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }

        let response = try await fence.execute(request: [
            "command": "activate",
            "heistId": "button",
            "expect": ["type": "screen_changed"],
        ])

        let waitMessages = mockConn.sent.filter { sent, _ in
            if case .waitForChange = sent { return true }
            return false
        }
        XCTAssertTrue(waitMessages.isEmpty)
        if case .action(let result, let expectation) = response {
            XCTAssertEqual(result.method, .activate)
            XCTAssertEqual(expectation?.met, true)
        } else {
            XCTFail("Expected action response, got \(response)")
        }
    }

    @ButtonHeistActor
    func testNoShortCircuitWithoutExpectation() async throws {
        let fence = TheFence(configuration: .init())

        // Background delta present but no expectation on the action
        let delta: AccessibilityTrace.Delta = .screenChanged(.init(
            elementCount: 3,
            newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        ))
        fence.handoff.onBackgroundDelta?(delta)

        // Action without expect — should NOT short-circuit against the
        // background delta. Depending on current connection setup this may
        // surface as a thrown connection error or an error response, but it
        // must not return the synthetic "expectation already met" action.
        do {
            let response = try await fence.execute(request: [
                "command": "activate",
                "heistId": "some_button",
            ])
            if case .action(let result, _) = response {
                XCTAssertFalse(result.success)
                XCTAssertNotEqual(result.message, "expectation already met by background change")
            }
        } catch {
            // Also acceptable — no connection, and no background short-circuit.
        }
    }

    // MARK: - Heist Recording Expectations

    @ButtonHeistActor
    func testHeistRecordingSkipsActionWhenExplicitExpectationFails() async throws {
        let (fence, mockConn) = makeConnectedFence(configuration: .init(postActionExpectationTimeoutBuffer: 0))
        mockConn.autoResponse = { message in
            switch message {
            case .activate:
                mockConn.autoResponse = nil
                return .actionResult(ActionResult(
                    success: true,
                    method: .activate,
                    accessibilityDelta: .noChange(.init(elementCount: 1))
                ))
            case .requestInterface:
                return .interface(Interface(timestamp: Date(timeIntervalSince1970: 0), tree: []))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }
        try await startHeistRecording(on: fence)

        let response = try await fence.execute(request: [
            "command": "activate",
            "label": "No Change",
            "timeout": 0.01,
            "expect": ["type": "screen_changed"],
        ])

        if case .action(let result, let expectation) = response {
            XCTAssertTrue(result.success)
            XCTAssertEqual(result.method, .activate)
            XCTAssertEqual(expectation?.met, false)
        } else {
            XCTFail("Expected action response, got \(response)")
        }
        XCTAssertEqual(heistEvidenceCount(in: fence), 0)
        try? await fence.bookKeeper.closeSession()
    }

    @ButtonHeistActor
    func testHeistRecordingRecordsActionWhenExplicitExpectationIsMet() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { message in
            switch message {
            case .activate:
                return .actionResult(ActionResult(
                    success: true,
                    method: .activate,
                    accessibilityDelta: .screenChanged(.init(
                        elementCount: 0,
                        newInterface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
                    )),
                    accessibilityTrace: AccessibilityTrace(interface: Interface(
                        timestamp: Date(timeIntervalSince1970: 0),
                        tree: []
                    ))
                ))
            case .waitForChange:
                XCTFail("Immediate screen_changed expectation should not wait")
                return .actionResult(ActionResult(success: false, method: .waitForChange))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }
        try await startHeistRecording(on: fence)

        let response = try await fence.execute(request: [
            "command": "activate",
            "label": "Continue",
            "expect": ["type": "screen_changed"],
        ])

        if case .action(_, let expectation) = response {
            XCTAssertEqual(expectation?.met, true)
        } else {
            XCTFail("Expected action response, got \(response)")
        }
        XCTAssertEqual(heistEvidenceCount(in: fence), 1)

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("heist")
        defer { try? FileManager.default.removeItem(at: output) }
        let stopResponse = try await fence.execute(request: [
            "command": "stop_heist",
            "output": output.path,
        ])
        if case .heistStopped(_, let stepCount) = stopResponse {
            XCTAssertEqual(stepCount, 1)
        } else {
            XCTFail("Expected heistStopped response, got \(stopResponse)")
        }
        let heist = try TheBookKeeper.readHeist(from: output)
        XCTAssertEqual(heist.steps.count, 1)
        XCTAssertEqual(heist.steps[0].command, "activate")
        XCTAssertEqual(heist.steps[0].recorded?.accessibilityTrace?.receipts.first?.kind, .capture)
        XCTAssertEqual(heist.steps[0].recorded?.accessibilityDelta?.kindRawValue, "screenChanged")
        XCTAssertEqual(heist.steps[0].recorded?.expectation?.met, true)
        try? await fence.bookKeeper.closeSession()
    }

    @ButtonHeistActor
    func testHeistRecordingUsesVerifiedWaitResultAsTraceEvidence() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { message in
            switch message {
            case .activate:
                return .actionResult(ActionResult(
                    success: true,
                    method: .activate,
                    accessibilityDelta: .noChange(.init(elementCount: 1)),
                    accessibilityTrace: AccessibilityTrace(interface: Interface(
                        timestamp: Date(timeIntervalSince1970: 0),
                        tree: [.element(HeistElement(
                            heistId: "loading",
                            description: "Loading",
                            label: "Loading",
                            value: nil,
                            identifier: nil,
                            traits: [.staticText],
                            frameX: 0,
                            frameY: 0,
                            frameWidth: 100,
                            frameHeight: 44,
                            actions: []
                        ))]
                    ))
                ))
            case .waitForChange:
                let doneInterface = Interface(
                    timestamp: Date(timeIntervalSince1970: 1),
                    tree: [.element(HeistElement(
                        heistId: "done",
                        description: "Done",
                        label: "Done",
                        value: nil,
                        identifier: nil,
                        traits: [.button],
                        frameX: 0,
                        frameY: 0,
                        frameWidth: 100,
                        frameHeight: 44,
                        actions: []
                    ))]
                )
                return .actionResult(ActionResult(
                    success: true,
                    method: .waitForChange,
                    accessibilityDelta: .screenChanged(.init(
                        elementCount: 1,
                        newInterface: doneInterface
                    )),
                    accessibilityTrace: AccessibilityTrace(interface: doneInterface)
                ))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }
        try await startHeistRecording(on: fence)

        let response = try await fence.execute(request: [
            "command": "activate",
            "label": "Continue",
            "expect": ["type": "screen_changed"],
        ])

        if case .action(let result, let expectation) = response {
            XCTAssertEqual(result.method, .waitForChange)
            XCTAssertEqual(expectation?.met, true)
        } else {
            XCTFail("Expected action response, got \(response)")
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("heist")
        defer { try? FileManager.default.removeItem(at: output) }
        _ = try await fence.execute(request: [
            "command": "stop_heist",
            "output": output.path,
        ])

        let heist = try TheBookKeeper.readHeist(from: output)
        XCTAssertEqual(heist.steps.count, 1)
        XCTAssertEqual(heist.steps[0].command, "activate")
        XCTAssertEqual(heist.steps[0].recorded?.accessibilityTrace?.captures.first?.interface.elements.first?.label, "Done")
        XCTAssertEqual(heist.steps[0].recorded?.accessibilityDelta?.kindRawValue, "screenChanged")
        XCTAssertEqual(heist.steps[0].recorded?.expectation?.met, true)
        try? await fence.bookKeeper.closeSession()
    }

    @ButtonHeistActor
    func testHeistRecordingRecordsSuccessfulActionWithoutExpectation() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { message in
            switch message {
            case .activate:
                return .actionResult(ActionResult(
                    success: true,
                    method: .activate,
                    accessibilityDelta: .noChange(.init(elementCount: 1))
                ))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }
        try await startHeistRecording(on: fence)

        let response = try await fence.execute(request: [
            "command": "activate",
            "label": "Plain Success",
        ])

        if case .action(let result, let expectation) = response {
            XCTAssertTrue(result.success)
            XCTAssertNil(expectation)
        } else {
            XCTFail("Expected action response, got \(response)")
        }
        XCTAssertEqual(heistEvidenceCount(in: fence), 1)
        try? await fence.bookKeeper.closeSession()
    }

    @ButtonHeistActor
    func testHeistRecordingSkipsFailedActionResult() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.autoResponse = { message in
            switch message {
            case .activate:
                return .actionResult(ActionResult(
                    success: false,
                    method: .activate,
                    message: "element not found",
                    errorKind: .elementNotFound
                ))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }
        try await startHeistRecording(on: fence)

        let response = try await fence.execute(request: [
            "command": "activate",
            "label": "Missing",
        ])

        if case .action(let result, let expectation) = response {
            XCTAssertFalse(result.success)
            XCTAssertEqual(expectation?.met, false)
        } else {
            XCTFail("Expected action response, got \(response)")
        }
        XCTAssertEqual(heistEvidenceCount(in: fence), 0)
        try? await fence.bookKeeper.closeSession()
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
        let fence = TheFence(configuration: .init())
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
        let fence = TheFence(configuration: .init())
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

    /// A late `actionResult` arriving after the per-action timeout must be
    /// dropped without affecting the connection or future actions. Before the
    /// fix, the timeout path called `forceDisconnect`, so a late response landed
    /// on a dead socket. Now the connection stays live, the response flows to
    /// `actionTracker.resolve`, and the tracker silently no-ops on an unknown
    /// requestId.
    @ButtonHeistActor
    func testLateActionResultAfterTimeoutIsSafelyDropped() async throws {
        let device = DiscoveredDevice(
            id: "late-device",
            name: "MockApp#late",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 1),
            certFingerprint: "sha256:mock"
        )
        let mockConnection = MockConnection()
        let fence = TheFence(configuration: .init())
        fence.handoff.makeConnection = { _, _, _ in mockConnection }
        fence.handoff.connect(to: device)

        do {
            _ = try await fence.sendAndAwaitAction(.activate(.heistId("slow")), timeout: 0.05)
            XCTFail("Expected first action to time out")
        } catch let error as FenceError {
            guard case .actionTimeout = error else {
                return XCTFail("Expected .actionTimeout, got \(error)")
            }
        }

        guard let lastSent = mockConnection.sent.last, let timedOutRequestId = lastSent.1 else {
            return XCTFail("Expected the timed-out action to have been sent with a requestId")
        }

        // Deliver a response for the already-timed-out request. Must not crash,
        // must not throw, must leave the socket alone.
        let lateResult = ActionResult(success: true, method: .activate)
        mockConnection.onEvent?(
            .message(.actionResult(lateResult), requestId: timedOutRequestId, backgroundAccessibilityDelta: nil, accessibilityTrace: nil)
        )

        XCTAssertTrue(
            fence.handoff.isConnected,
            "A late response for an already-timed-out request must not affect the connection"
        )

        // A follow-up action still reaches the live socket — proves the late
        // response did not poison tracker state.
        let sendCountBefore = mockConnection.sent.count
        do {
            _ = try await fence.sendAndAwaitAction(.activate(.heistId("next")), timeout: 0.05)
        } catch let error as FenceError {
            guard case .actionTimeout = error else {
                return XCTFail("Expected .actionTimeout for follow-up (no auto-response), got \(error)")
            }
        }
        XCTAssertEqual(
            mockConnection.sent.count,
            sendCountBefore + 1,
            "Follow-up action must reach the live socket after a late response was dropped"
        )
    }

    /// With two actions in flight, a timeout on one must NOT cancel the other.
    /// Before the fix, `forceDisconnect` -> `onDisconnected` ->
    /// `cancelAllPendingRequests` would fail every sibling with
    /// `.connectionFailed`. Now the timeout is local to its own request and a
    /// sibling can still resolve from its own response.
    @ButtonHeistActor
    func testActionTimeoutDoesNotCancelSiblingPendingRequest() async throws {
        let device = DiscoveredDevice(
            id: "sibling-device",
            name: "MockApp#sibling",
            endpoint: .hostPort(host: .ipv6(.loopback), port: 1),
            certFingerprint: "sha256:mock"
        )
        let mockConnection = MockConnection()
        let fence = TheFence(configuration: .init())
        fence.handoff.makeConnection = { _, _, _ in mockConnection }
        fence.handoff.connect(to: device)

        // Launch a sibling with a generous timeout. Its requestId is captured
        // from `mockConnection.sent` once it has been registered with the
        // tracker.
        let sibling = Task { @ButtonHeistActor in
            try await fence.sendAndAwaitAction(.activate(.heistId("sibling")), timeout: 5)
        }

        // Yield until the sibling has actually been sent. Polling the actor
        // here avoids any sleep-based race.
        while mockConnection.sent.isEmpty {
            await Task.yield()
        }
        guard let firstSent = mockConnection.sent.first, let siblingRequestId = firstSent.1 else {
            sibling.cancel()
            return XCTFail("Expected sibling action to have been sent with a requestId")
        }

        // Now run a short-timeout action that will time out without a response.
        do {
            _ = try await fence.sendAndAwaitAction(.activate(.heistId("victim")), timeout: 0.05)
            sibling.cancel()
            XCTFail("Expected victim action to time out")
            return
        } catch let error as FenceError {
            guard case .actionTimeout = error else {
                sibling.cancel()
                return XCTFail("Expected .actionTimeout for victim, got \(error)")
            }
        }

        // Sibling must still be alive. Resolve it with its own response.
        let siblingResult = ActionResult(success: true, method: .activate)
        mockConnection.onEvent?(
            .message(.actionResult(siblingResult), requestId: siblingRequestId, backgroundAccessibilityDelta: nil, accessibilityTrace: nil)
        )

        let result = try await sibling.value
        XCTAssertTrue(
            result.success,
            "Sibling must resolve from its own response, not be cancelled by the victim's timeout"
        )
        XCTAssertTrue(
            fence.handoff.isConnected,
            "Connection must remain live after a sibling-only timeout"
        )
    }

    @ButtonHeistActor
    private func startHeistRecording(on fence: TheFence) async throws {
        let response = try await fence.execute(request: [
            "command": "start_heist",
            "identifier": "record-verified-actions-\(UUID().uuidString)",
            "app": "com.example.app",
        ])
        guard case .heistStarted = response else {
            return XCTFail("Expected heistStarted response, got \(response)")
        }
    }

    @ButtonHeistActor
    private func heistEvidenceCount(in fence: TheFence) -> Int? {
        guard case .active(let session) = fence.bookKeeper.phase,
              case .recording(let recording) = session.heistRecording else {
            return nil
        }
        recording.fileHandle.synchronizeFile()
        guard let data = try? Data(contentsOf: recording.filePath) else { return nil }
        return data.split(separator: 0x0A).count
    }
}
