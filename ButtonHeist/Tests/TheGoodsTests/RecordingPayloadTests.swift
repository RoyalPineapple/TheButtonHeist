import XCTest
 import TheGoods

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
}
