import XCTest
import AccessibilitySnapshotModel
@testable import ButtonHeist
import TheScore

final class PublicContractGoldenTests: XCTestCase {
    private let publicDictionaryAdapterCall = "json" + "Dict("
    private let publicDictionaryAdapterPath = "compatibility" + "Dictionary"

    func testPublicJSONFormattingCentralFileRemainsTypedEntrypoint() throws {
        let source = try sourceFile("ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+Formatting+JSON.swift")

        XCTAssertLessThanOrEqual(
            lineCount(source),
            110,
            "TheFence+Formatting+JSON.swift should stay a small typed JSON entrypoint."
        )
        XCTAssertTrue(
            source.contains("PublicResponseModel(response: self)"),
            "FenceResponse.jsonData should encode the typed public response model."
        )
        let serializer = try sourceFile("ButtonHeist/Sources/TheButtonHeist/TheFence/PublicJSONSerializer.swift")
        XCTAssertTrue(
            serializer.contains("enum PublicJSONSerializer"),
            "Request-id object bridging should stay behind the named public JSON serializer."
        )
        XCTAssertFalse(
            serializer.contains(publicDictionaryAdapterPath),
            "Public JSON should not expose a Foundation dictionary compatibility path."
        )

        let forbiddenRuntimeFormatting = [
            "case .interface",
            "case .action",
            "case .screenshot",
            "case .recording",
            "case .batch",
            "case .sessionState",
            "case .heistPlayback",
            "PublicInterfaceResponse(",
            "PublicActionResponse(",
            "PublicScreenshotResponse(",
            "PublicRecordingResponse(",
            "PublicBatchResponse(",
            "PublicSessionStateResponse(",
            "PublicPlaybackResponse(",
        ]

        for pattern in forbiddenRuntimeFormatting {
            XCTAssertFalse(
                source.contains(pattern),
                "The central JSON shim should not hand-shape public JSON with \(pattern)."
            )
        }
    }

    func testPublicJSONHandShapingIsContainedToSerializerShim() throws {
        let fenceDirectory = try sourceDirectory("ButtonHeist/Sources/TheButtonHeist/TheFence")
        let formattingSources = try FileManager.default.contentsOfDirectory(
            at: fenceDirectory,
            includingPropertiesForKeys: nil
        )
            .filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix("FenceJSON+")
                    || name.hasPrefix("TheFence+Formatting")
                    || name == "PublicJSONSerializer.swift"
            }

        XCTAssertFalse(formattingSources.isEmpty)

        for file in formattingSources {
            let source = try String(contentsOf: file, encoding: .utf8)
            let isSerializerShim = file.lastPathComponent == "PublicJSONSerializer.swift"

            if isSerializerShim {
                XCTAssertTrue(source.contains("PublicJSONSerializer"))
                XCTAssertFalse(source.contains(publicDictionaryAdapterPath))
                continue
            }

            XCTAssertFalse(
                source.contains("[String: Any]"),
                "\(file.lastPathComponent) should render from typed Encodable models, not Foundation dictionaries."
            )
            XCTAssertFalse(
                source.contains("JSONSerialization"),
                "\(file.lastPathComponent) should not cross the final JSON serialization boundary."
            )
            XCTAssertFalse(
                source.contains(publicDictionaryAdapterCall),
                "\(file.lastPathComponent) should not call a Foundation dictionary public JSON adapter."
            )
        }
    }

    func testCLIJSONOutputUsesTypedSerializerBoundary() throws {
        let source = try sourceFile("ButtonHeistCLI/Sources/Session/SessionRepl.swift")

        XCTAssertTrue(
            source.contains("response.jsonData(requestId: id)"),
            "REPL JSON output should serialize the typed public response model with request id at the serializer boundary."
        )
        XCTAssertFalse(
            source.contains("publicJSONObject(response)"),
            "REPL JSON output must not round-trip through a Foundation dictionary public JSON adapter."
        )
    }

    func testPublicJSONResponseFamiliesStaySplitByDomain() throws {
        let expectedFamilies: [(path: String, maximumLines: Int, requiredTypes: [String])] = [
            (
                "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Observation.swift",
                400,
                ["PublicInterfaceResponse", "PublicScreenshotResponse"]
            ),
            (
                "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Action.swift",
                350,
                ["PublicActionResponse", "PublicBatchResponse"]
            ),
            (
                "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Recording.swift",
                120,
                ["PublicRecordingResponse", "PublicHeistStartedResponse", "PublicHeistStoppedResponse"]
            ),
            (
                "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Session.swift",
                260,
                ["PublicSessionStateResponse", "PublicPongResponse", "PublicOKResponse", "PublicHelpResponse"]
            ),
            (
                "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Playback.swift",
                120,
                ["PublicPlaybackResponse"]
            ),
            (
                "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceJSON+Response.swift",
                160,
                ["PublicResponseModel", "PublicErrorResponse"]
            ),
        ]

        for family in expectedFamilies {
            let source = try sourceFile(family.path)

            XCTAssertLessThanOrEqual(
                lineCount(source),
                family.maximumLines,
                "\(family.path) is getting too broad; split new public JSON behavior by response family."
            )
            XCTAssertFalse(
                source.contains("[String: Any]"),
                "\(family.path) should encode typed public JSON models, not hand-shaped dictionaries."
            )
            XCTAssertFalse(
                source.contains("JSONSerialization"),
                "\(family.path) should stay typed; JSONSerialization belongs only at serializer edges."
            )

            for type in family.requiredTypes {
                XCTAssertTrue(
                    source.contains(type),
                    "\(type) should stay in \(family.path) so public JSON formatting remains split by domain."
                )
            }
        }
    }

    func testCommandCatalogDescriptionsAreDescriptorBackedAndExplicit() throws {
        let catalog = try sourceFile("ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+CommandCatalog.swift")

        XCTAssertTrue(
            catalog.contains("presentationDescription(for:"),
            "Descriptors and MCP contracts should project help text from command presentation files."
        )

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

    func testNormalizedOperationsDoNotExposeRawBatchArguments() throws {
        let catalog = try sourceFile("ButtonHeist/Sources/TheButtonHeist/TheFence/FenceOperationCatalog.swift")
        let normalizedOperation = try XCTUnwrap(
            catalog.range(of: "public struct NormalizedOperation").flatMap { start in
                catalog.range(of: "/// Shared routing table", range: start.upperBound..<catalog.endIndex).map { end in
                    String(catalog[start.lowerBound..<end.lowerBound])
                }
            }
        )
        XCTAssertFalse(
            normalizedOperation.contains("[String: Any]"),
            "NormalizedOperation should carry a typed routed request, not expose raw dictionaries."
        )
        XCTAssertTrue(
            normalizedOperation.contains("RoutedCommandRequest"),
            "NormalizedOperation should keep routed request metadata behind a typed envelope."
        )
        XCTAssertTrue(
            catalog.contains("routeBatchStepDecodeInput"),
            "Raw batch steps should be adapted at a named decode edge before batch planning."
        )

        let batchParser = try sourceFile(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+BatchCommandParser.swift"
        )
        XCTAssertFalse(
            batchParser.contains("[String: Any]"),
            "Batch planning should consume routed batch steps, not raw batch step dictionaries."
        )
        XCTAssertTrue(
            batchParser.contains("RoutedBatchStep"),
            "Batch planning should receive typed routed batch steps from the catalog."
        )
        XCTAssertFalse(
            batchParser.contains("operation.arguments"),
            "Batch planning should consume parsed requests, not raw operation arguments."
        )
        XCTAssertFalse(
            batchParser.contains("operation.request.arguments"),
            "Batch planning should consume parsed requests, not raw routed request dictionaries."
        )

        let clientMessageLowering = try sourceFile(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+ClientMessageLowering.swift"
        )
        XCTAssertTrue(
            clientMessageLowering.contains("func clientMessageExecutionPlan"),
            "Direct command execution should lower through the shared client-message plan."
        )
        XCTAssertTrue(
            clientMessageLowering.contains("func batchActionPlan"),
            "Batch step planning should lower through the same client-message path as direct execution."
        )
        let forbiddenLoweringPatterns = [
            "[String: Any]",
            "schemaString(",
            "schemaInteger(",
            "schemaDictionary(",
            "operation.arguments",
            "operation.request.arguments",
        ]
        for pattern in forbiddenLoweringPatterns {
            XCTAssertFalse(
                clientMessageLowering.contains(pattern),
                "Client-message lowering should map typed parsed requests, not parse raw dictionaries with \(pattern)."
            )
        }
    }

    func testBatchEligibilityIsFenceCatalogOwned() throws {
        let batchAction = try sourceFile("ButtonHeist/Sources/TheScore/BatchAction.swift")
        XCTAssertFalse(
            batchAction.contains("isBatchExecutableCommand"),
            "TheScore batch steps should not mirror Fence batch eligibility."
        )
        XCTAssertFalse(
            batchAction.contains("not batch-executable"),
            "Batch eligibility failures should come from Fence command descriptors."
        )

        let operationCatalog = try sourceFile(
            "ButtonHeist/Sources/TheButtonHeist/TheFence/FenceOperationCatalog.swift"
        )
        XCTAssertTrue(
            operationCatalog.contains("isExecutable: \\.isBatchExecutable"),
            "run_batch routing should validate eligibility through Fence command descriptors."
        )
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
            #"{"method":"getPasteboard","screenId":"receipt","screenName":"Receipt","status":"ok","value":"copied"}"#
        )
    }

    func testPublicJSONRequestIdIsAddedAtSerializerBoundary() throws {
        XCTAssertEqual(
            try jsonString(FenceResponse.ok(message: "done"), requestId: "req-1"),
            #"{"id":"req-1","message":"done","status":"ok"}"#
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
                #""message":"activate request contract failed: missing target; requires heistId, ordinal, or at least one matcher field "#,
                #"(label, identifier, value, traits, or excludeTraits). Next: get_interface() to inspect the current app accessibility "#,
                #"state, then retry activate with a heistId, exact matcher, or ordinal selector.","phase":"request","#,
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
                BatchStepOutcome(command: "status", response: .ok(message: "ready")),
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
                #"{"command":"status","index":0},{"command":"activate","error":"boom","index":1},"#,
                #"{"command":"type_text","error":"skipped: stop_on_error stopped batch after step 1","index":2}"#,
                #"],"totalTimingMs":42}"#
            )
        )
    }

    func testPlaybackFailurePublicJSONGolden() throws {
        let failure = PlaybackFailure.fenceError(
            step: PlaybackFailure.FailedStep(
                command: "activate",
                target: ElementMatcher(label: "Pay", traits: [.button])
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
                #""error":"not connected","target":{"label":"Pay","traits":["button"]}},"#,
                #""status":"error","totalTimingMs":25}"#
            )
        )
    }

    func testPlaybackFailureDiagnosticCaptureFailurePublicJSONGolden() throws {
        let failure = PlaybackFailure.fenceError(
            step: PlaybackFailure.FailedStep(
                command: "activate",
                target: ElementMatcher(label: "Pay", traits: [.button])
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
                #""error":"not connected","target":{"label":"Pay","traits":["button"]}},"#,
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
            version: 2,
            recorded: Date(timeIntervalSince1970: 0),
            app: "com.buttonheist.testapp",
            steps: [
                HeistEvidence(
                    command: "activate",
                    target: ElementMatcher(label: "Pay", traits: [.button])
                ),
                HeistEvidence(
                    command: "type_text",
                    target: ElementMatcher(label: "Note"),
                    arguments: ["text": .string("hello")]
                ),
            ]
        )

        XCTAssertEqual(
            try sortedJSONString(playback, dateEncodingStrategy: .iso8601),
            golden(
                #"{"app":"com.buttonheist.testapp","recorded":"1970-01-01T00:00:00Z","steps":["#,
                #"{"command":"activate","label":"Pay","traits":["button"]},"#,
                #"{"command":"type_text","label":"Note","text":"hello"}],"version":2}"#
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

    private func jsonString(_ response: FenceResponse, requestId: Any) throws -> String {
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

    private func sourceFile(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func sourceDirectory(_ relativePath: String) throws -> URL {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRoot.appendingPathComponent(relativePath)
    }

    private func lineCount(_ source: String) -> Int {
        source.split(separator: "\n", omittingEmptySubsequences: false).count
    }
}
