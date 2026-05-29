import XCTest
import AccessibilitySnapshotModel
@testable import ButtonHeist
import TheScore

final class TheFenceTests: XCTestCase {
    private enum NonFenceWaitFailure: Error, Equatable, LocalizedError {
        case injected

        var errorDescription: String? {
            "injected wait failure"
        }
    }

    // MARK: - Command Enum

    func testMCPContractsUseToolNameAsCommandIdentity() {
        for contract in TheFence.Command.mcpToolContracts {
            guard let command = TheFence.Command(rawValue: contract.name) else {
                XCTFail("MCP tool name must be the canonical Fence command name: \(contract.name)")
                continue
            }

            XCTAssertEqual(command.descriptor.mcpExposure, .directTool)
        }
    }

    func testMCPReferenceDoesNotRenderDuplicateCommandIdentity() {
        let markdown = FenceCommandReference.mcpMarkdown()

        XCTAssertFalse(markdown.contains("| Tool | Command |"))
        XCTAssertFalse(markdown.contains("- Command:"))
    }

    // MARK: - Auth Token Status

    func testAuthApprovedStatusEmitsGeneratedTokenWhenNoTokenWasConfigured() {
        XCTAssertEqual(
            TheFence.authApprovedStatusMessage(token: "generated-token", configuredToken: nil),
            "BUTTONHEIST_TOKEN=generated-token"
        )
    }

    func testAuthApprovedStatusDoesNotEchoConfiguredToken() {
        XCTAssertNil(
            TheFence.authApprovedStatusMessage(token: "configured-token", configuredToken: "configured-token")
        )
    }

    func testAuthApprovedStatusDoesNotEchoApprovalTokenWhenUserConfiguredDifferentToken() {
        XCTAssertNil(
            TheFence.authApprovedStatusMessage(token: "generated-token", configuredToken: "user-specified-token")
        )
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
        XCTAssertEqual(details.hint, "Is the app running? Check 'buttonheist list_devices' to see available devices.")
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
        let failed = FenceResponse.sessionState(payload: SessionStatePayload(
            connected: false,
            phase: .failed,
            device: nil,
            isRecording: false,
            actionTimeoutSeconds: Timeouts.actionSeconds,
            longActionTimeoutSeconds: Timeouts.longActionSeconds,
            lastFailure: SessionFailurePayload(
                errorCode: "session.locked",
                phase: .session,
                retryable: true,
                message: nil,
                hint: "Reconnect after the active client releases the session."
            ),
            lastAction: nil
        ))
        let disconnected = FenceResponse.sessionState(payload: SessionStatePayload(
            connected: false,
            phase: .disconnected,
            device: nil,
            isRecording: false,
            actionTimeoutSeconds: Timeouts.actionSeconds,
            longActionTimeoutSeconds: Timeouts.longActionSeconds,
            lastFailure: nil,
            lastAction: nil
        ))

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
        let json = publicJSONObject(response)
        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertEqual(json["message"] as? String, "done")
    }

    func testErrorResponseJSON() {
        let response = FenceResponse.error("failed")
        let json = publicJSONObject(response)
        XCTAssertEqual(json["status"] as? String, "error")
        XCTAssertEqual(json["message"] as? String, "failed")
    }

    func testErrorResponseJSONIncludesFailureDetailsWhenPresent() {
        let response = FenceResponse.failure(FenceError.authFailed("bad token"))
        let json = publicJSONObject(response)

        XCTAssertEqual(json["status"] as? String, "error")
        let message = json["message"] as? String
        XCTAssertTrue(message?.contains("Auth failed: bad token") == true)
        XCTAssertFalse(message?.contains("Retry without --token") == true)
        XCTAssertFalse(message?.contains("Code: auth.failed") == true)
        XCTAssertEqual(json["errorCode"] as? String, "auth.failed")
        XCTAssertEqual(json["phase"] as? String, "auth")
        XCTAssertEqual(json["retryable"] as? Bool, false)
        XCTAssertNil(json["hint"])
    }

    func testAuthFailureHintPreservesConfiguredTokenRemediation() {
        let response = FenceResponse.failure(FenceError.authFailed("Invalid token. Retry with the configured token."))
        let json = publicJSONObject(response)

        XCTAssertEqual(json["errorCode"] as? String, "auth.failed")
        XCTAssertEqual(json["hint"] as? String, "Retry with the configured token.")
        let message = json["message"] as? String
        XCTAssertTrue(message?.contains("Retry with the configured token.") == true)
        XCTAssertFalse(message?.contains("Retry without --token") == true)
    }

    func testHelpResponseJSON() {
        let response = FenceResponse.help(commands: ["one_finger_tap", "swipe"])
        let json = publicJSONObject(response)
        XCTAssertEqual(json["status"] as? String, "ok")
        let commands = json["commands"] as? [String]
        XCTAssertEqual(commands, ["one_finger_tap", "swipe"])
    }

    func testStatusResponseJSON() {
        let response = FenceResponse.status(connected: true, deviceName: "MyApp")
        let json = publicJSONObject(response)
        XCTAssertEqual(json["connected"] as? Bool, true)
        XCTAssertEqual(json["device"] as? String, "MyApp")
    }

    func testScreenshotResponseJSON() {
        let element = HeistElement(
            heistId: "visible_total",
            description: "Total $12.34",
            label: "Total",
            value: "$12.34",
            identifier: "total",
            traits: [.staticText],
            frameX: 12,
            frameY: 680,
            frameWidth: 240,
            frameHeight: 32,
            activationPointX: 132,
            activationPointY: 696,
            actions: []
        )
        let response = FenceResponse.screenshot(
            path: "/tmp/shot.png",
            payload: ScreenPayload(
                pngData: "",
                width: 390,
                height: 844,
                interface: makeReceiptTestInterface([element])
            ),
            options: ScreenshotResponseOptions(includeInterface: true)
        )
        let json = publicJSONObject(response)
        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertEqual(json["path"] as? String, "/tmp/shot.png")
        XCTAssertEqual(json["width"] as? Double, 390)
        XCTAssertEqual(json["height"] as? Double, 844)
        let interface = try? XCTUnwrap(json["interface"] as? [String: Any])
        let tree = try? XCTUnwrap(interface?["tree"] as? [[String: Any]])
        let node = try? XCTUnwrap(tree?.first?["element"] as? [String: Any])
        XCTAssertEqual(node?["heistId"] as? String, "visible_total")
        XCTAssertEqual(node?["frameX"] as? Double, 12)
        XCTAssertEqual(node?["frameY"] as? Double, 680)
        XCTAssertEqual(node?["frameWidth"] as? Double, 240)
        XCTAssertEqual(node?["frameHeight"] as? Double, 32)
        XCTAssertEqual(node?["activationPointX"] as? Double, 132)
        XCTAssertEqual(node?["activationPointY"] as? Double, 696)
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
        let interface = makeReceiptTestInterface(
            nodes: [
                .element(title),
                .container(
                    makeReceiptTestContainer(type: .list, frameX: 0, frameY: 44, frameWidth: 390, frameHeight: 600),
                    children: [.element(wifi)]
                ),
            ]
        )

        let response = FenceResponse.interface(interface, detail: .full)
        let json = publicJSONObject(response)
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
        let interface = makeReceiptTestInterface(
            nodes: [
                .container(
                    makeReceiptTestScrollableContainer(
                        contentWidth: 390,
                        contentHeight: 1200,
                        frameX: 0,
                        frameY: 44,
                        frameWidth: 390,
                        frameHeight: 600
                    ),
                    children: [.element(element)]
                ),
            ]
        )

        let response = FenceResponse.interface(interface, detail: .summary)
        let json = publicJSONObject(response)
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
        let interface = makeReceiptTestInterface([element])

        let response = FenceResponse.interface(interface, detail: .full)
        let json = publicJSONObject(response)
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

    func testInterfacePublicJSONDataMatchesTypedJSONModel() throws {
        let element = HeistElement(
            heistId: "receipt_total",
            description: "Total $12.34",
            label: "Total",
            value: "$12.34",
            identifier: "total",
            traits: [.staticText],
            frameX: 12,
            frameY: 680,
            frameWidth: 240,
            frameHeight: 32,
            actions: []
        )
        let response = FenceResponse.interface(makeReceiptTestInterface([element]), detail: .summary)

        let encoded = try Self.jsonObject(from: response.jsonData())
        let dict = publicJSONObject(response)

        XCTAssertEqual(encoded["status"] as? String, dict["status"] as? String)
        XCTAssertEqual(encoded["detail"] as? String, "summary")
        let interface = try XCTUnwrap(encoded["interface"] as? [String: Any])
        XCTAssertNil(interface["elements"])
        let tree = try XCTUnwrap(interface["tree"] as? [[String: Any]])
        let node = try XCTUnwrap(tree.first?["element"] as? [String: Any])
        XCTAssertEqual(node["heistId"] as? String, "receipt_total")
        XCTAssertNil(node["frameY"])
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
        let interface = makeReceiptTestInterface(
            nodes: [
                .container(
                    makeReceiptTestScrollableContainer(
                        contentWidth: 390,
                        contentHeight: 1200,
                        frameX: 0,
                        frameY: 44,
                        frameWidth: 390,
                        frameHeight: 600
                    ),
                    children: [.element(element)]
                ),
            ]
        )

        let text = FenceResponse.interface(interface, detail: .summary).compactFormatted()
        XCTAssertTrue(text.contains("<scrollable = \"390x1200\">"))
        XCTAssertTrue(text.contains("  [0] wifi_toggle \"Wi-Fi\":\"On\" button hint=\"Double tap to toggle\" id=\"wifi\""))
        XCTAssertFalse(text.contains("frame"))
    }

    func testCompactElementLineNormalizesMissingStringsAndShowsDenseSignal() {
        let missingStrings = HeistElement(
            heistId: "rich_row",
            description: "",
            label: "",
            value: "",
            identifier: "",
            hint: "",
            traits: [.button, .staticText, .selected],
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            rotors: [HeistRotor(name: "Links"), HeistRotor(name: "")],
            actions: [.activate, .custom("Open details")]
        )
        let nilStrings = HeistElement(
            heistId: "rich_row",
            description: "",
            label: nil,
            value: nil,
            identifier: nil,
            hint: nil,
            traits: [.button, .staticText, .selected],
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            rotors: [HeistRotor(name: "Links")],
            actions: [.activate, .custom("Open details")]
        )
        let labeled = HeistElement(
            heistId: "cart-row",
            description: "Cart row",
            label: "Espresso, Espresso",
            value: "$ 3,00",
            identifier: "cart-row",
            hint: "Use \"menu\"",
            traits: [.staticText],
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: []
        )

        XCTAssertEqual(
            FenceResponse.compactElementLine(missingStrings, displayIndex: 4),
            "[4] rich_row \"\" button | staticText | selected {Open details} [Links]"
        )
        XCTAssertEqual(FenceResponse.compactElementLine(missingStrings), FenceResponse.compactElementLine(nilStrings))
        XCTAssertEqual(
            FenceResponse.compactElementLine(labeled),
            "cart-row \"Espresso, Espresso\":\"$ 3,00\" staticText hint=\"Use \\\"menu\\\"\" id=\"cart-row\""
        )
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
        let interface = makeReceiptTestInterface(
            nodes: [
                .container(
                    makeReceiptTestScrollableContainer(
                        contentWidth: 390,
                        contentHeight: 1200,
                        frameX: 0,
                        frameY: 44,
                        frameWidth: 390,
                        frameHeight: 600
                    ),
                    children: [.element(element)]
                ),
            ]
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
        let result = ActionResult(success: true, method: .activate, traceProjecting: .noChange(.init(elementCount: 5)))
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
            traceProjecting: .elementsChanged(.init(elementCount: 5, edits: ElementEdits()))
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

        XCTAssertEqual(text, "checkout | wait_for: error[timeout]: Timed out after 2.0s waiting for element")
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
            "wait_for: error[request.accessibility_tree_unavailable]: Could not access accessibility tree: no traversable app windows"
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
        XCTAssertTrue(text.contains("long_list_button \"Long List\" button"))
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
        let json = publicJSONObject(response)
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
        let json = publicJSONObject(response)
        XCTAssertEqual(json["status"] as? String, "expectation_failed")
        let expDict = json["expectation"] as? [String: Any]
        XCTAssertEqual(expDict?["met"] as? Bool, false)
    }

    func testActionWithoutExpectationJSON() {
        let result = ActionResult(success: true, method: .activate)
        let response = FenceResponse.action(result: result)
        let json = publicJSONObject(response)
        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertNil(json["expectation"])
    }

    func testActionSuccessPublicJSONDataMatchesTypedJSONModel() throws {
        let result = ActionResult(
            success: true,
            method: .getPasteboard,
            payload: .value("copied"),
            screenName: "Receipt",
            screenId: "receipt"
        )
        let response = FenceResponse.action(result: result)

        let encoded = try Self.jsonObject(from: response.jsonData())
        let dict = publicJSONObject(response)

        XCTAssertEqual(encoded["status"] as? String, dict["status"] as? String)
        XCTAssertEqual(encoded["method"] as? String, "get_pasteboard")
        XCTAssertEqual(encoded["value"] as? String, "copied")
        XCTAssertEqual(encoded["screenId"] as? String, "receipt")
        XCTAssertNil(encoded["errorClass"])
    }

    func testTreeUnavailableActionJSONIncludesLocalDiagnosticDetails() {
        let result = ActionResult(
            success: false,
            method: .explore,
            message: "Could not access accessibility tree: no traversable app windows",
            errorKind: .actionFailed
        )
        let response = FenceResponse.action(result: result)

        let json = publicJSONObject(response)

        XCTAssertEqual(json["status"] as? String, "error")
        XCTAssertEqual(json["errorClass"] as? String, "actionFailed")
        XCTAssertEqual(json["errorCode"] as? String, "request.accessibility_tree_unavailable")
        XCTAssertEqual(json["phase"] as? String, "request")
        XCTAssertEqual(json["retryable"] as? Bool, true)
        XCTAssertTrue((json["hint"] as? String)?.contains("traversable app window") == true)
    }

    func testActionFailurePublicJSONDataMatchesTypedJSONModel() throws {
        let result = ActionResult(
            success: false,
            method: .waitFor,
            message: "Could not access accessibility tree: no traversable app windows",
            errorKind: .actionFailed
        )
        let response = FenceResponse.action(result: result)

        let encoded = try Self.jsonObject(from: response.jsonData())
        let dict = publicJSONObject(response)

        XCTAssertEqual(encoded["status"] as? String, dict["status"] as? String)
        XCTAssertEqual(encoded["errorClass"] as? String, "actionFailed")
        XCTAssertEqual(encoded["errorCode"] as? String, "request.accessibility_tree_unavailable")
        XCTAssertEqual(encoded["phase"] as? String, "request")
        XCTAssertEqual(encoded["retryable"] as? Bool, true)
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
        let json = publicJSONObject(FenceResponse.action(result: result))

        XCTAssertEqual(details?.errorCode, "request.accessibility_tree_unavailable")
        XCTAssertEqual(
            compact,
            "wait_for: error[request.accessibility_tree_unavailable]: Could not access accessibility tree: no traversable app windows"
        )
        XCTAssertEqual(json["errorClass"] as? String, "actionFailed")
        XCTAssertEqual(json["errorCode"] as? String, "request.accessibility_tree_unavailable")
    }

    // MARK: - FenceResponse: Typed Expectation JSON

    func testActionExpectationJSONMet() throws {
        let result = ExpectationResult(met: true, expectation: .elementsChanged, actual: "elementsChanged")
        let json = try decodeActionExpectationJSON(result)
        XCTAssertEqual(json.status, "ok")
        XCTAssertEqual(json.expectation?.met, true)
        XCTAssertEqual(json.expectation?.actual, "elementsChanged")
        XCTAssertNotNil(json.expectation?.expected)
    }

    func testActionExpectationJSONDelivery() throws {
        let result = ExpectationResult(met: true, expectation: nil, actual: "delivered")
        let json = try decodeActionExpectationJSON(result)
        XCTAssertEqual(json.status, "ok")
        XCTAssertEqual(json.expectation?.met, true)
        XCTAssertEqual(json.expectation?.actual, "delivered")
        XCTAssertNil(json.expectation?.expected)
    }

    func testActionExpectationJSONElementUpdatedExpectation() throws {
        let result = ExpectationResult(met: false, expectation: .elementUpdated(newValue: "hello"), actual: "counter: value: world → goodbye")
        let json = try decodeActionExpectationJSON(result)
        XCTAssertEqual(json.status, "expectation_failed")
        XCTAssertEqual(json.expectation?.met, false)
        XCTAssertEqual(json.expectation?.actual, "counter: value: world → goodbye")
        XCTAssertNotNil(json.expectation?.expected)
    }

    // MARK: - FenceResponse: Batch with Expectations

    func testBatchWithExpectationsFormatting() {
        let response = FenceResponse.batch(
            outcomes: [
                makeExpectationBatchOutcome(met: true),
                makeExpectationBatchOutcome(met: false),
            ],
            totalTimingMs: 100
        )
        let text = response.humanFormatted()
        XCTAssertTrue(text.contains("2 step(s) completed"))
        XCTAssertTrue(text.contains("[expectations: 1/2 met]"))
    }

    func testBatchWithoutExpectationsFormatting() {
        let response = FenceResponse.batch(
            outcomes: [makeBatchOutcome()],
            totalTimingMs: 50
        )
        let text = response.humanFormatted()
        XCTAssertTrue(text.contains("1 step(s) completed"))
        XCTAssertFalse(text.contains("expectations"))
    }

    func testBatchWithFailedIndexFormatting() {
        let response = FenceResponse.batch(
            outcomes: [
                makeBatchOutcome(),
                makeBatchOutcome(response: .error("failed"), stopsBatch: true),
            ],
            totalTimingMs: 80
        )
        let text = response.humanFormatted()
        XCTAssertTrue(text.contains("(failed at step 1)"))
    }

    func testBatchWithExpectationsJSON() {
        let response = FenceResponse.batch(
            outcomes: [
                makeExpectationBatchOutcome(met: true),
                makeExpectationBatchOutcome(met: true),
                makeExpectationBatchOutcome(met: false),
            ],
            totalTimingMs: 50
        )
        let json = publicJSONObject(response)
        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertEqual(json["completedSteps"] as? Int, 3)
        let expectations = json["expectations"] as? [String: Any]
        XCTAssertNotNil(expectations)
        XCTAssertEqual(expectations?["checked"] as? Int, 3)
        XCTAssertEqual(expectations?["met"] as? Int, 2)
        XCTAssertEqual(expectations?["allMet"] as? Bool, false)
    }

    func testBatchWithoutExpectationsJSON() {
        let response = FenceResponse.batch(
            outcomes: [makeBatchOutcome()],
            totalTimingMs: 50
        )
        let json = publicJSONObject(response)
        XCTAssertNil(json["expectations"])
    }

    func testBatchAllExpectationsMetJSON() {
        let response = FenceResponse.batch(
            outcomes: [
                makeExpectationBatchOutcome(met: true),
                makeExpectationBatchOutcome(met: true),
            ],
            totalTimingMs: 0
        )
        let json = publicJSONObject(response)
        let expectations = json["expectations"] as? [String: Any]
        XCTAssertEqual(expectations?["allMet"] as? Bool, true)
    }

    func testBatchJSONAndCompactDeriveFromTypedOutcomes() throws {
        let response = FenceResponse.batch(
            outcomes: [
                makeBatchOutcome(command: "activate"),
                makeBatchOutcome(command: "bad_step", response: .error("boom"), stopsBatch: true),
                .skipped(command: "later_step", afterFailedIndex: 1),
            ],
            totalTimingMs: 42
        )

        XCTAssertEqual(
            response.compactFormatted(),
            """
            batch: 2 steps in 42ms (failed at 1)
              [0] activate
              [1] bad_step → error: boom
              [2] later_step → error: skipped: stop_on_error stopped batch after step 1
            """
        )

        let json = publicJSONObject(response)
        XCTAssertEqual(json["status"] as? String, "partial")
        XCTAssertEqual(json["completedSteps"] as? Int, 2)
        XCTAssertEqual(json["failedIndex"] as? Int, 1)
        let results = try XCTUnwrap(json["results"] as? [[String: Any]])
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[1]["status"] as? String, "error")
        let summaries = try XCTUnwrap(json["stepSummaries"] as? [[String: Any]])
        XCTAssertEqual(summaries.count, 3)
        XCTAssertEqual(summaries[2]["error"] as? String, "skipped: stop_on_error stopped batch after step 1")
    }

    func testSessionStateJSONAndCompactRenderTypedPayload() throws {
        let response = FenceResponse.sessionState(payload: SessionStatePayload(
            connected: true,
            phase: .connected,
            device: SessionDevicePayload(
                deviceName: "MockApp",
                appName: "MockApp",
                connectionType: .network,
                shortId: "abc123"
            ),
            isRecording: false,
            actionTimeoutSeconds: Timeouts.actionSeconds,
            longActionTimeoutSeconds: Timeouts.longActionSeconds,
            lastFailure: nil,
            lastAction: SessionLastActionPayload(
                method: .activate,
                success: true,
                message: nil,
                latencyMs: 17
            )
        ))

        XCTAssertEqual(response.compactFormatted(), "session: connected")
        let json = publicJSONObject(response)
        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertEqual(json["connected"] as? Bool, true)
        XCTAssertEqual(json["phase"] as? String, "connected")
        XCTAssertEqual(json["deviceName"] as? String, "MockApp")
        XCTAssertEqual(json["connectionType"] as? String, "network")
        let lastAction = try XCTUnwrap(json["lastAction"] as? [String: Any])
        XCTAssertEqual(lastAction["method"] as? String, "activate")
        XCTAssertEqual(lastAction["success"] as? Bool, true)
        XCTAssertEqual(lastAction["latency_ms"] as? Int, 17)
        XCTAssertNil(lastAction["message"])
    }

    func testSessionStatePublicJSONDataMatchesTypedJSONModel() throws {
        let response = FenceResponse.sessionState(payload: SessionStatePayload(
            connected: false,
            phase: .failed,
            device: nil,
            isRecording: true,
            actionTimeoutSeconds: 3,
            longActionTimeoutSeconds: 9,
            lastFailure: SessionFailurePayload(
                errorCode: "connection.failed",
                phase: .transport,
                retryable: true,
                message: "Connection dropped",
                hint: "Reconnect"
            ),
            lastAction: nil
        ))

        let encoded = try Self.jsonObject(from: response.jsonData())
        let dict = publicJSONObject(response)

        XCTAssertEqual(encoded["status"] as? String, dict["status"] as? String)
        XCTAssertEqual(encoded["phase"] as? String, "failed")
        XCTAssertEqual(encoded["isRecording"] as? Bool, true)
        let failure = try XCTUnwrap(encoded["lastFailure"] as? [String: Any])
        XCTAssertEqual(failure["errorCode"] as? String, "connection.failed")
        XCTAssertEqual(failure["phase"] as? String, "transport")
        XCTAssertEqual(failure["retryable"] as? Bool, true)
    }

    func testRecordingPublicJSONDataMatchesTypedJSONModel() throws {
        let start = Date(timeIntervalSince1970: 0)
        let payload = RecordingPayload(
            videoData: Data("video".utf8).base64EncodedString(),
            width: 390,
            height: 844,
            duration: 2.0,
            frameCount: 16,
            fps: 8,
            startTime: start,
            endTime: start.addingTimeInterval(2.0),
            stopReason: .manual,
            interactionLog: [
                InteractionEvent(
                    timestamp: 0,
                    command: .activate(.matcher(ElementMatcher(label: "Pay"))),
                    result: ActionResult(success: true, method: .activate)
                )
            ]
        )
        let response = FenceResponse.recordingExpanded(
            path: "/tmp/recording.mp4",
            payload: payload,
            options: RecordingResponseOptions(inlineData: true, includeInteractionLog: true)
        )

        let encoded = try Self.jsonObject(from: response.jsonData())
        let dict = publicJSONObject(response)

        XCTAssertEqual(encoded["status"] as? String, dict["status"] as? String)
        XCTAssertEqual(encoded["path"] as? String, "/tmp/recording.mp4")
        XCTAssertEqual(encoded["videoData"] as? String, payload.videoData)
        XCTAssertEqual(encoded["interactionCount"] as? Int, 1)
        XCTAssertEqual((encoded["interactionLog"] as? [[String: Any]])?.count, 1)
    }

    func testJSONEncodingFailureReturnsDiagnosticErrorInsteadOfSuccess() {
        let response = FenceResponse.screenshot(
            path: "/tmp/shot.png",
            payload: ScreenPayload(
                pngData: "",
                width: .nan,
                height: 844,
                interface: Interface(timestamp: Date(), tree: [])
            )
        )

        let json = publicJSONObject(response)

        XCTAssertEqual(json["status"] as? String, "error")
        XCTAssertEqual(json["errorCode"] as? String, "formatting.json_encoding_failed")
        XCTAssertEqual(json["phase"] as? String, "client")
        XCTAssertEqual(json["retryable"] as? Bool, false)
        XCTAssertNil(json["path"])
    }

    func testJSONEncodingFailurePreservesRequestId() throws {
        let response = FenceResponse.screenshot(
            path: "/tmp/shot.png",
            payload: ScreenPayload(
                pngData: "",
                width: .nan,
                height: 844,
                interface: Interface(timestamp: Date(), tree: [])
            )
        )

        let json = try Self.jsonObject(from: response.jsonData(requestId: .string("req-json-failure")))

        XCTAssertEqual(json["id"] as? String, "req-json-failure")
        XCTAssertEqual(json["status"] as? String, "error")
        XCTAssertEqual(json["errorCode"] as? String, "formatting.json_encoding_failed")
        XCTAssertNil(json["path"])
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
        let before = makeReceiptTestInterface([
            HeistElement(
                heistId: "label1",
                description: "Label",
                label: "Label",
                value: "a",
                identifier: nil,
                traits: [.staticText],
                frameX: 0,
                frameY: 0,
                frameWidth: 100,
                frameHeight: 44,
                actions: []
            ),
        ])
        let after = makeReceiptTestInterface([
            HeistElement(
                heistId: "label1",
                description: "Label",
                label: "Label",
                value: "b",
                identifier: nil,
                traits: [.staticText],
                frameX: 0,
                frameY: 10,
                frameWidth: 100,
                frameHeight: 44,
                actions: []
            ),
        ])
        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: makeReceiptTestTrace(before: before, after: after)
        )
        let response = FenceResponse.action(result: result)
        let json = publicJSONObject(response)
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
        let before = makeReceiptTestInterface([
            HeistElement(
                heistId: "img",
                description: "Image",
                label: "Image",
                value: nil,
                identifier: nil,
                traits: [.image],
                frameX: 0,
                frameY: 0,
                frameWidth: 50,
                frameHeight: 50,
                actions: []
            ),
        ])
        let after = makeReceiptTestInterface([
            HeistElement(
                heistId: "img",
                description: "Image",
                label: "Image",
                value: nil,
                identifier: nil,
                traits: [.image],
                frameX: 0,
                frameY: 5,
                frameWidth: 50,
                frameHeight: 50,
                actions: []
            ),
        ])
        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: makeReceiptTestTrace(before: before, after: after)
        )
        let response = FenceResponse.action(result: result)
        let json = publicJSONObject(response)
        let deltaDict = json["delta"] as! [String: Any]
        // Geometry-only updates are dropped — and with no other edits, the
        // entire `edits` key is omitted from the delta dictionary.
        XCTAssertNil(deltaDict["edits"], "Geometry-only updates should be dropped entirely")
    }

    func testActionJsonDeltaIncludesCaptureEdge() {
        let interface = makeReceiptTestInterface(elementCount: 3)
        let trace = makeReceiptTestTrace(before: interface, after: interface)
        let result = ActionResult(success: true, method: .activate, accessibilityTrace: trace)
        let response = FenceResponse.action(result: result)
        let json = publicJSONObject(response)
        let deltaDict = json["delta"] as! [String: Any]
        let edgeDict = deltaDict["captureEdge"] as! [String: Any]
        let before = edgeDict["before"] as! [String: Any]
        let after = edgeDict["after"] as! [String: Any]

        XCTAssertEqual(before["sequence"] as? Int, 1)
        XCTAssertEqual(before["hash"] as? String, trace.captures[0].hash)
        XCTAssertEqual(after["sequence"] as? Int, 2)
        XCTAssertEqual(after["hash"] as? String, trace.captures[1].hash)
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

        let json = publicJSONObject(response)
        XCTAssertEqual(json["errorCode"] as? String, "session.locked")
        XCTAssertTrue((json["message"] as? String)?.contains("owner driver id: driver-a") == true)
        XCTAssertTrue((json["message"] as? String)?.contains("remaining timeout: 8s") == true)
        XCTAssertTrue((json["hint"] as? String)?.contains("BUTTONHEIST_DRIVER_ID") == true)
    }

    func testFenceErrorTaxonomy() {
        let cases: [(FenceError, String, FailurePhase, Bool, String?)] = [
            (.invalidRequest("bad"), "request.invalid", .request, false, "Fix the request"),
            (.noDeviceFound, "discovery.no_device_found", .discovery, true, "Start the app"),
            (
                .noMatchingDevice(filter: "Demo", available: ["Other"]),
                "discovery.no_matching_device", .discovery, false, "Check the device filter"
            ),
            (.connectionTimeout, "setup.timeout", .setup, true, "buttonheist list_devices"),
            (.connectionFailed("refused"), "connection.failed", .transport, true, "buttonheist list_devices"),
            (
                .connectionFailure(ConnectionFailure(disconnectReason: .missingFingerprint)),
                "tls.missing_fingerprint", .tls, false, "TLS certificate fingerprint"
            ),
            (.sessionLocked("busy"), "session.locked", .session, true, "current driver"),
            (.authFailed("denied"), "auth.failed", .authentication, false, nil),
            (
                .authFailed("Invalid token. Retry without a token to request a fresh session."),
                "auth.failed", .authentication, false, "without --token"
            ),
            (
                .authApprovalPending("Waiting for approval on the device."),
                "auth.approval_pending", .authentication, true, "Tap Allow"
            ),
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
            (.authFailure, "auth.failed", .authentication, false, nil),
            (.authApprovalPending, "auth.approval_pending", .authentication, true, "Tap Allow"),
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

        let wrongToken = ServerError(
            kind: .authFailure,
            message: "Invalid token. Retry without a token to request a fresh session."
        )
        XCTAssertEqual(wrongToken.hint, "Retry without --token to request a fresh session.")
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

        let json = publicJSONObject(response)
        XCTAssertEqual(json["errorCode"] as? String, "tls.missing_fingerprint")
        XCTAssertEqual(json["phase"] as? String, "tls")
        XCTAssertEqual(json["retryable"] as? Bool, false)
        XCTAssertTrue((json["message"] as? String)?.contains("connection failed in tls") == true)
    }

    @ButtonHeistActor
    func testDisconnectCancelsPendingActionWaitWithReason() async {
        let (fence, mockConnection) = makeConnectedFence()
        fence.handoff.connect(to: TheFenceFixtures.testDevice)

        let waitTask = Task { @ButtonHeistActor in
            try await fence.waitForActionResult(requestId: "pending", timeout: 10)
        }
        await Task.yield()

        mockConnection.onEvent?(.disconnected(.serverClosed))

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
    func testFailedConnectionStateCancelsPendingActionWait() async {
        let (fence, mockConnection) = makeConnectedFence()
        fence.handoff.connect(to: TheFenceFixtures.testDevice)

        let waitTask = Task { @ButtonHeistActor in
            try await fence.waitForActionResult(requestId: "pending", timeout: 10)
        }
        await Task.yield()

        mockConnection.onEvent?(.message(
            .error(ServerError(kind: .general, message: "server died")),
            requestId: nil,
            accessibilityTrace: nil
        ))

        do {
            _ = try await waitTask.value
            XCTFail("Expected pending wait to fail")
        } catch FenceError.connectionFailed(let message) {
            XCTAssertEqual(message, "server died")
        } catch {
            XCTFail("Expected connectionFailed, got \(error)")
        }
    }

    @ButtonHeistActor
    func testDisconnectCancelsPendingRecordingWaitWithReason() async {
        let (fence, mockConnection) = makeConnectedFence()
        fence.handoff.connect(to: TheFenceFixtures.testDevice)

        let waitTask = Task { @ButtonHeistActor in
            try await fence.waitForRecording(timeout: 10)
        }
        await Task.yield()

        mockConnection.onEvent?(.disconnected(.serverClosed))

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
    func testStopDisablesAutoReconnectAndDisconnects() async {
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

        fence.stop()

        assertDisconnected(fence.handoff.connectionPhase)
    }

    @ButtonHeistActor
    func testDisconnectClearsLastActionSessionState() async {
        let (fence, mockConnection) = makeConnectedFence()
        fence.handoff.connect(to: TheFenceFixtures.testDevice)
        fence.recordCompletedAction(ActionResult(success: true, method: .activate))
        XCTAssertNotNil(fence.currentSessionState().lastAction)

        mockConnection.onEvent?(.disconnected(.serverClosed))

        XCTAssertNil(fence.currentSessionState().lastAction)
    }

    func testCommandExecutionStateOwnsLastActionAndProjectsSessionPayload() {
        let state = TheFence.CommandExecutionState()
        XCTAssertNil(state.lastAction.sessionPayload)

        state.completeAction(ActionResult(success: true, method: .activate))
        XCTAssertEqual(
            state.lastAction.sessionPayload,
            SessionLastActionPayload(
                method: .activate,
                success: true,
                message: nil,
                latencyMs: 0
            )
        )

        state.noteDispatchedResponse(
            .action(result: ActionResult(success: true, method: .activate)),
            latencyMs: 17
        )

        XCTAssertEqual(
            state.lastAction.sessionPayload,
            SessionLastActionPayload(
                method: .activate,
                success: true,
                message: nil,
                latencyMs: 17
            )
        )

        state.noteDispatchedResponse(.ok(message: "noop"), latencyMs: 99)
        XCTAssertEqual(
            state.lastAction.sessionPayload,
            SessionLastActionPayload(
                method: .activate,
                success: true,
                message: nil,
                latencyMs: 17
            )
        )

        state.reset()
        XCTAssertNil(state.lastAction.sessionPayload)
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

    @ButtonHeistActor
    func testAsyncTransportSendFailureFailsPendingActionWithoutWaitingForTimeout() async {
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mockConnection = MockConnection()
        mockConnection.connectEventsOverride = [.connected]
        mockConnection.asyncSendFailure = .transportFailed("socket write failed")
        let fence = TheFence(configuration: .init())
        fence.handoff.makeConnection = { _, _, _ in mockConnection }
        fence.handoff.connect(to: device)

        do {
            _ = try await fence.sendAndAwaitAction(.activate(.heistId("write-fails")), timeout: 10)
            XCTFail("Expected async send failure")
        } catch FenceError.actionFailed(let message) {
            XCTAssertTrue(message.contains("Transport send failed"))
            XCTAssertTrue(message.contains("socket write failed"))
        } catch FenceError.actionTimeout {
            XCTFail("Async transport send failure must fail the pending tracker instead of timing out")
        } catch {
            XCTFail("Expected actionFailed, got \(error)")
        }
    }

    @ButtonHeistActor
    func testSendAndAwaitActionPropagatesNonFenceWaitFailure() async {
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mockConnection = MockConnection()
        mockConnection.connectEventsOverride = [.connected]
        let fence = TheFence(configuration: .init())
        fence.handoff.makeConnection = { _, _, _ in mockConnection }
        fence.handoff.connect(to: device)

        let waitTask = Task { @ButtonHeistActor in
            try await fence.sendAndAwaitAction(.activate(.heistId("custom-failure")), timeout: 5)
        }

        while mockConnection.sent.isEmpty {
            await Task.yield()
        }

        guard let requestId = mockConnection.sent.last?.1 else {
            waitTask.cancel()
            return XCTFail("Expected action request to have been sent with a requestId")
        }

        fence.pendingRequests.resolveAction(
            requestId: requestId,
            result: .failure(NonFenceWaitFailure.injected)
        )

        do {
            _ = try await waitTask.value
            XCTFail("Expected injected wait failure")
        } catch NonFenceWaitFailure.injected {
            // expected: transport waits must not coerce unknown tracker failures into actionFailed.
        } catch FenceError.actionFailed(let message) {
            XCTFail("Expected injected wait failure, got actionFailed: \(message)")
        } catch {
            XCTFail("Expected injected wait failure, got \(error)")
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
        XCTAssertEqual(Timeouts.healthSeconds, 3)
        XCTAssertEqual(Timeouts.longActionSeconds, 30)
    }

    // MARK: - TheFence execute (error cases)

    @ButtonHeistActor
    func testMissingCommandReturnsSchemaError() async throws {
        let arguments = TheFence.CommandArgumentEnvelope(values: [:])

        XCTAssertThrowsError(try arguments.requiredSchemaString("command")) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for command: observed missing; expected string"
            )
        }
    }

    @ButtonHeistActor
    func testExecuteHelp() async throws {
        let fence = TheFence(configuration: .init())
        let response = try await fence.execute(command: .help)
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
        let response = try await fence.execute(command: .quit)
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

        let response = try await fence.execute(command: .getSessionState)

        if case .sessionState(let payload) = response {
            XCTAssertEqual(payload.connected, false)
            XCTAssertEqual(payload.phase, .disconnected)
            XCTAssertNil(payload.lastFailure)
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

        let response = try await fence.execute(command: .getSessionState)

        guard case .sessionState(let payload) = response else {
            return XCTFail("Expected sessionState response, got \(response)")
        }
        XCTAssertEqual(payload.connected, true)
        XCTAssertEqual(payload.phase, .connected)
        XCTAssertEqual(payload.device?.deviceName, "MockApp")
        XCTAssertEqual(payload.device?.appName, "MockApp")
        XCTAssertEqual(payload.device?.connectionType, .network)
        XCTAssertEqual(payload.isRecording, false)
        XCTAssertEqual(payload.actionTimeoutSeconds, Timeouts.actionSeconds)
        XCTAssertEqual(payload.longActionTimeoutSeconds, Timeouts.longActionSeconds)
        XCTAssertNil(payload.lastFailure)
    }

    @ButtonHeistActor
    func testRecordingPhaseIsFenceOwnedFromHandoffEvents() async throws {
        let mockConnection = MockConnection()
        mockConnection.serverInfo = TheFenceFixtures.testServerInfo

        let fence = TheFence(configuration: .init())
        fence.handoff.makeConnection = { _, _, _ in mockConnection }
        fence.handoff.connect(to: TheFenceFixtures.testDevice)

        fence.handoff.handleServerMessage(.recordingStarted, requestId: nil)
        let recordingState = try await fence.execute(command: .getSessionState)
        guard case .sessionState(let recordingPayload) = recordingState else {
            return XCTFail("Expected sessionState response, got \(recordingState)")
        }
        XCTAssertEqual(recordingPayload.isRecording, true)

        fence.handoff.handleServerMessage(.recordingStopped, requestId: nil)
        let stoppedState = try await fence.execute(command: .getSessionState)
        guard case .sessionState(let stoppedPayload) = stoppedState else {
            return XCTFail("Expected sessionState response, got \(stoppedState)")
        }
        XCTAssertEqual(stoppedPayload.isRecording, false)

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
        let completedState = try await fence.execute(command: .getSessionState)
        guard case .sessionState(let completedPayload) = completedState else {
            return XCTFail("Expected sessionState response, got \(completedState)")
        }
        XCTAssertEqual(completedPayload.isRecording, false)
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

        let response = try await fence.execute(command: .getSessionState)
        guard case .sessionState(let payload) = response else {
            return XCTFail("Expected sessionState response, got \(response)")
        }
        XCTAssertEqual(payload.isRecording, false)
        XCTAssertEqual(payload.connected, false)
    }

    @ButtonHeistActor
    func testGetSessionStateFailedAuthReportsFailureDetails() async throws {
        let fence = TheFence(configuration: .init())
        fence.handoff.handleServerMessage(
            .error(ServerError(kind: .authFailure, message: "bad token")),
            requestId: nil
        )

        let response = try await fence.execute(command: .getSessionState)

        guard case .sessionState(let payload) = response else {
            return XCTFail("Expected sessionState response, got \(response)")
        }
        XCTAssertEqual(payload.connected, false)
        XCTAssertEqual(payload.phase, .failed)
        let failure = try XCTUnwrap(payload.lastFailure)
        XCTAssertEqual(failure.errorCode, "auth.failed")
        XCTAssertEqual(failure.phase, .authentication)
        XCTAssertEqual(failure.retryable, false)
        XCTAssertEqual(failure.message, "Authentication failed: bad token")
        XCTAssertNil(failure.hint)
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

        let response = try await fence.execute(command: .getSessionState)

        guard case .sessionState(let payload) = response else {
            return XCTFail("Expected sessionState response, got \(response)")
        }
        XCTAssertEqual(payload.connected, false)
        XCTAssertEqual(payload.phase, .disconnected)
        let failure = try XCTUnwrap(payload.lastFailure)
        XCTAssertEqual(failure.errorCode, "transport.server_closed")
        XCTAssertEqual(failure.phase, .transport)
        XCTAssertEqual(failure.retryable, true)
        XCTAssertEqual(failure.hint, "Check that the app is still running and reachable, then retry.")
    }

    @ButtonHeistActor
    func testGetSessionStateSendsNoHierarchyObservationMessages() async throws {
        let mockConnection = MockConnection()
        mockConnection.serverInfo = TheFenceFixtures.testServerInfo

        let fence = TheFence(configuration: .init())
        fence.handoff.makeConnection = { _, _, _ in mockConnection }
        fence.handoff.connect(to: TheFenceFixtures.testDevice)
        mockConnection.sent.removeAll()

        _ = try await fence.execute(command: .getSessionState)

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
        let response = try await fence.execute(command: .getSessionLog)
        if case .error(let message, let details) = response {
            XCTAssertTrue(message.contains("No active session"))
            XCTAssertEqual(details?.errorCode, "request.invalid")
            XCTAssertEqual(details?.phase, .request)
            XCTAssertFalse(details?.retryable ?? true)
        } else {
            XCTFail("Expected error response when no session active, got \(response)")
        }
    }

    @ButtonHeistActor
    func testExecuteArchiveSessionReturnsErrorWhenIdle() async throws {
        let fence = TheFence(configuration: .init())
        do {
            _ = try await fence.execute(command: .archiveSession)
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
        try fence.bookKeeper.logCommand(fence.parseRequest(
            command: .getSessionState,
            values: ["requestId": .string("r1")]
        ))

        let response = try await fence.execute(command: .archiveSession)

        guard case .archiveResult(let path, let snapshot) = response else {
            return XCTFail("Expected archiveResult response, got \(response)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        // 2 = the explicit get_session_state call above + the archive_session request,
        // which execute() logs before dispatching to the handler.
        XCTAssertEqual(snapshot.counts.commandCount, 2)
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
            _ = try await fence.execute(
                command: .activate,
                values: ["target": targetArgumentValue(identifier: "button")]
            )
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

    @ButtonHeistActor
    func testStartRecordingRejectsWhileCompletionWaitIsPendingAfterStopped() async throws {
        let (fence, _) = makeConnectedFence()
        try await fence.start()
        fence.handoff.onRecordingEvent?(.started)

        let completionWait = Task { @ButtonHeistActor in
            try await fence.waitForRecording(timeout: 5.0)
        }
        while !fence.isWaitingForRecordingCompletion {
            await Task.yield()
        }

        fence.handoff.onRecordingEvent?(.stopped)
        XCTAssertFalse(fence.isRecording)
        XCTAssertTrue(fence.isWaitingForRecordingCompletion)

        do {
            _ = try await fence.execute(command: .startRecording)
            XCTFail("Expected start_recording conflict while completion wait is pending")
        } catch let error as FenceError {
            guard case .invalidRequest(let message) = error else {
                completionWait.cancel()
                return XCTFail("Expected invalidRequest, got \(error)")
            }
            XCTAssertTrue(
                message.contains("already waiting for completion"),
                "Expected completion wait conflict, got: \(message)"
            )
        } catch {
            completionWait.cancel()
            XCTFail("Expected FenceError.invalidRequest, got \(error)")
        }

        completionWait.cancel()
        do {
            _ = try await completionWait.value
            XCTFail("Expected completion waiter cancellation")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    @ButtonHeistActor
    func testStartRecordingAlreadyRecordingThrowsInvalidRequest() async throws {
        let (fence, _) = makeConnectedFence()
        try await fence.start()
        fence.handoff.onRecordingEvent?(.started)

        do {
            _ = try await fence.execute(command: .startRecording)
            XCTFail("Expected start_recording conflict while recording")
        } catch let error as FenceError {
            guard case .invalidRequest(let message) = error else {
                return XCTFail("Expected invalidRequest, got \(error)")
            }
            XCTAssertTrue(
                message.contains("Recording already in progress"),
                "Expected already recording conflict, got: \(message)"
            )
        } catch {
            XCTFail("Expected FenceError.invalidRequest, got \(error)")
        }
    }

    @ButtonHeistActor
    func testStoppedKeepsCompletionWaitUntilPayload() async throws {
        let fence = TheFence(configuration: .init())
        fence.handoff.onRecordingEvent?(.started)
        let expectedPayload = RecordingPayload(
            videoData: "dGVzdA==", width: 390, height: 844,
            duration: 2.0, frameCount: 16, fps: 8,
            startTime: Date(), endTime: Date(), stopReason: .manual
        )

        let completionWait = Task { @ButtonHeistActor in
            try await fence.waitForRecording(timeout: 5.0)
        }
        while !fence.isWaitingForRecordingCompletion {
            await Task.yield()
        }

        fence.handoff.onRecordingEvent?(.stopped)
        XCTAssertFalse(fence.isRecording)
        XCTAssertTrue(fence.isWaitingForRecordingCompletion)

        fence.handoff.onRecordingEvent?(.completed(expectedPayload))

        let payload = try await completionWait.value
        XCTAssertEqual(payload.videoData, expectedPayload.videoData)
        XCTAssertFalse(fence.isWaitingForRecordingCompletion)
    }

    @ButtonHeistActor
    func testStartRecordingErrorResolvesStartWaitAndAllowsNextStart() async throws {
        let (fence, mockConn) = makeConnectedFence()
        try await fence.start()
        mockConn.autoResponse = { message in
            if case .startRecording = message {
                Task { @ButtonHeistActor in
                    fence.handoff.onRecordingEvent?(.failed("permission denied"))
                }
            }
            return .actionResult(ActionResult(success: true, method: .activate))
        }

        do {
            try await fence.startRecordingAndWait(
                config: RecordingConfig(fps: 8, maxDuration: 60),
                timeout: 5.0
            )
            XCTFail("Expected start recording failure")
        } catch let error as FenceError {
            guard case .actionFailed(let message) = error else {
                return XCTFail("Expected actionFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("permission denied"))
        }

        mockConn.autoResponse = { message in
            if case .startRecording = message {
                return .recordingStarted
            }
            return .actionResult(ActionResult(success: true, method: .activate))
        }

        try await fence.startRecordingAndWait(
            config: RecordingConfig(fps: 8, maxDuration: 60),
            timeout: 5.0
        )
        XCTAssertTrue(fence.isRecording)
    }

    @ButtonHeistActor
    func testCompletionFailureClearsStateAndAllowsNextStart() async throws {
        let (fence, mockConn) = makeConnectedFence()
        try await fence.start()
        mockConn.autoResponse = { message in
            if case .startRecording = message {
                Task { @ButtonHeistActor in
                    for _ in 0..<200 where !fence.isWaitingForRecordingCompletion {
                        await Task.yield()
                    }
                    fence.handoff.onRecordingEvent?(.failed("encoder failed"))
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
            XCTFail("Expected completion failure")
        } catch let error as FenceError {
            guard case .actionFailed(let message) = error else {
                return XCTFail("Expected actionFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("encoder failed"))
        }

        mockConn.autoResponse = { message in
            if case .startRecording = message {
                return .recordingStarted
            }
            return .actionResult(ActionResult(success: true, method: .activate))
        }

        try await fence.startRecordingAndWait(
            config: RecordingConfig(fps: 8, maxDuration: 60),
            timeout: 5.0
        )
        XCTAssertTrue(fence.isRecording)
    }

    @ButtonHeistActor
    func testDisconnectCancelsPendingRecordingStartAndCompletionWaits() async throws {
        do {
            let (fence, mockConn) = makeConnectedFence()
            try await fence.start()
            mockConn.autoResponse = nil

            let startWait = Task { @ButtonHeistActor in
                try await fence.startRecordingAndWait(
                    config: RecordingConfig(fps: 8, maxDuration: 60),
                    timeout: 5.0
                )
            }
            while mockConn.sent.isEmpty {
                await Task.yield()
            }

            mockConn.onEvent?(.disconnected(.serverClosed))

            do {
                try await startWait.value
                XCTFail("Expected pending start wait to fail on disconnect")
            } catch let error as FenceError {
                guard case .connectionFailure(let failure) = error else {
                    return XCTFail("Expected connectionFailure, got \(error)")
                }
                XCTAssertEqual(failure.errorCode, "transport.server_closed")
            }
        }

        do {
            let (fence, mockConn) = makeConnectedFence()
            try await fence.start()
            fence.handoff.onRecordingEvent?(.started)

            let completionWait = Task { @ButtonHeistActor in
                try await fence.waitForRecording(timeout: 5.0)
            }
            while !fence.isWaitingForRecordingCompletion {
                await Task.yield()
            }

            mockConn.onEvent?(.disconnected(.serverClosed))

            do {
                _ = try await completionWait.value
                XCTFail("Expected pending completion wait to fail on disconnect")
            } catch let error as FenceError {
                guard case .connectionFailure(let failure) = error else {
                    return XCTFail("Expected connectionFailure, got \(error)")
                }
                XCTAssertEqual(failure.errorCode, "transport.server_closed")
            }
        }
    }

    @ButtonHeistActor
    func testRecordingLifecycleResetCancelsPendingStartWait() async throws {
        let recording = FenceRecordingLifecycle()

        do {
            try await recording.waitForStartAcknowledgement(timeout: 5.0) {
                recording.reset()
            }
            XCTFail("Expected reset to cancel the pending start wait")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    @ButtonHeistActor
    func testStopRecordingRetrievesCachedPayloadWhenLocalRecordingPhaseIsIdle() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let tempDirectory = TempDirectoryFixture.make(prefix: "cached-recording")
        defer { TempDirectoryFixture.remove(tempDirectory) }
        let outputURL = tempDirectory.appendingPathComponent("cached.mp4")
        let expectedPayload = RecordingPayload(
            videoData: "dGVzdA==", width: 390, height: 844,
            duration: 2.0, frameCount: 16, fps: 8,
            startTime: Date(), endTime: Date(), stopReason: .inactivity
        )
        mockConn.autoResponse = { message in
            if case .stopRecording = message {
                return .recording(expectedPayload)
            }
            return .actionResult(ActionResult(success: true, method: .activate))
        }

        try await fence.start()
        XCTAssertFalse(fence.isRecording)

        let response = try await fence.execute(
            command: .stopRecording,
            values: ["output": .string(outputURL.path)]
        )

        XCTAssertTrue(mockConn.sent.contains { sent in
            if case .stopRecording = sent.0 { return true }
            return false
        }, "Expected stop_recording to be sent even when local recording phase is idle")
        let stopRequestId = mockConn.sent.first { sent in
            if case .stopRecording = sent.0 { return true }
            return false
        }?.1
        XCTAssertNil(stopRequestId)
        guard case .recording(let path, let payload) = response else {
            return XCTFail("Expected .recording response, got \(response)")
        }
        XCTAssertEqual(path, outputURL.standardized.path)
        XCTAssertEqual(payload.videoData, expectedPayload.videoData)
        XCTAssertEqual(payload.stopReason, .inactivity)
        XCTAssertEqual(try Data(contentsOf: outputURL), Data("test".utf8))
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
            let response = try await fence.execute(command: .startRecording)
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
        let startRequestId = mockConn.sent.first { sent in
            if case .startRecording = sent.0 { return true }
            return false
        }?.1
        XCTAssertNil(startRequestId)
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
        let stopRequestId = mockConn.sent.first { sent in
            if case .stopRecording = sent.0 { return true }
            return false
        }?.1
        XCTAssertNil(stopRequestId)
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
        let probeConnection = MockConnection()
        probeConnection.emitTransportReadyOnConnect = true
        let mockConnection = MockConnection()
        mockConnection.connectEventsOverride = []
        let previousFactory = makeReachabilityConnection
        makeReachabilityConnection = { _ in probeConnection }
        defer { makeReachabilityConnection = previousFactory }

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
    func testDirectConnectUnreachableFailsBeforeSessionHandshake() async {
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let probeConnection = MockConnection()
        probeConnection.connectEventsOverride = [.disconnected(.serverClosed)]
        let sessionConnection = MockConnection()
        let previousFactory = makeReachabilityConnection
        makeReachabilityConnection = { _ in probeConnection }
        defer { makeReachabilityConnection = previousFactory }

        let fence = TheFence(configuration: .init(
            connectionTimeout: 30,
            autoReconnect: false,
            directDevice: device
        ))
        fence.handoff.makeConnection = { _, _, _ in sessionConnection }

        do {
            try await fence.start()
            XCTFail("Expected endpoint unreachable failure")
        } catch FenceError.connectionFailure(let failure) {
            XCTAssertEqual(failure.errorCode, "connection.endpoint_unreachable")
            XCTAssertEqual(failure.phase, .transport)
            XCTAssertTrue(failure.retryable)
        } catch {
            XCTFail("Expected endpoint unreachable failure, got \(error)")
        }

        XCTAssertEqual(sessionConnection.connectCount, 0)
        XCTAssertFalse(probeConnection.isConnected)
        assertDisconnected(fence.handoff.connectionPhase)
    }

    @ButtonHeistActor
    func testDirectConnectReachabilityPreservesTLSFailure() async {
        let device = DiscoveredDevice(host: "192.0.2.1", port: 1234)
        let probeConnection = MockConnection()
        probeConnection.connectEventsOverride = [.disconnected(.missingFingerprint)]
        let sessionConnection = MockConnection()
        let previousFactory = makeReachabilityConnection
        makeReachabilityConnection = { _ in probeConnection }
        defer { makeReachabilityConnection = previousFactory }

        let fence = TheFence(configuration: .init(
            connectionTimeout: 30,
            autoReconnect: false,
            directDevice: device
        ))
        fence.handoff.makeConnection = { _, _, _ in sessionConnection }

        do {
            try await fence.start()
            XCTFail("Expected TLS failure")
        } catch FenceError.connectionFailure(let failure) {
            XCTAssertEqual(failure.errorCode, "tls.missing_fingerprint")
            XCTAssertEqual(failure.phase, .tls)
            XCTAssertFalse(failure.retryable)
        } catch {
            XCTFail("Expected TLS failure, got \(error)")
        }

        XCTAssertEqual(sessionConnection.connectCount, 0)
        XCTAssertFalse(probeConnection.isConnected)
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
            if device.id == reachableDevice.id {
                connection.emitTransportReadyOnConnect = true
            }
            return connection
        }
        defer { makeReachabilityConnection = previousFactory }

        let response = try await fence.execute(command: .listDevices)

        if case .devices(let devices) = response {
            XCTAssertEqual(devices, [reachableDevice])
        } else {
            XCTFail("Expected devices response, got \(response)")
        }

        XCTAssertEqual(mockDiscovery.startCount, 1)
        XCTAssertEqual(mockDiscovery.stopCount, 1)
        XCTAssertEqual(mockConnection.connectCount, 0)
    }

    // MARK: - Background Accessibility Trace

    @ButtonHeistActor
    func testDrainBackgroundAccessibilityTraceReturnsNilWhenEmpty() async {
        let fence = TheFence(configuration: .init())
        XCTAssertNil(fence.drainBackgroundAccessibilityTrace())
    }

    @ButtonHeistActor
    func testDrainBackgroundAccessibilityTraceClearsAfterRead() async {
        let fence = TheFence(configuration: .init())
        let trace = makeBackgroundScreenChangedTrace(elementCount: 7)
        fence.handoff.onBackgroundAccessibilityTrace?(trace)

        let first = fence.drainBackgroundAccessibilityTrace()
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.backgroundDeltaProjection?.isScreenChanged, true)
        XCTAssertEqual(first?.backgroundDeltaProjection?.elementCount, 7)

        let second = fence.drainBackgroundAccessibilityTrace()
        XCTAssertNil(second)
    }

    @ButtonHeistActor
    func testDrainBackgroundAccessibilityTracePreservesArrivalOrder() async {
        let fence = TheFence(configuration: .init())
        fence.handoff.onBackgroundAccessibilityTrace?(makeBackgroundElementsChangedTrace(elementCount: 2))
        fence.handoff.onBackgroundAccessibilityTrace?(makeBackgroundScreenChangedTrace(elementCount: 7))

        let first = fence.drainBackgroundAccessibilityTrace()?.backgroundDeltaProjection
        XCTAssertEqual(first?.kindRawValue, "elementsChanged")
        XCTAssertEqual(first?.elementCount, 2)

        let second = fence.drainBackgroundAccessibilityTrace()?.backgroundDeltaProjection
        XCTAssertEqual(second?.isScreenChanged, true)
        XCTAssertEqual(second?.elementCount, 7)

        XCTAssertNil(fence.drainBackgroundAccessibilityTrace())
    }

    @ButtonHeistActor
    func testDrainBackgroundAccessibilityTracesReturnsAllQueuedTraces() async {
        let fence = TheFence(configuration: .init())
        fence.handoff.onBackgroundAccessibilityTrace?(makeBackgroundElementsChangedTrace(elementCount: 2))
        fence.handoff.onBackgroundAccessibilityTrace?(makeBackgroundScreenChangedTrace(elementCount: 7))

        let traces = fence.drainBackgroundAccessibilityTraces()
        let deltas = traces.compactMap(\.backgroundDeltaProjection)

        XCTAssertEqual(deltas.map(\.kindRawValue), ["elementsChanged", "screenChanged"])
        XCTAssertEqual(deltas.map(\.elementCount), [2, 7])
        XCTAssertNil(fence.drainBackgroundAccessibilityTrace())
    }

    @ButtonHeistActor
    func testBackgroundChangeIsStoredAsTraceAndDeltaIsDerivedAtTheEdge() async {
        let fence = TheFence(configuration: .init())
        let before = makeReceiptTestInterface([
            makeReceiptTestElement(heistId: "status", label: "Status", value: "Old"),
        ])
        let after = makeReceiptTestInterface([
            makeReceiptTestElement(heistId: "status", label: "Status", value: "New"),
        ])
        let trace = makeReceiptTestTrace(before: before, after: after)

        fence.handoff.handleServerMessage(
            .pong(),
            requestId: nil,
            accessibilityTrace: trace
        )

        let drained = fence.drainBackgroundAccessibilityTrace()
        XCTAssertEqual(drained, trace)
        let derived = drained?.backgroundDeltaProjection
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
        fence.handoff.onBackgroundAccessibilityTrace?(makeBackgroundScreenChangedTrace(elementCount: 7))

        let response = try await fence.execute(
            command: .activate,
            values: [
                "target": targetArgumentValue(heistId: "stale_button"),
                "expect": expectationValue(type: "element_updated", fields: [
                    "heistId": .string("counter"),
                    "property": .string("value"),
                    "newValue": .string("5"),
                ]),
            ]
        )
        if case .action(_, let expectation) = response {
            XCTAssertEqual(expectation?.met, false)
        } else {
            XCTFail("Expected action response, got \(response)")
        }

        let queued = fence.drainBackgroundAccessibilityTrace()?.backgroundDeltaProjection
        XCTAssertEqual(queued?.isScreenChanged, true)
        XCTAssertEqual(queued?.elementCount, 7)
        XCTAssertNil(fence.drainBackgroundAccessibilityTrace())
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
            screenWidth: 390, screenHeight: 844,
            instanceId: "mock-session",
            instanceIdentifier: "mock-server",
            listeningPort: 49152,
            tlsActive: true
        )

        let fence = TheFence(configuration: .init())
        fence.handoff.makeDiscovery = { mockDiscovery }
        fence.handoff.makeConnection = { _, _, _ in mockConnection }

        fence.handoff.onBackgroundAccessibilityTrace?(makeBackgroundElementsChangedTrace(elementCount: 2))
        fence.handoff.onBackgroundAccessibilityTrace?(makeBackgroundScreenChangedTrace(elementCount: 7))

        let response = try await fence.execute(
            command: .waitForChange,
            values: ["expect": expectationValue(type: "screen_changed")]
        )

        if case .action(let result, let expectation) = response {
            XCTAssertTrue(result.success)
            XCTAssertEqual(result.accessibilityDelta?.isScreenChanged, true)
            XCTAssertEqual(expectation?.met, true)
            XCTAssertEqual(mockDiscovery.startCount, 0, "Short-circuit should avoid discovery")
            XCTAssertEqual(mockConnection.connectCount, 0, "Short-circuit should avoid connection")
        } else {
            XCTFail("Expected action response, got \(response)")
        }

        let remaining = fence.drainBackgroundAccessibilityTrace()?.backgroundDeltaProjection
        XCTAssertEqual(remaining?.kindRawValue, "elementsChanged")
        XCTAssertEqual(remaining?.elementCount, 2)
        XCTAssertNil(fence.drainBackgroundAccessibilityTrace())
    }

    @ButtonHeistActor
    func testBackgroundTraceQueueDropsOldestWhenCapacityExceeded() async {
        let fence = TheFence(configuration: .init())
        for count in 1...25 {
            fence.handoff.onBackgroundAccessibilityTrace?(makeBackgroundElementsChangedTrace(elementCount: count))
        }

        let first = fence.drainBackgroundAccessibilityTrace()?.backgroundDeltaProjection
        XCTAssertEqual(first?.elementCount, 6)

        for expectedCount in 7...25 {
            XCTAssertEqual(fence.drainBackgroundAccessibilityTrace()?.backgroundDeltaProjection?.elementCount, expectedCount)
        }
        XCTAssertNil(fence.drainBackgroundAccessibilityTrace())
    }

    @ButtonHeistActor
    func testBackgroundTraceQueueClearsOnDisconnect() async {
        let (fence, mockConnection) = makeConnectedFence()
        fence.handoff.connect(to: TheFenceFixtures.testDevice)
        fence.handoff.onBackgroundAccessibilityTrace?(makeBackgroundScreenChangedTrace(elementCount: 7))

        mockConnection.onEvent?(.disconnected(.serverClosed))

        XCTAssertNil(fence.drainBackgroundAccessibilityTrace())
    }

    @ButtonHeistActor
    func testWaitForChangeExpectationShortCircuitsOnBackgroundTrace() async throws {
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
            screenWidth: 390, screenHeight: 844,
            instanceId: "mock-session",
            instanceIdentifier: "mock-server",
            listeningPort: 49152,
            tlsActive: true
        )

        let fence = TheFence(configuration: .init())
        fence.handoff.makeDiscovery = { mockDiscovery }
        fence.handoff.makeConnection = { _, _, _ in mockConnection }

        let element = HeistElement(
            description: "Button", label: "New Order", value: nil, identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44, actions: [.activate]
        )
        let fullInterface = makeReceiptTestInterface([element])
        let trace = makeReceiptTestTrace(
            before: makeReceiptTestInterface(elementCount: 0),
            after: fullInterface,
            beforeScreenId: "before",
            afterScreenId: "after"
        )
        fence.handoff.onBackgroundAccessibilityTrace?(trace)

        // wait_for_change may satisfy a late call from a queued background trace.
        let response = try await fence.execute(
            command: .waitForChange,
            values: ["expect": expectationValue(type: "screen_changed")]
        )

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
    func testWaitForChangeBackgroundShortCircuitUsesTraceTransitionDelta() async throws {
        let fence = TheFence(configuration: .init())
        let interface = makeReceiptTestInterface([
            makeReceiptTestElement(heistId: "settings", label: "Settings"),
        ])
        let beforeCapture = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            context: AccessibilityTrace.Context(screenId: "same")
        )
        let afterCapture = AccessibilityTrace.Capture(
            sequence: 2,
            interface: interface,
            parentHash: beforeCapture.hash,
            context: AccessibilityTrace.Context(screenId: "same"),
            transition: AccessibilityTrace.Transition(screenChangeReason: "primaryHeaderChanged")
        )
        let trace = AccessibilityTrace(captures: [beforeCapture, afterCapture])
        XCTAssertEqual(trace.endpointDeltaProjection?.kindRawValue, "screenChanged")
        XCTAssertTrue(
            ElementEdits.between(beforeCapture.interface, afterCapture.interface).isEmpty,
            "This fixture only proves the contract if raw interface edits would disagree."
        )
        fence.handoff.onBackgroundAccessibilityTrace?(trace)

        let response = try await fence.execute(
            command: .waitForChange,
            values: ["expect": expectationValue(type: "screen_changed")]
        )

        guard case .action(let result, let expectation) = response else {
            return XCTFail("Expected action response, got \(response)")
        }
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.accessibilityTrace, trace)
        XCTAssertEqual(result.accessibilityDelta, trace.endpointDeltaProjection)
        XCTAssertEqual(expectation?.met, true)
        guard case .screenChanged(let payload)? = result.accessibilityDelta else {
            return XCTFail("Expected trace transition to project screenChanged, got \(String(describing: result.accessibilityDelta))")
        }
        XCTAssertEqual(payload.captureEdge?.before.hash, trace.captures.first?.hash)
        XCTAssertEqual(payload.captureEdge?.after.hash, trace.captures.last?.hash)
        XCTAssertEqual(payload.newInterface, interface)
        XCTAssertNil(fence.drainBackgroundAccessibilityTrace())
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
                    traceProjecting: .noChange(.init(elementCount: 1))
                ))
            case .waitForChange:
                return .actionResult(ActionResult(
                    success: true,
                    method: .waitForChange,
                    message: "expectation met after observed change",
                    traceProjecting: .noChange(.init(elementCount: 1))
                ))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }
        fence.handoff.onBackgroundAccessibilityTrace?(makeBackgroundScreenChangedTrace(elementCount: 7))

        let response = try await fence.execute(
            command: .activate,
            values: [
                "target": targetArgumentValue(heistId: "stale_button"),
                "expect": expectationValue(type: "screen_changed"),
            ]
        )

        XCTAssertTrue(mockConn.sent.contains { sent, _ in
            if case .activate = sent { return true }
            return false
        }, "Action must dispatch even when a queued background trace already matches")
        if case .action(_, let expectation) = response {
            XCTAssertEqual(expectation?.met, false)
        } else {
            XCTFail("Expected action response, got \(response)")
        }

        let queued = fence.drainBackgroundAccessibilityTrace()?.backgroundDeltaProjection
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
                    traceProjecting: .noChange(.init(elementCount: 1))
                ))
            case .waitForChange:
                return .actionResult(ActionResult(
                    success: true,
                    method: .waitForChange,
                    message: "expectation met after 0.1s",
                    traceProjecting: .elementsChanged(.init(
                        elementCount: 2,
                        edits: ElementEdits(added: [appeared])
                    ))
                ))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }

        let response = try await fence.execute(
            command: .activate,
            values: [
                "target": targetArgumentValue(heistId: "button"),
                "expect": expectationValue(type: "element_appeared", fields: [
                    "matcher": .object(["label": .string("Ready")]),
                ]),
            ]
        )

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
                    traceProjecting: .noChange(.init(elementCount: 1))
                ))
            case .waitForChange:
                return .actionResult(ActionResult(
                    success: false,
                    method: .waitForChange,
                    message: "expectation not met after 0.1s",
                    errorKind: .timeout,
                    traceProjecting: .elementsChanged(.init(elementCount: 3, edits: ElementEdits()))
                ))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }

        let response = try await fence.execute(
            command: .activate,
            values: [
                "target": targetArgumentValue(heistId: "button"),
                "expect": expectationValue(type: "screen_changed"),
            ]
        )

        if case .action(let result, let expectation) = response {
            XCTAssertFalse(result.success)
            XCTAssertEqual(result.method, .waitForChange)
            XCTAssertEqual(result.errorKind, .timeout)
            XCTAssertEqual(result.accessibilityDelta?.kindRawValue, "elementsChanged")
            XCTAssertEqual(expectation?.met, false)
            XCTAssertEqual(expectation?.actual, "elementsChanged")
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
                    traceProjecting: .noChange(.init(elementCount: 1))
                ))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }

        let response = try await fence.execute(
            command: .activate,
            values: [
                "target": targetArgumentValue(heistId: "button"),
                "timeout": .double(0.01),
                "expect": expectationValue(type: "screen_changed"),
            ]
        )

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
                    traceProjecting: .screenChanged(.init(
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

        let response = try await fence.execute(
            command: .activate,
            values: [
                "target": targetArgumentValue(heistId: "button"),
                "expect": expectationValue(type: "screen_changed"),
            ]
        )

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

        // Background trace present but no expectation on the action
        fence.handoff.onBackgroundAccessibilityTrace?(makeBackgroundScreenChangedTrace(elementCount: 3))

        // Action without expect — should NOT short-circuit against the
        // background trace. Depending on current connection setup this may
        // surface as a thrown connection error or an error response, but it
        // must not return the synthetic "expectation already met" action.
        do {
            let response = try await fence.execute(
                command: .activate,
                values: ["target": targetArgumentValue(heistId: "some_button")]
            )
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
                    traceProjecting: .noChange(.init(elementCount: 1))
                ))
            case .requestInterface:
                return .interface(Interface(timestamp: Date(timeIntervalSince1970: 0), tree: []))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }
        try await startHeistRecording(on: fence)

        let response = try await fence.execute(
            command: .activate,
            values: [
                "target": targetArgumentValue(label: "No Change"),
                "timeout": .double(0.01),
                "expect": expectationValue(type: "screen_changed"),
            ]
        )

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
                let interface = makeReceiptTestInterface(elementCount: 0)
                return .actionResult(ActionResult(
                    success: true,
                    method: .activate,
                    accessibilityTrace: makeReceiptTestTrace(
                        before: interface,
                        after: interface,
                        beforeScreenId: "before",
                        afterScreenId: "after"
                    )
                ))
            case .waitForChange:
                XCTFail("Immediate screen_changed expectation should not wait")
                return .actionResult(ActionResult(success: false, method: .waitForChange))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }
        try await startHeistRecording(on: fence)

        let response = try await fence.execute(
            command: .activate,
            values: [
                "target": targetArgumentValue(label: "Continue"),
                "expect": expectationValue(type: "screen_changed"),
            ]
        )

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
        let stopResponse = try await fence.execute(
            command: .stopHeist,
            values: ["output": .string(output.path)]
        )
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
                let loadingInterface = makeReceiptTestInterface([
                    HeistElement(
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
                    ),
                ])
                return .actionResult(ActionResult(
                    success: true,
                    method: .activate,
                    accessibilityTrace: makeReceiptTestTrace(before: loadingInterface, after: loadingInterface)
                ))
            case .waitForChange:
                let doneInterface = makeReceiptTestInterface(
                    [HeistElement(
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
                    )],
                    timestamp: Date(timeIntervalSince1970: 1)
                )
                return .actionResult(ActionResult(
                    success: true,
                    method: .waitForChange,
                    accessibilityTrace: makeReceiptTestTrace(
                        before: doneInterface,
                        after: doneInterface,
                        beforeScreenId: "loading",
                        afterScreenId: "done"
                    )
                ))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }
        try await startHeistRecording(on: fence)

        let response = try await fence.execute(
            command: .activate,
            values: [
                "target": targetArgumentValue(label: "Continue"),
                "expect": expectationValue(type: "screen_changed"),
            ]
        )

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
        _ = try await fence.execute(
            command: .stopHeist,
            values: ["output": .string(output.path)]
        )

        let heist = try TheBookKeeper.readHeist(from: output)
        XCTAssertEqual(heist.steps.count, 1)
        XCTAssertEqual(heist.steps[0].command, "activate")
        XCTAssertEqual(heist.steps[0].recorded?.accessibilityTrace?.captures.first?.interface.elements.first?.label, "Done")
        XCTAssertEqual(heist.steps[0].recorded?.accessibilityDelta?.kindRawValue, "screenChanged")
        XCTAssertEqual(heist.steps[0].recorded?.expectation?.met, true)
        try? await fence.bookKeeper.closeSession()
    }

    @ButtonHeistActor
    func testHeistRecordingUsesActionBeforeCaptureForTargetAfterScreenChange() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let target = makeReceiptTestElement(
            heistId: "pay_button",
            label: "Pay",
            identifier: "checkout.pay",
            traits: [.button]
        )
        let after = makeReceiptTestElement(
            heistId: "done",
            label: "Done",
            identifier: "checkout.done",
            traits: [.staticText]
        )
        let trace = makeReceiptTestTrace(
            before: makeReceiptTestInterface([target]),
            after: makeReceiptTestInterface([after]),
            beforeScreenId: "checkout",
            afterScreenId: "receipt"
        )
        mockConn.autoResponse = { message in
            switch message {
            case .activate:
                return .actionResult(ActionResult(
                    success: true,
                    method: .activate,
                    accessibilityTrace: trace
                ))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }
        try await startHeistRecording(on: fence)

        let response = try await fence.execute(
            command: .activate,
            values: [
                "target": targetArgumentValue(heistId: "pay_button"),
                "expect": expectationValue(type: "element_disappeared", fields: [
                    "matcher": .object(["label": .string("Pay")]),
                ]),
            ]
        )
        guard case .action(let result, let expectation) = response else {
            return XCTFail("Expected action response, got \(response)")
        }
        XCTAssertTrue(result.success)
        XCTAssertEqual(expectation?.met, true)

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("heist")
        defer { try? FileManager.default.removeItem(at: output) }
        _ = try await fence.execute(
            command: .stopHeist,
            values: ["output": .string(output.path)]
        )

        let heist = try TheBookKeeper.readHeist(from: output)
        XCTAssertEqual(heist.steps.count, 1)
        XCTAssertEqual(heist.steps[0].recorded?.heistId, "pay_button")
        XCTAssertEqual(heist.steps[0].target?.matcher.identifier, "checkout.pay")
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
                return .actionResult(ActionResult(success: true, method: .activate))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }
        try await startHeistRecording(on: fence)

        let response = try await fence.execute(
            command: .activate,
            values: ["target": targetArgumentValue(label: "Plain Success")]
        )

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
    func testActionTraceProvidesTargetCaptureForHeistMatcher() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let target = makeReceiptTestElement(
            heistId: "pay_button",
            label: "Pay",
            identifier: "checkout.pay",
            traits: [.button]
        )
        let interface = makeReceiptTestInterface([target])
        mockConn.autoResponse = { message in
            switch message {
            case .activate:
                return .actionResult(ActionResult(
                    success: true,
                    method: .activate,
                    accessibilityTrace: makeReceiptTestTrace(before: interface, after: interface)
                ))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }
        try await startHeistRecording(on: fence)

        let response = try await fence.execute(
            command: .activate,
            values: ["target": targetArgumentValue(heistId: "pay_button")]
        )
        guard case .action(let result, _) = response else {
            return XCTFail("Expected action response, got \(response)")
        }
        XCTAssertTrue(result.success)

        let evidence = try XCTUnwrap(heistEvidence(in: fence))
        XCTAssertEqual(evidence.count, 1)
        XCTAssertEqual(evidence[0].recorded?.heistId, "pay_button")
        XCTAssertEqual(evidence[0].target?.matcher.identifier, "checkout.pay")
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

        let response = try await fence.execute(
            command: .activate,
            values: ["target": targetArgumentValue(label: "Missing")]
        )

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
    /// the action response tracker, which silently no-ops on an unknown requestId.
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
            .message(.actionResult(lateResult), requestId: timedOutRequestId, accessibilityTrace: nil)
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
    /// Before the fix, `forceDisconnect` -> connection-state change ->
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
            .message(.actionResult(siblingResult), requestId: siblingRequestId, accessibilityTrace: nil)
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
        let response = try await fence.execute(
            command: .startHeist,
            values: [
                "identifier": .string("record-verified-actions-\(UUID().uuidString)"),
                "app": .string("com.example.app"),
            ]
        )
        guard case .heistStarted = response else {
            return XCTFail("Expected heistStarted response, got \(response)")
        }
    }

    private func expectationValue(type: String, fields: [String: HeistValue] = [:]) -> HeistValue {
        var values = fields
        values["type"] = .string(type)
        return .object(values)
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

    @ButtonHeistActor
    private func heistEvidence(in fence: TheFence) throws -> [HeistEvidence]? {
        guard case .active(let session) = fence.bookKeeper.phase,
              case .recording(let recording) = session.heistRecording else {
            return nil
        }
        recording.fileHandle.synchronizeFile()
        let data = try Data(contentsOf: recording.filePath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try data
            .split(separator: 0x0A)
            .map { try decoder.decode(HeistEvidence.self, from: Data($0)) }
    }

    private func decodeActionExpectationJSON(_ result: ExpectationResult) throws -> ActionExpectationPublicJSON {
        let response = FenceResponse.action(
            result: ActionResult(success: true, method: .activate),
            expectation: result
        )
        return try JSONDecoder().decode(ActionExpectationPublicJSON.self, from: response.jsonData())
    }

    private struct ActionExpectationPublicJSON: Decodable {
        let status: String
        let expectation: ActionExpectationJSON?
    }

    private struct ActionExpectationJSON: Decodable {
        let met: Bool
        let actual: String?
        let expected: ActionExpectation?
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
