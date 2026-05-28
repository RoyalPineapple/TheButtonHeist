import XCTest
import AccessibilitySnapshotModel
@testable import ButtonHeist
import TheScore

final class PublicContractGoldenTests: XCTestCase {
    func testCommandCatalogDescriptionsAreExplicit() {
        for descriptor in TheFence.Command.descriptors {
            XCTAssertEqual(
                descriptor.description,
                TheFence.Command.presentationDescription(for: descriptor.canonicalName),
                "\(descriptor.canonicalName) should project public prose from the descriptor presentation layer."
            )
            XCTAssertFalse(
                descriptor.description.contains("missing a public description"),
                "\(descriptor.canonicalName) must not expose descriptor fallback prose."
            )
            XCTAssertFalse(
                descriptor.description.contains("Execute the "),
                "\(descriptor.canonicalName) must not expose prototype command prose."
            )
        }

        for contract in TheFence.Command.mcpToolContracts {
            XCTAssertEqual(
                contract.description,
                TheFence.Command.presentationDescription(for: contract.name),
                "\(contract.name) should project MCP prose from the descriptor presentation layer."
            )
            XCTAssertFalse(
                contract.description.contains("missing a public description"),
                "\(contract.name) must not expose descriptor fallback prose."
            )
            XCTAssertFalse(
                contract.description.contains("Execute the "),
                "\(contract.name) must not expose prototype command prose."
            )
        }
    }

    func testGetInterfacePublicJSONGolden() throws {
        let interface = makeReceiptTestInterface([
            makeReceiptTestElement(heistId: "pay_button", label: "Pay", traits: [.button]),
        ])

        XCTAssertEqual(
            try jsonString(FenceResponse.interface(interface, detail: .summary)),
            golden(
                #"{"detail":"summary","interface":{"navigation":{},"#,
                #""screenDescription":"1 button","timestamp":"1970-01-01T00:00:00Z","tree":["#,
                #"{"element":{"heistId":"pay_button","label":"Pay","order":0,"traits":["button"]}}"#,
                #"]},"status":"ok"}"#
            )
        )
    }

    func testActionSuccessPublicJSONGolden() throws {
        let result = ActionResult(
            success: true,
            method: .getPasteboard,
            payload: .value("copied"),
            screenName: "Receipt",
            screenId: "receipt"
        )

        XCTAssertEqual(
            try jsonString(FenceResponse.action(result: result)),
            #"{"method":"get_pasteboard","screenId":"receipt","screenName":"Receipt","status":"ok","value":"copied"}"#
        )
    }

    func testPublicJSONRequestIdIsAddedAtSerializerBoundary() throws {
        XCTAssertEqual(
            try jsonString(FenceResponse.ok(message: "done"), requestId: .string("req-1")),
            #"{"id":"req-1","message":"done","status":"ok"}"#
        )
    }

    func testPublicJSONRequestIdPreservesExactScalarIdentity() throws {
        XCTAssertEqual(
            try jsonString(FenceResponse.ok(message: "done"), requestId: .signedInteger(42)),
            #"{"id":42,"message":"done","status":"ok"}"#
        )
        XCTAssertEqual(
            try jsonString(FenceResponse.ok(message: "done"), requestId: .signedInteger(Int64.max)),
            #"{"id":9223372036854775807,"message":"done","status":"ok"}"#
        )
        XCTAssertEqual(
            try jsonString(FenceResponse.ok(message: "done"), requestId: .unsignedInteger(UInt64.max)),
            #"{"id":18446744073709551615,"message":"done","status":"ok"}"#
        )
        XCTAssertEqual(
            try jsonString(FenceResponse.ok(message: "done"), requestId: .double(1.25)),
            #"{"id":1.25,"message":"done","status":"ok"}"#
        )
        XCTAssertEqual(
            try jsonString(FenceResponse.ok(message: "done"), requestId: .null),
            #"{"id":null,"message":"done","status":"ok"}"#
        )
    }

    func testPublicJSONRequestIdRejectsNonScalarValues() {
        XCTAssertThrowsError(
            try PublicRequestId(value: ["nested": "object"])
        )
        XCTAssertThrowsError(
            try PublicRequestId(value: ["array"])
        )
        XCTAssertThrowsError(
            try PublicRequestId(value: true)
        )
    }

    func testPublicJSONRequestIdRejectsNonFiniteNumbers() {
        XCTAssertThrowsError(
            try PublicRequestId(value: Double.nan)
        )
        XCTAssertThrowsError(
            try PublicRequestId(value: Double.infinity)
        )
    }

    func testPongPublicJSONGolden() throws {
        let payload = PongPayload(
            buttonHeistVersion: "2026.05.22",
            appName: "MockApp",
            bundleIdentifier: "com.test.mock",
            appVersion: "1.0",
            appBuild: "42",
            serverInstanceIdentifier: "server-1",
            serverTimestampMs: 1_700_000_000_000
        )

        XCTAssertEqual(
            try jsonString(FenceResponse.pong(payload)),
            golden(
                #"{"appBuild":"42","appName":"MockApp","appVersion":"1.0","#,
                #""bundleIdentifier":"com.test.mock","buttonHeistVersion":"2026.05.22","#,
                #""serverInstanceIdentifier":"server-1","serverTimestampMs":1700000000000,"status":"ok"}"#
            )
        )
    }

    func testActionFailurePublicJSONGolden() throws {
        let result = ActionResult(
            success: false,
            method: .activate,
            message: #"No element matching label "Buy""#,
            errorKind: .elementNotFound
        )

        XCTAssertEqual(
            try jsonString(FenceResponse.action(result: result)),
            #"{"errorClass":"elementNotFound","message":"No element matching label \"Buy\"","method":"activate","status":"error"}"#
        )
    }

    func testStructuredFailurePublicJSONGolden() throws {
        let response = FenceResponse.error(
            "Malformed request",
            details: FailureDetails(
                errorCode: "request.invalid",
                phase: .request,
                retryable: false,
                hint: "Fix command payload"
            )
        )

        XCTAssertEqual(
            try jsonString(response),
            golden(
                #"{"errorCode":"request.invalid","hint":"Fix command payload","#,
                #""message":"Malformed request","phase":"request","#,
                #""retryable":false,"status":"error"}"#
            )
        )
    }

    @ButtonHeistActor
    func testMissingTargetFailurePublicJSONGolden() async throws {
        let (fence, _) = makeConnectedFence()
        let response = try await fence.execute(request: [
            "command": TheFence.Command.activate.rawValue,
        ])

        XCTAssertEqual(
            try jsonString(response),
            golden(
                #"{"errorCode":"request.missing_target","hint":"get_interface()","#,
                #""message":"activate request contract failed: missing target; requires target object with heistId or matcher. "#,
                #"Next: get_interface() to inspect the current app accessibility state, then retry activate with "#,
                #"target.heistId or target.matcher.","phase":"request","#,
                #""retryable":false,"status":"error"}"#
            )
        )
    }

    func testScreenshotArtifactPublicJSONGolden() throws {
        let payload = ScreenPayload(
            pngData: "abc123",
            width: 393,
            height: 852,
            timestamp: Date(timeIntervalSince1970: 0),
            interface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        )

        XCTAssertEqual(
            try jsonString(FenceResponse.screenshot(path: "/tmp/screen.png", payload: payload)),
            #"{"height":852,"path":"\/tmp\/screen.png","status":"ok","width":393}"#
        )
    }

    func testScreenshotInlinePublicJSONGolden() throws {
        let payload = ScreenPayload(
            pngData: "abc123",
            width: 393,
            height: 852,
            timestamp: Date(timeIntervalSince1970: 0),
            interface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        )

        XCTAssertEqual(
            try jsonString(FenceResponse.screenshotData(payload: payload)),
            #"{"height":852,"pngData":"abc123","status":"ok","width":393}"#
        )
    }

    func testRecordingArtifactPublicJSONGolden() throws {
        let payload = RecordingPayload(
            videoData: Data("video".utf8).base64EncodedString(),
            width: 390,
            height: 844,
            duration: 2,
            frameCount: 16,
            fps: 8,
            startTime: Date(timeIntervalSince1970: 0),
            endTime: Date(timeIntervalSince1970: 2),
            stopReason: .manual
        )

        XCTAssertEqual(
            try jsonString(FenceResponse.recording(path: "/tmp/recording.mp4", payload: payload)),
            golden(
                #"{"duration":2,"fps":8,"frameCount":16,"height":844,"interactionCount":0,"#,
                #""path":"\/tmp\/recording.mp4","status":"ok","stopReason":"manual","width":390}"#
            )
        )
    }

    func testRecordingExpandedPublicJSONGolden() throws {
        let payload = RecordingPayload(
            videoData: Data("video".utf8).base64EncodedString(),
            width: 390,
            height: 844,
            duration: 2,
            frameCount: 16,
            fps: 8,
            startTime: Date(timeIntervalSince1970: 0),
            endTime: Date(timeIntervalSince1970: 2),
            stopReason: .manual,
            interactionLog: []
        )
        let response = FenceResponse.recordingExpanded(
            path: "/tmp/recording.mp4",
            payload: payload,
            options: RecordingResponseOptions(inlineData: true, includeInteractionLog: true)
        )

        XCTAssertEqual(
            try jsonString(response),
            golden(
                #"{"duration":2,"fps":8,"frameCount":16,"height":844,"interactionCount":0,"#,
                #""interactionLog":[],"path":"\/tmp\/recording.mp4","status":"ok","#,
                #""stopReason":"manual","videoData":"dmlkZW8=","width":390}"#
            )
        )
    }

    func testBatchPublicJSONGolden() throws {
        let response = FenceResponse.batch(
            outcomes: [
                BatchStepOutcome(command: "wait_for", response: .ok(message: "ready")),
                BatchStepOutcome(command: "activate", response: .error("boom"), stopsBatch: true),
                .skipped(command: "type_text", afterFailedIndex: 1),
            ],
            totalTimingMs: 42
        )

        XCTAssertEqual(
            try jsonString(response),
            golden(
                #"{"completedSteps":2,"failedIndex":1,"results":["#,
                #"{"message":"ready","status":"ok"},{"message":"boom","status":"error"}],"#,
                #""status":"partial","stepSummaries":["#,
                #"{"command":"wait_for","index":0},{"command":"activate","error":"boom","index":1},"#,
                #"{"command":"type_text","error":"skipped: stop_on_error stopped batch after step 1","index":2}"#,
                #"],"totalTimingMs":42}"#
            )
        )
    }

    func testPlaybackFailurePublicJSONGolden() throws {
        let failure = PlaybackFailure.fenceError(
            step: PlaybackFailure.FailedStep(
                command: "activate",
                target: semanticTarget(label: "Pay", traits: [.button])
            ),
            message: "not connected",
            interface: nil,
            diagnosticCaptureFailure: nil
        )

        XCTAssertEqual(
            try jsonString(FenceResponse.heistPlayback(
                completedSteps: 1,
                failedIndex: 1,
                totalTimingMs: 25,
                failure: failure
            )),
            golden(
                #"{"completedSteps":1,"failedIndex":1,"failure":{"command":"activate","#,
                #""error":"not connected","target":{"matcher":{"label":"Pay","traits":["button"]}}},"#,
                #""status":"error","totalTimingMs":25}"#
            )
        )
    }

    func testPlaybackFailureDiagnosticCaptureFailurePublicJSONGolden() throws {
        let failure = PlaybackFailure.fenceError(
            step: PlaybackFailure.FailedStep(
                command: "activate",
                target: semanticTarget(label: "Pay", traits: [.button])
            ),
            message: "not connected",
            interface: nil,
            diagnosticCaptureFailure: "diagnostic interface unavailable"
        )

        XCTAssertEqual(
            try jsonString(FenceResponse.heistPlayback(
                completedSteps: 1,
                failedIndex: 1,
                totalTimingMs: 25,
                failure: failure
            )),
            golden(
                #"{"completedSteps":1,"failedIndex":1,"failure":{"command":"activate","#,
                #""diagnosticCaptureFailure":"diagnostic interface unavailable","#,
                #""error":"not connected","target":{"matcher":{"label":"Pay","traits":["button"]}}},"#,
                #""status":"error","totalTimingMs":25}"#
            )
        )
    }

    func testRequestEnvelopeWireGolden() throws {
        let request = RequestEnvelope(
            buttonHeistVersion: "0.4.2-test",
            requestId: "req-1",
            message: .activate(.matcher(ElementMatcher(label: "Pay", traits: [.button])))
        )

        XCTAssertEqual(
            try sortedJSONString(request),
            #"{"buttonHeistVersion":"0.4.2-test","payload":{"label":"Pay","traits":["button"]},"requestId":"req-1","type":"activate"}"#
        )
    }

    func testApprovalPendingResponseEnvelopeWireGolden() throws {
        let response = ResponseEnvelope(
            buttonHeistVersion: "0.4.2-test",
            requestId: "req-1",
            message: .authApprovalPending(AuthApprovalPendingPayload())
        )

        XCTAssertEqual(
            try sortedJSONString(response),
            golden(
                #"{"buttonHeistVersion":"0.4.2-test","payload":{"hint":"Tap Allow on the iOS device to continue.","#,
                #""message":"Waiting for approval on the device."},"requestId":"req-1","type":"authApprovalPending"}"#
            )
        )
    }

    func testHeistPlaybackWireGolden() throws {
        let playback = HeistPlayback(
            version: HeistPlayback.currentVersion,
            recorded: Date(timeIntervalSince1970: 0),
            app: "com.buttonheist.testapp",
            steps: [
                HeistEvidence(
                    command: "activate",
                    target: semanticTarget(label: "Pay", traits: [.button])
                ),
                HeistEvidence(
                    command: "type_text",
                    target: semanticTarget(label: "Note"),
                    arguments: ["text": .string("hello")]
                ),
            ]
        )

        XCTAssertEqual(
            try sortedJSONString(playback, dateEncodingStrategy: .iso8601),
            golden(
                #"{"app":"com.buttonheist.testapp","recorded":"1970-01-01T00:00:00Z","steps":["#,
                #"{"command":"activate","target":{"matcher":{"label":"Pay","traits":["button"]}}},"#,
                #"{"command":"type_text","target":{"matcher":{"label":"Note"}},"text":"hello"}],"version":3}"#
            )
        )
    }

    private func golden(_ parts: String...) -> String {
        parts.joined()
    }

    private func jsonString(_ response: FenceResponse) throws -> String {
        let data = try response.jsonData()
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func jsonString(_ response: FenceResponse, requestId: PublicRequestId) throws -> String {
        let data = try response.jsonData(requestId: requestId)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func sortedJSONString<T: Encodable>(
        _ value: T,
        dateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .deferredToDate
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = dateEncodingStrategy
        let data = try encoder.encode(value)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

}
