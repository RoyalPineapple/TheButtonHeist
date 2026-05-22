import XCTest
import TheScore

final class ServerMessageTests: XCTestCase {

    func testInfoEncodeDecode() throws {
        let info = ServerInfo(
            appName: "TestApp",
            bundleIdentifier: "com.test.app",
            deviceName: "iPhone",
            systemVersion: "17.0",
            screenWidth: 390,
            screenHeight: 844
        )
        let message = ServerMessage.info(info)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .info(let decodedInfo) = decoded {
            XCTAssertEqual(decodedInfo.appName, "TestApp")
            XCTAssertEqual(decodedInfo.bundleIdentifier, "com.test.app")
        } else {
            XCTFail("Expected info, got \(decoded)")
        }
    }

    func testStatusEncodeDecode() throws {
        let payload = StatusPayload(
            identity: StatusIdentity(
                appName: "ReachableApp",
                bundleIdentifier: "com.test.reachable",
                appBuild: "42",
                deviceName: "iPhone",
                systemVersion: "18.0",
                buttonHeistVersion: "5.0"
            ),
            session: StatusSession(
                active: true,
                watchersAllowed: false,
                activeConnections: 1
            )
        )
        let message = ServerMessage.status(payload)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .status(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload.identity.appName, "ReachableApp")
            XCTAssertEqual(decodedPayload.identity.bundleIdentifier, "com.test.reachable")
            XCTAssertEqual(decodedPayload.session.active, true)
            XCTAssertEqual(decodedPayload.session.activeConnections, 1)
        } else {
            XCTFail("Expected status, got \(decoded)")
        }
    }

    func testAuthApprovalPendingEncodeDecode() throws {
        let payload = AuthApprovalPendingPayload(
            message: "Waiting for approval on the device.",
            hint: "Tap Allow on the iOS device to continue."
        )
        let message = ServerMessage.authApprovalPending(payload)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .authApprovalPending(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload, payload)
        } else {
            XCTFail("Expected authApprovalPending, got \(decoded)")
        }
    }

    func testInterfaceEncodeDecode() throws {
        let element = HeistElement(
            description: "Button",
            label: "Submit",
            value: nil,
            identifier: "submit_btn",
            frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
        let payload = makeTestInterface(elements: [element], timestamp: Date())
        let message = ServerMessage.interface(payload)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ServerMessage.self, from: data)

        if case .interface(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload.elements.count, 1)
            XCTAssertEqual(decodedPayload.elements[0].label, "Submit")
        } else {
            XCTFail("Expected interface, got \(decoded)")
        }
    }

    func testPongEncodeDecode() throws {
        let payload = PongPayload(
            buttonHeistVersion: "2026.05.22",
            appName: "TestApp",
            bundleIdentifier: "com.test.app",
            appVersion: "1.2.3",
            appBuild: "456",
            serverInstanceIdentifier: "server-1",
            serverTimestampMs: 1_700_000_000_000
        )
        let message = ServerMessage.pong(payload)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .pong(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload, payload)
        } else {
            XCTFail("Expected pong, got \(decoded)")
        }
    }

    func testPongRejectsMissingPayload() throws {
        let data = Data(#"{"type":"pong"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ServerMessage.self, from: data))
    }

    func testResponseEnvelopeRejectsMissingPongPayload() throws {
        let data = Data("""
        {"buttonHeistVersion":"\(TheScore.buttonHeistVersion)","requestId":"ping-1","type":"pong"}
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ResponseEnvelope.self, from: data))
    }

    func testErrorEncodeDecode() throws {
        let message = ServerMessage.error(ServerError(kind: .general, message: "Connection failed"))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .error(let serverError) = decoded {
            XCTAssertEqual(serverError.kind, .general)
            XCTAssertEqual(serverError.message, "Connection failed")
        } else {
            XCTFail("Expected error, got \(decoded)")
        }
    }

    func testErrorWireShape() throws {
        let message = ServerMessage.error(ServerError(kind: .recording, message: "disk full"))
        let data = try JSONEncoder().encode(message)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "error")
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertEqual(payload["kind"] as? String, "recording")
        XCTAssertEqual(payload["message"] as? String, "disk full")
    }

    func testErrorDecodesFromExplicitJSON() throws {
        let json = """
        {"type":"error","payload":{"kind":"general","message":"oops"}}
        """
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: Data(json.utf8))
        guard case .error(let serverError) = decoded else {
            XCTFail("Expected error message, got \(decoded)")
            return
        }
        XCTAssertEqual(serverError.kind, .general)
        XCTAssertEqual(serverError.message, "oops")
    }

    // MARK: - ActionResult Tests

    func testActionResultWithValue() throws {
        let result = ActionResult(success: true, method: .typeText, payload: .value("Hello World"))
        let message = ServerMessage.actionResult(result)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .actionResult(let decodedResult) = decoded {
            XCTAssertTrue(decodedResult.success)
            XCTAssertEqual(decodedResult.method, .typeText)
            guard case .value(let string) = decodedResult.payload else {
                XCTFail("Expected .value payload")
                return
            }
            XCTAssertEqual(string, "Hello World")
            XCTAssertNil(decodedResult.message)
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }

    func testActionResultWithoutValue() throws {
        let result = ActionResult(success: true, method: .syntheticTap)
        let message = ServerMessage.actionResult(result)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .actionResult(let decodedResult) = decoded {
            XCTAssertTrue(decodedResult.success)
            XCTAssertEqual(decodedResult.method, .syntheticTap)
            XCTAssertNil(decodedResult.payload)
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }

    func testActionResultPayloadValueWireShape() throws {
        let result = ActionResult(success: true, method: .typeText, payload: .value("Hi"))
        let data = try JSONEncoder().encode(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertEqual(payload["kind"] as? String, "value")
        XCTAssertEqual(payload["data"] as? String, "Hi")
    }

    func testActionResultPayloadScrollSearchWireShape() throws {
        let search = ScrollSearchResult(
            scrollCount: 2, uniqueElementsSeen: 10, totalItems: nil, exhaustive: false
        )
        let result = ActionResult(success: true, method: .elementSearch, payload: .scrollSearch(search))
        let data = try JSONEncoder().encode(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertEqual(payload["kind"] as? String, "scrollSearch")
        let inner = try XCTUnwrap(payload["data"] as? [String: Any])
        XCTAssertEqual(inner["scrollCount"] as? Int, 2)
    }

    func testActionResultPayloadRotorWireShape() throws {
        let rotor = RotorResult(
            rotor: "Errors",
            direction: .next,
            foundElement: HeistElement(
                description: "Email",
                label: "Email",
                value: nil,
                identifier: nil,
                frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
                actions: []
            ),
            textRange: RotorTextRange(text: "@maria", startOffset: 10, endOffset: 16, rangeDescription: "[10..<16]")
        )
        let result = ActionResult(success: true, method: .rotor, payload: .rotor(rotor))
        let data = try JSONEncoder().encode(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertEqual(payload["kind"] as? String, "rotor")
        let inner = try XCTUnwrap(payload["data"] as? [String: Any])
        XCTAssertEqual(inner["rotor"] as? String, "Errors")
        XCTAssertEqual(inner["direction"] as? String, "next")
        XCTAssertNotNil(inner["foundElement"])
        let textRange = try XCTUnwrap(inner["textRange"] as? [String: Any])
        XCTAssertEqual(textRange["text"] as? String, "@maria")
        XCTAssertEqual(textRange["startOffset"] as? Int, 10)
        XCTAssertEqual(textRange["endOffset"] as? Int, 16)
        XCTAssertEqual(textRange["rangeDescription"] as? String, "[10..<16]")
    }

    func testActionResultAccessibilityTraceWireShape() throws {
        let interface = makeTestInterface(
            elements: [
                HeistElement(
                    heistId: "submit",
                    description: "Submit",
                    label: "Submit",
                    value: nil,
                    identifier: "submit_button",
                    traits: [.button],
                    frameX: 10,
                    frameY: 20,
                    frameWidth: 100,
                    frameHeight: 44,
                    actions: [.activate]
                ),
            ]
        )
        let trace = AccessibilityTrace(first: interface).appending(interface)
        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: trace
        )

        let data = try JSONEncoder().encode(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let delta = try XCTUnwrap(json["accessibilityDelta"] as? [String: Any])

        XCTAssertEqual(delta["kind"] as? String, "noChange")
        XCTAssertNotNil(json["accessibilityTrace"])
        XCTAssertNil(json["interfaceDelta"])
    }

    func testActionResultAccessibilityDeltaProjectsFromTrace() throws {
        let before = makeTestInterface(
            elements: [
                HeistElement(
                    heistId: "before-title",
                    description: "Before",
                    label: "Before",
                    value: nil,
                    identifier: "before_title",
                    traits: [.header],
                    frameX: 0,
                    frameY: 0,
                    frameWidth: 100,
                    frameHeight: 44,
                    actions: []
                ),
            ],
            timestamp: Date(timeIntervalSince1970: 0)
        )
        let after = makeTestInterface(
            elements: [
                HeistElement(
                    heistId: "after-title",
                    description: "After",
                    label: "After",
                    value: nil,
                    identifier: "after_title",
                    traits: [.header],
                    frameX: 0,
                    frameY: 0,
                    frameWidth: 100,
                    frameHeight: 44,
                    actions: []
                ),
            ],
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let trace = AccessibilityTrace(first: before).appending(after)
        let conflictingDelta = AccessibilityTrace.Delta.noChange(.init(elementCount: 999))

        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityDelta: conflictingDelta,
            accessibilityTrace: trace
        )

        XCTAssertEqual(result.accessibilityDelta, trace.captureEndpointDelta)
        XCTAssertNotEqual(result.accessibilityDelta, conflictingDelta)
    }

    func testActionResultDecodedAccessibilityDeltaProjectsFromTrace() throws {
        let before = makeTestInterface(
            elements: [
                HeistElement(
                    heistId: "before-title",
                    description: "Before",
                    label: "Before",
                    value: nil,
                    identifier: "before_title",
                    traits: [.header],
                    frameX: 0,
                    frameY: 0,
                    frameWidth: 100,
                    frameHeight: 44,
                    actions: []
                ),
            ],
            timestamp: Date(timeIntervalSince1970: 0)
        )
        let after = makeTestInterface(
            elements: [
                HeistElement(
                    heistId: "after-title",
                    description: "After",
                    label: "After",
                    value: nil,
                    identifier: "after_title",
                    traits: [.header],
                    frameX: 0,
                    frameY: 0,
                    frameWidth: 100,
                    frameHeight: 44,
                    actions: []
                ),
            ],
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let trace = AccessibilityTrace(first: before).appending(after)
        let conflictingDelta = AccessibilityTrace.Delta.noChange(.init(elementCount: 999))
        let traceJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(trace))
        let deltaJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(conflictingDelta))
        let json: [String: Any] = [
            "success": true,
            "method": "activate",
            "accessibilityDelta": deltaJSON,
            "accessibilityTrace": traceJSON,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let result = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertEqual(result.accessibilityDelta, trace.captureEndpointDelta)
        XCTAssertNotEqual(result.accessibilityDelta, conflictingDelta)
    }

    func testActionResultAccessibilityDeltaRetainsNoTraceProjection() throws {
        let delta = AccessibilityTrace.Delta.noChange(.init(elementCount: 7))
        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityDelta: delta
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertEqual(decoded.accessibilityDelta, delta)
    }

    func testActionResultTraceWithoutEndpointDropsIndependentDelta() throws {
        let interface = makeTestInterface(
            elements: [
                HeistElement(
                    heistId: "title",
                    description: "Title",
                    label: "Title",
                    value: nil,
                    identifier: "title",
                    traits: [.header],
                    frameX: 0,
                    frameY: 0,
                    frameWidth: 100,
                    frameHeight: 44,
                    actions: []
                ),
            ],
            timestamp: Date(timeIntervalSince1970: 0)
        )
        let trace = AccessibilityTrace(interface: interface)
        let independentDelta = AccessibilityTrace.Delta.noChange(.init(elementCount: 999))
        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityDelta: independentDelta,
            accessibilityTrace: trace
        )

        XCTAssertNil(result.accessibilityDelta)

        let traceJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(trace))
        let deltaJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(independentDelta))
        let json: [String: Any] = [
            "success": true,
            "method": "activate",
            "accessibilityDelta": deltaJSON,
            "accessibilityTrace": traceJSON,
        ]
        let decoded = try JSONDecoder().decode(
            ActionResult.self,
            from: try JSONSerialization.data(withJSONObject: json)
        )

        XCTAssertNil(decoded.accessibilityDelta)
    }

    func testActionResultScreenContextProjectsFromTrace() throws {
        let before = interfaceWithHeader("Before", heistId: "before-title")
        let after = interfaceWithHeader("Trace Screen", heistId: "trace-title", timestamp: 1)
        let trace = AccessibilityTrace(first: before).appending(
            after,
            context: AccessibilityTrace.Context(screenId: "trace_screen")
        )

        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: trace,
            screenName: "stored screen",
            screenId: "stored_screen"
        )

        XCTAssertEqual(result.screenName, "Trace Screen")
        XCTAssertEqual(result.screenId, "trace_screen")
    }

    func testActionResultScreenContextRoundTripsTraceProjection() throws {
        let before = interfaceWithHeader("Before", heistId: "before-title")
        let after = interfaceWithHeader("Trace Screen", heistId: "trace-title", timestamp: 1)
        let trace = AccessibilityTrace(first: before).appending(
            after,
            context: AccessibilityTrace.Context(screenId: "trace_screen")
        )
        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: trace,
            screenName: "stored screen",
            screenId: "stored_screen"
        )

        let data = try JSONEncoder().encode(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertEqual(json["screenName"] as? String, "Trace Screen")
        XCTAssertEqual(json["screenId"] as? String, "trace_screen")
        XCTAssertEqual(decoded.screenName, "Trace Screen")
        XCTAssertEqual(decoded.screenId, "trace_screen")
    }

    func testActionResultScreenContextDoesNotFallbackWhenTraceProjectsNil() throws {
        let before = interfaceWithHeader("Before", heistId: "before-title")
        let trace = AccessibilityTrace(first: before).appending(interfaceWithoutHeader(timestamp: 1))
        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: trace,
            screenName: "stored screen",
            screenId: "stored_screen"
        )

        XCTAssertNil(result.screenName)
        XCTAssertNil(result.screenId)
    }

    func testActionResultScreenContextFallsBackWithoutTrace() throws {
        let result = ActionResult(
            success: true,
            method: .activate,
            screenName: "Legacy Screen",
            screenId: "legacy_screen"
        )

        XCTAssertEqual(result.screenName, "Legacy Screen")
        XCTAssertEqual(result.screenId, "legacy_screen")
    }

    func testActionResultDecodedScreenContextProjectsFromTrace() throws {
        let before = interfaceWithHeader("Before", heistId: "before-title")
        let after = interfaceWithHeader("Trace Screen", heistId: "trace-title", timestamp: 1)
        let trace = AccessibilityTrace(first: before).appending(
            after,
            context: AccessibilityTrace.Context(screenId: "trace_screen")
        )
        let traceJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(trace))
        let json: [String: Any] = [
            "success": true,
            "method": "activate",
            "screenName": "stored screen",
            "screenId": "stored_screen",
            "accessibilityTrace": traceJSON,
        ]
        let data = try JSONSerialization.data(withJSONObject: json)

        let result = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertEqual(result.screenName, "Trace Screen")
        XCTAssertEqual(result.screenId, "trace_screen")
    }

    func testActionResultDecodedScreenContextFallsBackWithoutTrace() throws {
        let json = """
        {"success":true,"method":"activate","screenName":"Legacy Screen","screenId":"legacy_screen"}
        """

        let result = try JSONDecoder().decode(ActionResult.self, from: Data(json.utf8))

        XCTAssertEqual(result.screenName, "Legacy Screen")
        XCTAssertEqual(result.screenId, "legacy_screen")
    }

    func testActionResultPayloadDecodesFromExplicitJSON() throws {
        let json = """
        {"type":"actionResult","payload":{"success":true,"method":"typeText","payload":{"kind":"value","data":"Hello"}}}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)
        guard case .actionResult(let result) = decoded,
              case .value(let string) = result.payload else {
            XCTFail("Expected actionResult with .value payload, got \(decoded)")
            return
        }
        XCTAssertEqual(string, "Hello")
    }

    func testActionResultWithoutOptionalFieldsFromExplicitJSON() throws {
        let json = """
        {"type":"actionResult","payload":{"success":true,"method":"syntheticTap"}}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .actionResult(let result) = decoded {
            XCTAssertTrue(result.success)
            XCTAssertEqual(result.method, .syntheticTap)
            XCTAssertNil(result.payload)
            XCTAssertNil(result.message)
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }

    func testActionResultWithErrorKind() throws {
        let result = ActionResult(
            success: false,
            method: .syntheticTap,
            message: "Element not found",
            errorKind: .elementNotFound
        )
        let message = ServerMessage.actionResult(result)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .actionResult(let decodedResult) = decoded {
            XCTAssertFalse(decodedResult.success)
            XCTAssertEqual(decodedResult.errorKind, .elementNotFound)
            XCTAssertEqual(decodedResult.message, "Element not found")
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }

    func testErrorKindAllCasesRoundTrip() throws {
        for kind in ErrorKind.allCases {
            let result = ActionResult(success: false, method: .syntheticTap, errorKind: kind)
            let data = try JSONEncoder().encode(result)
            let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
            XCTAssertEqual(decoded.errorKind, kind, "Round-trip failed for \(kind)")
        }
    }

    func testActionResultWithoutErrorKindDecodesAsNil() throws {
        let json = """
        {"type":"actionResult","payload":{"success":false,"method":"syntheticTap","message":"fail"}}
        """
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: Data(json.utf8))

        if case .actionResult(let result) = decoded {
            XCTAssertFalse(result.success)
            XCTAssertNil(result.errorKind)
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }

    // MARK: - ResponseEnvelope Background Accessibility Trace

    func testResponseEnvelopeWithoutBackgroundAccessibilityTrace() throws {
        let envelope = ResponseEnvelope(requestId: "r-1", message: .pong())
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: data)

        XCTAssertEqual(decoded.requestId, "r-1")
        XCTAssertNil(decoded.accessibilityTrace)
        if case .pong = decoded.message {
        } else {
            XCTFail("Expected pong, got \(decoded.message)")
        }
    }

    func testResponseEnvelopeCarriesBackgroundAccessibilityTraceOnly() throws {
        let before = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let after = makeTestInterface(elements: [
            HeistElement(
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
                actions: [.activate]
            ),
        ], timestamp: Date(timeIntervalSince1970: 1))
        let first = AccessibilityTrace.Capture(sequence: 1, interface: before, context: AccessibilityTrace.Context(screenId: "before"))
        let last = AccessibilityTrace.Capture(
            sequence: 2,
            interface: after,
            parentHash: first.hash,
            context: AccessibilityTrace.Context(screenId: "after")
        )
        let trace = AccessibilityTrace(captures: [first, last])
        let envelope = ResponseEnvelope(
            requestId: "capture-1",
            message: .pong(),
            accessibilityTrace: trace
        )
        let data = try JSONEncoder().encode(envelope)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["backgroundAccessibilityDelta"])
        XCTAssertNotNil(json["accessibilityTrace"])

        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        let receipt = try XCTUnwrap(decoded.accessibilityTrace?.receipts.first)
        XCTAssertEqual(receipt.kind, .capture)
        XCTAssertEqual(decoded.accessibilityTrace?.backgroundDelta?.kindRawValue, "screenChanged")
        XCTAssertEqual(decoded.accessibilityTrace?.backgroundDelta?.elementCount, 1)

        let reencoded = try JSONEncoder().encode(decoded)
        let reencodedJson = try XCTUnwrap(JSONSerialization.jsonObject(with: reencoded) as? [String: Any])
        XCTAssertNil(reencodedJson["backgroundAccessibilityDelta"])
        XCTAssertNotNil(reencodedJson["accessibilityTrace"])
    }

    func testResponseEnvelopeDropsObsoleteBackgroundDeltaField() throws {
        let oldShape: [String: Any] = [
            "buttonHeistVersion": TheScore.buttonHeistVersion,
            "requestId": "old-delta",
            "type": "pong",
            "payload": [
                "buttonHeistVersion": TheScore.buttonHeistVersion,
                "appName": "",
                "bundleIdentifier": "",
            ],
            "backgroundAccessibilityDelta": [
                "kind": "elementsChanged",
                "elementCount": 3,
                "edits": ["removed": ["old"]],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: oldShape)

        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        XCTAssertEqual(decoded.requestId, "old-delta")
        XCTAssertNil(decoded.accessibilityTrace)

        let reencoded = try JSONEncoder().encode(decoded)
        let reencodedJson = try XCTUnwrap(JSONSerialization.jsonObject(with: reencoded) as? [String: Any])
        XCTAssertNil(reencodedJson["backgroundAccessibilityDelta"])
        XCTAssertNil(reencodedJson["accessibilityTrace"])
    }

    func testResponseEnvelopeAccessibilityTraceOnlyShapeRoundTrips() throws {
        let envelope = ResponseEnvelope(
            requestId: "trace-only",
            message: .pong(),
            accessibilityTrace: AccessibilityTrace(interface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: []))
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: data)

        let receipt = try XCTUnwrap(decoded.accessibilityTrace?.receipts.first)
        XCTAssertEqual(receipt.sequence, 1)
        XCTAssertEqual(receipt.kind, .capture)
        XCTAssertEqual(receipt.interface.elements.count, 0)

        let reencoded = try JSONEncoder().encode(decoded)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: reencoded) as? [String: Any])
        XCTAssertNil(json["backgroundAccessibilityDelta"])
        XCTAssertNotNil(json["accessibilityTrace"])
    }

    func testScreenEncodeDecode() throws {
        let element = HeistElement(
            heistId: "visible_button",
            description: "Pay",
            label: "Pay",
            value: nil,
            identifier: "pay_button",
            traits: [.button],
            frameX: 20,
            frameY: 700,
            frameWidth: 160,
            frameHeight: 48,
            activationPointX: 100,
            activationPointY: 724,
            actions: [.activate]
        )
        let payload = ScreenPayload(
            pngData: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
            width: 390,
            height: 844,
            interface: makeTestInterface(elements: [element], timestamp: Date(timeIntervalSince1970: 42))
        )
        let message = ServerMessage.screen(payload)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ServerMessage.self, from: data)

        if case .screen(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload.pngData, payload.pngData)
            XCTAssertEqual(decodedPayload.width, 390)
            XCTAssertEqual(decodedPayload.height, 844)
            XCTAssertEqual(decodedPayload.interface.elements, [element])
            XCTAssertEqual(decodedPayload.interface.elements.first?.frameX, 20)
            XCTAssertEqual(decodedPayload.interface.elements.first?.activationPointX, 100)
        } else {
            XCTFail("Expected screen, got \(decoded)")
        }
    }

    private func interfaceWithHeader(
        _ label: String,
        heistId: HeistId,
        timestamp: TimeInterval = 0
    ) -> Interface {
        makeTestInterface(
            elements: [
                HeistElement(
                    heistId: heistId,
                    description: label,
                    label: label,
                    value: nil,
                    identifier: nil,
                    traits: [.header],
                    frameX: 0,
                    frameY: 0,
                    frameWidth: 100,
                    frameHeight: 44,
                    actions: []
                ),
            ],
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
    }

    private func interfaceWithoutHeader(timestamp: TimeInterval = 0) -> Interface {
        makeTestInterface(
            elements: [
                HeistElement(
                    heistId: "button-only",
                    description: "Continue",
                    label: "Continue",
                    value: nil,
                    identifier: nil,
                    traits: [.button],
                    frameX: 0,
                    frameY: 0,
                    frameWidth: 100,
                    frameHeight: 44,
                    actions: []
                ),
            ],
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
    }
}
