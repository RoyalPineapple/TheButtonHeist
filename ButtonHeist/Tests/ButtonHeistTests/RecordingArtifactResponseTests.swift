import XCTest
@testable import ButtonHeist
import TheScore

final class RecordingArtifactResponseTests: XCTestCase {

    @ButtonHeistActor
    func testDefaultStopRecordingWritesArtifactAndOmitsInlineDataAndInteractionLog() async throws {
        let tempDirectory = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let videoBytes = Data("video".utf8)
        let payload = Self.makeRecordingPayload(
            videoData: videoBytes.base64EncodedString(),
            interactionCount: 1
        )
        let fence = Self.makeFence(tempDirectory: tempDirectory, payload: payload)

        let response = try await fence.execute(request: ["command": "stop_recording"])

        guard case .recording(let path, let recording) = response else {
            return XCTFail("Expected recording artifact response, got \(response)")
        }
        XCTAssertEqual(recording.width, 390)
        XCTAssertEqual(recording.height, 844)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), videoBytes)

        let json = publicJSONObject(response)
        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertEqual(json["path"] as? String, path)
        XCTAssertEqual(json["interactionCount"] as? Int, 1)
        XCTAssertNil(json["videoData"])
        XCTAssertNil(json["interactionLog"])
    }

    @ButtonHeistActor
    func testExpandedStopRecordingRequiresExplicitFlagsAndRemainsBounded() async throws {
        let tempDirectory = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let videoData = Data("video".utf8).base64EncodedString()
        let payload = Self.makeRecordingPayload(videoData: videoData, interactionCount: 2)
        let fence = Self.makeFence(tempDirectory: tempDirectory, payload: payload)

        let response = try await fence.execute(request: [
            "command": "stop_recording",
            "inlineData": true,
            "includeInteractionLog": true,
        ])

        guard case .recordingExpanded(let path, let recording, let options) = response else {
            return XCTFail("Expected expanded recording response, got \(response)")
        }
        XCTAssertTrue(options.inlineData)
        XCTAssertTrue(options.includeInteractionLog)
        XCTAssertEqual(recording.videoData, videoData)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data("video".utf8))

        let json = try JSONDecoder().decode(
            ExpandedRecordingPublicJSON.self,
            from: response.jsonData()
        )
        XCTAssertEqual(json.status, "ok")
        XCTAssertEqual(json.path, path)
        XCTAssertEqual(json.videoData, videoData)
        XCTAssertEqual(json.interactionLog?.count, 2)
    }

    @ButtonHeistActor
    func testInlineStopRecordingRejectsOversizePayloadBeforeDelivery() async throws {
        let tempDirectory = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let oversizedPayload = String(
            repeating: "A",
            count: TheFence.DecodeLimits.maxInlineRecordingBase64Bytes + 1
        )
        let payload = Self.makeRecordingPayload(videoData: oversizedPayload, interactionCount: 0)
        let fence = Self.makeFence(tempDirectory: tempDirectory, payload: payload)

        let response = try await fence.execute(request: [
            "command": "stop_recording",
            "inlineData": true,
        ])

        guard case .error(let message, let details) = response else {
            return XCTFail("Expected oversize inline error, got \(response)")
        }
        XCTAssertTrue(message.contains("Inline recording payload is too large"))
        XCTAssertEqual(details?.errorCode, "recording.inline_payload_too_large")
        XCTAssertEqual(details?.phase, .client)
        XCTAssertEqual(details?.retryable, false)
        XCTAssertNil(publicJSONObject(response)["videoData"])
    }

    @ButtonHeistActor
    func testStopRecordingInvalidOutputThrowsTypedInvalidRequest() async throws {
        let tempDirectory = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let payload = Self.makeRecordingPayload(
            videoData: Data("video".utf8).base64EncodedString(),
            interactionCount: 0
        )
        let fence = Self.makeFence(tempDirectory: tempDirectory, payload: payload)

        do {
            _ = try await fence.execute(request: [
                "command": "stop_recording",
                "output": "/tmp/../buttonheist-recording.mp4",
            ])
            XCTFail("Expected invalid output path to throw")
        } catch let error as FenceError {
            guard case .invalidRequest(let message) = error else {
                return XCTFail("Expected invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains("Invalid output path"))
        } catch {
            XCTFail("Expected FenceError.invalidRequest, got \(error)")
        }
    }

    @ButtonHeistActor
    func testStopRecordingInvalidBase64ThrowsTypedServerError() async throws {
        let tempDirectory = Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let payload = Self.makeRecordingPayload(videoData: "not base64", interactionCount: 0)
        let fence = Self.makeFence(tempDirectory: tempDirectory, payload: payload)

        do {
            _ = try await fence.execute(request: ["command": "stop_recording"])
            XCTFail("Expected invalid recording base64 to throw")
        } catch let error as FenceError {
            guard case .serverError(let serverError) = error else {
                return XCTFail("Expected serverError, got \(error)")
            }
            XCTAssertEqual(serverError.kind, .recording)
            XCTAssertEqual(serverError.message, "Failed to decode video data")
        } catch {
            XCTFail("Expected FenceError.serverError, got \(error)")
        }
    }

    private static func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("buttonheist-recording-\(UUID().uuidString)", isDirectory: true)
    }

    @ButtonHeistActor
    private static func makeFence(
        tempDirectory: URL,
        payload: RecordingPayload
    ) -> TheFence {
        let config = TheFence.Configuration(bookKeeperBaseDirectory: tempDirectory)
        let (fence, mockConnection) = makeConnectedFence(configuration: config)
        mockConnection.autoResponse = { message in
            switch message {
            case .stopRecording:
                return .recording(payload)
            case .requestInterface:
                return .interface(Interface(timestamp: Date(), tree: []))
            default:
                return .actionResult(ActionResult(success: true, method: .activate))
            }
        }
        return fence
    }

    private static func makeRecordingPayload(
        videoData: String,
        interactionCount: Int
    ) -> RecordingPayload {
        let start = Date(timeIntervalSince1970: 0)
        let events = (0..<interactionCount).map { index in
            InteractionEvent(
                timestamp: Double(index),
                command: .activate(.matcher(ElementMatcher(label: "element_\(index)"))),
                result: ActionResult(success: true, method: .activate)
            )
        }
        return RecordingPayload(
            videoData: videoData,
            width: 390,
            height: 844,
            duration: 2.0,
            frameCount: 16,
            fps: 8,
            startTime: start,
            endTime: start.addingTimeInterval(2.0),
            stopReason: .manual,
            interactionLog: events
        )
    }

    private struct ExpandedRecordingPublicJSON: Decodable {
        let status: String
        let path: String
        let videoData: String
        let interactionLog: [InteractionEvent]?
    }
}
