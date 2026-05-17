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

    func testInterfaceEncodeDecode() throws {
        let element = HeistElement(
            description: "Button",
            label: "Submit",
            value: nil,
            identifier: "submit_btn",
            frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
        let payload = Interface(timestamp: Date(), tree: [.element(element)])
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
        let message = ServerMessage.pong
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .pong = decoded {
        } else {
            XCTFail("Expected pong, got \(decoded)")
        }
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
        let interface = Interface(
            timestamp: Date(timeIntervalSince1970: 0),
            tree: [
                .element(HeistElement(
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
                )),
            ]
        )
        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityDelta: .noChange(.init(elementCount: 1)),
            accessibilityTrace: AccessibilityTrace(interface: interface)
        )

        let data = try JSONEncoder().encode(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(json["accessibilityDelta"])
        XCTAssertNotNil(json["accessibilityTrace"])
        XCTAssertNil(json["interfaceDelta"])
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

    // MARK: - ResponseEnvelope backgroundAccessibilityDelta

    func testResponseEnvelopeWithoutBackgroundDelta() throws {
        let envelope = ResponseEnvelope(requestId: "r-1", message: .pong)
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: data)

        XCTAssertEqual(decoded.requestId, "r-1")
        XCTAssertNil(decoded.backgroundAccessibilityDelta)
        XCTAssertNil(decoded.accessibilityTrace)
        if case .pong = decoded.message {
        } else {
            XCTFail("Expected pong, got \(decoded.message)")
        }
    }

    func testResponseEnvelopeWithBackgroundDelta() throws {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let delta: AccessibilityTrace.Delta = .screenChanged(.init(elementCount: 5, newInterface: interface))
        let envelope = ResponseEnvelope(requestId: "r-2", message: .pong, backgroundAccessibilityDelta: delta)
        let data = try JSONEncoder().encode(envelope)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["backgroundAccessibilityDelta"])
        XCTAssertNil(json["accessibilityTrace"])

        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: data)

        XCTAssertEqual(decoded.requestId, "r-2")
        XCTAssertNotNil(decoded.backgroundAccessibilityDelta)
        XCTAssertEqual(decoded.backgroundAccessibilityDelta?.isScreenChanged, true)
        XCTAssertEqual(decoded.backgroundAccessibilityDelta?.elementCount, 5)
        XCTAssertNil(decoded.accessibilityTrace)
    }

    func testResponseEnvelopeBackgroundDeltaBackwardCompatible() throws {
        // Envelopes from older servers (no backgroundAccessibilityDelta field) should decode cleanly
        let envelope = ResponseEnvelope(requestId: "compat-1", message: .pong)
        let data = try JSONEncoder().encode(envelope)

        // Re-encode without backgroundAccessibilityDelta by stripping it from the JSON
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "backgroundAccessibilityDelta")
        let strippedData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: strippedData)
        XCTAssertNil(decoded.backgroundAccessibilityDelta)
        XCTAssertNil(decoded.accessibilityTrace)
        XCTAssertEqual(decoded.requestId, "compat-1")
    }

    func testResponseEnvelopeCarriesAccessibilityTraceBesideDerivedBackgroundDelta() throws {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let delta: AccessibilityTrace.Delta = .screenChanged(.init(elementCount: 0, newInterface: interface))
        let envelope = ResponseEnvelope(
            requestId: "capture-1",
            message: .pong,
            backgroundAccessibilityDelta: delta,
            accessibilityTrace: AccessibilityTrace(interface: interface)
        )
        let data = try JSONEncoder().encode(envelope)

        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        XCTAssertEqual(decoded.backgroundAccessibilityDelta?.kindRawValue, "screenChanged")
        let receipt = try XCTUnwrap(decoded.accessibilityTrace?.receipts.first)
        XCTAssertEqual(receipt.kind, .capture)
        XCTAssertEqual(receipt.interface.tree, interface.tree)

        let reencoded = try JSONEncoder().encode(decoded)
        let reencodedJson = try XCTUnwrap(JSONSerialization.jsonObject(with: reencoded) as? [String: Any])
        XCTAssertNotNil(reencodedJson["backgroundAccessibilityDelta"])
        XCTAssertNotNil(reencodedJson["accessibilityTrace"])
    }

    func testResponseEnvelopeOldDeltaOnlyShapeDoesNotInventCapture() throws {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(
            elementCount: 3,
            edits: ElementEdits(removed: ["old"])
        ))
        let envelope = ResponseEnvelope(requestId: "compat-3", message: .pong, backgroundAccessibilityDelta: delta)
        let data = try JSONEncoder().encode(envelope)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "accessibilityTrace")
        let oldShapeData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: oldShapeData)
        XCTAssertEqual(decoded.backgroundAccessibilityDelta?.kindRawValue, "elementsChanged")
        XCTAssertNil(decoded.accessibilityTrace)

        let reencoded = try JSONEncoder().encode(decoded)
        let reencodedJson = try XCTUnwrap(JSONSerialization.jsonObject(with: reencoded) as? [String: Any])
        XCTAssertNotNil(reencodedJson["backgroundAccessibilityDelta"])
        XCTAssertNil(reencodedJson["accessibilityTrace"])
    }

    func testResponseEnvelopeAccessibilityTraceOnlyShapeRoundTrips() throws {
        let envelope = ResponseEnvelope(
            requestId: "trace-only",
            message: .pong,
            accessibilityTrace: AccessibilityTrace(interface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: []))
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: data)

        XCTAssertNil(decoded.backgroundAccessibilityDelta)
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
        let payload = ScreenPayload(
            pngData: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
            width: 390,
            height: 844
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
        } else {
            XCTFail("Expected screen, got \(decoded)")
        }
    }
}
