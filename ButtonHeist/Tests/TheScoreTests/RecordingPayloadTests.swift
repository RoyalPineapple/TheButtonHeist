import XCTest
 import TheScore

final class RecordingPayloadTests: XCTestCase {

    // MARK: - RecordingConfig

    func testRecordingConfigAllFields() throws {
        let config = RecordingConfig(fps: 10, scale: 0.5, inactivityTimeout: 3.0, maxDuration: 30.0)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(RecordingConfig.self, from: data)

        XCTAssertEqual(decoded.fps, 10)
        XCTAssertEqual(decoded.scale, 0.5)
        XCTAssertEqual(decoded.inactivityTimeout, 3.0)
        XCTAssertEqual(decoded.maxDuration, 30.0)
    }

    func testRecordingConfigDefaults() throws {
        let config = RecordingConfig()
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(RecordingConfig.self, from: data)

        XCTAssertNil(decoded.fps)
        XCTAssertNil(decoded.scale)
        XCTAssertNil(decoded.inactivityTimeout)
        XCTAssertNil(decoded.maxDuration)
    }

    func testRecordingConfigPartialFields() throws {
        let config = RecordingConfig(fps: 5, maxDuration: 120.0)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(RecordingConfig.self, from: data)

        XCTAssertEqual(decoded.fps, 5)
        XCTAssertNil(decoded.scale)
        XCTAssertNil(decoded.inactivityTimeout)
        XCTAssertEqual(decoded.maxDuration, 120.0)
    }

    // MARK: - RecordingPayload

    func testRecordingPayloadEncodeDecode() throws {
        let start = Date()
        let end = start.addingTimeInterval(5.0)
        let payload = RecordingPayload(
            videoData: "AAAAIGZ0eXBpc29t",
            width: 390,
            height: 844,
            duration: 5.0,
            frameCount: 40,
            fps: 8,
            startTime: start,
            endTime: end,
            stopReason: .manual
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RecordingPayload.self, from: data)

        XCTAssertEqual(decoded.videoData, "AAAAIGZ0eXBpc29t")
        XCTAssertEqual(decoded.width, 390)
        XCTAssertEqual(decoded.height, 844)
        XCTAssertEqual(decoded.duration, 5.0)
        XCTAssertEqual(decoded.frameCount, 40)
        XCTAssertEqual(decoded.fps, 8)
        XCTAssertEqual(decoded.stopReason, .manual)
    }

    // MARK: - StopReason

    func testAllStopReasons() throws {
        let reasons: [RecordingPayload.StopReason] = [.manual, .inactivity, .maxDuration, .fileSizeLimit]
        for reason in reasons {
            let data = try JSONEncoder().encode(reason)
            let decoded = try JSONDecoder().decode(RecordingPayload.StopReason.self, from: data)
            XCTAssertEqual(decoded, reason)
        }
    }

    func testStopReasonRawValues() {
        XCTAssertEqual(RecordingPayload.StopReason.manual.rawValue, "manual")
        XCTAssertEqual(RecordingPayload.StopReason.inactivity.rawValue, "inactivity")
        XCTAssertEqual(RecordingPayload.StopReason.maxDuration.rawValue, "maxDuration")
        XCTAssertEqual(RecordingPayload.StopReason.fileSizeLimit.rawValue, "fileSizeLimit")
    }

    // MARK: - ClientMessage Recording Cases

    func testStartRecordingEncodeDecode() throws {
        let config = RecordingConfig(fps: 8, scale: 0.5)
        let message = ClientMessage.startRecording(config)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .startRecording(let decodedConfig) = decoded {
            XCTAssertEqual(decodedConfig.fps, 8)
            XCTAssertEqual(decodedConfig.scale, 0.5)
        } else {
            XCTFail("Expected startRecording, got \(decoded)")
        }
    }

    func testStopRecordingEncodeDecode() throws {
        let message = ClientMessage.stopRecording
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .stopRecording = decoded {
            // Success
        } else {
            XCTFail("Expected stopRecording, got \(decoded)")
        }
    }

    // MARK: - ServerMessage Recording Cases

    func testRecordingStartedEncodeDecode() throws {
        let message = ServerMessage.recordingStarted
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .recordingStarted = decoded {
            // Success
        } else {
            XCTFail("Expected recordingStarted, got \(decoded)")
        }
    }

    func testRecordingStoppedEncodeDecode() throws {
        let message = ServerMessage.recordingStopped
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .recordingStopped = decoded {
            // Success
        } else {
            XCTFail("Expected recordingStopped, got \(decoded)")
        }
    }

    func testRecordingEncodeDecode() throws {
        let start = Date()
        let end = start.addingTimeInterval(10.0)
        let payload = RecordingPayload(
            videoData: "AAAAIGZ0eXBpc29t",
            width: 195,
            height: 422,
            duration: 10.0,
            frameCount: 80,
            fps: 8,
            startTime: start,
            endTime: end,
            stopReason: .inactivity
        )
        let message = ServerMessage.recording(payload)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ServerMessage.self, from: data)

        if case .recording(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload.videoData, "AAAAIGZ0eXBpc29t")
            XCTAssertEqual(decodedPayload.width, 195)
            XCTAssertEqual(decodedPayload.height, 422)
            XCTAssertEqual(decodedPayload.duration, 10.0)
            XCTAssertEqual(decodedPayload.frameCount, 80)
            XCTAssertEqual(decodedPayload.stopReason, .inactivity)
        } else {
            XCTFail("Expected recording, got \(decoded)")
        }
    }

    func testRecordingErrorEncodeDecode() throws {
        let message = ServerMessage.recordingError("AVAssetWriter failed")
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .recordingError(let errorMsg) = decoded {
            XCTAssertEqual(errorMsg, "AVAssetWriter failed")
        } else {
            XCTFail("Expected recordingError, got \(decoded)")
        }
    }

    // MARK: - InteractionEvent

    func testInteractionEventActivateRoundTrip() throws {
        let delta: InterfaceDelta = .noChange(.init(elementCount: 5))
        let event = InteractionEvent(
            timestamp: 1.5,
            command: .activate(.matcher(ElementMatcher(identifier: "loginButton"))),
            result: ActionResult(success: true, method: .activate, interfaceDelta: delta)
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(InteractionEvent.self, from: data)

        XCTAssertEqual(decoded.timestamp, 1.5)
        guard case .activate(.matcher(let matcher, _)) = decoded.command else {
            return XCTFail("Expected activate with matcher")
        }
        XCTAssertEqual(matcher.identifier, "loginButton")
        XCTAssertTrue(decoded.result.success)
        XCTAssertEqual(decoded.result.method, .activate)
        XCTAssertEqual(decoded.result.interfaceDelta?.kindRawValue, "noChange")
        XCTAssertEqual(decoded.result.interfaceDelta?.elementCount, 5)
    }

    func testInteractionEventTouchTapRoundTrip() throws {
        let delta: InterfaceDelta = .elementsChanged(.init(
            elementCount: 1,
            edits: ElementEdits(updated: [
                ElementUpdate(
                    heistId: "okBtn",
                    changes: [PropertyChange(property: .value, old: nil, new: "tapped")]
                )
            ])
        ))
        let event = InteractionEvent(
            timestamp: 3.2,
            command: .touchTap(TouchTapTarget(elementTarget: .matcher(ElementMatcher(identifier: "okBtn")))),
            result: ActionResult(success: true, method: .syntheticTap, interfaceDelta: delta)
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(InteractionEvent.self, from: data)

        XCTAssertEqual(decoded.timestamp, 3.2)
        XCTAssertEqual(decoded.result.method, .syntheticTap)
        XCTAssertNotNil(decoded.result.interfaceDelta)
        XCTAssertEqual(decoded.result.interfaceDelta?.kindRawValue, "elementsChanged")
        XCTAssertEqual(decoded.result.interfaceDelta?.elementEdits?.updated.first?.heistId, "okBtn")
    }

    func testInteractionEventNilDelta() throws {
        // Failed actions have no delta
        let event = InteractionEvent(
            timestamp: 2.0,
            command: .activate(.matcher(ElementMatcher(identifier: "missing"))),
            result: ActionResult(success: false, method: .elementNotFound, message: "Element not found")
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(InteractionEvent.self, from: data)

        XCTAssertEqual(decoded.timestamp, 2.0)
        XCTAssertFalse(decoded.result.success)
        XCTAssertEqual(decoded.result.method, .elementNotFound)
        XCTAssertNil(decoded.result.interfaceDelta)
    }

    func testRecordingPayloadWithInteractionLog() throws {
        let start = Date()
        let end = start.addingTimeInterval(5.0)
        let event = InteractionEvent(
            timestamp: 1.0,
            command: .activate(.matcher(ElementMatcher(label: "element_3"))),
            result: ActionResult(success: true, method: .activate, interfaceDelta: .noChange(.init(elementCount: 0)))
        )
        let payload = RecordingPayload(
            videoData: "AAAAIGZ0eXBpc29t",
            width: 390, height: 844,
            duration: 5.0, frameCount: 40, fps: 8,
            startTime: start, endTime: end,
            stopReason: .manual,
            interactionLog: [event]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RecordingPayload.self, from: data)

        XCTAssertNotNil(decoded.interactionLog)
        XCTAssertEqual(decoded.interactionLog?.count, 1)
        XCTAssertEqual(decoded.interactionLog?.first?.timestamp, 1.0)
    }

    func testRecordingPayloadNilInteractionLog() throws {
        let start = Date()
        let end = start.addingTimeInterval(5.0)
        let payload = RecordingPayload(
            videoData: "AAAAIGZ0eXBpc29t",
            width: 390, height: 844,
            duration: 5.0, frameCount: 40, fps: 8,
            startTime: start, endTime: end,
            stopReason: .manual
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RecordingPayload.self, from: data)

        XCTAssertNil(decoded.interactionLog)
    }

    func testRecordingPayloadDecodingWithoutInteractionLog() throws {
        // interactionLog is optional — absent field decodes as nil
        let json = """
        {
            "videoData": "AAAAIGZ0eXBpc29t",
            "width": 390,
            "height": 844,
            "duration": 5.0,
            "frameCount": 40,
            "fps": 8,
            "startTime": 0,
            "endTime": 5,
            "stopReason": "manual"
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RecordingPayload.self, from: data)

        XCTAssertEqual(decoded.videoData, "AAAAIGZ0eXBpc29t")
        XCTAssertEqual(decoded.width, 390)
        XCTAssertNil(decoded.interactionLog)
    }
}
