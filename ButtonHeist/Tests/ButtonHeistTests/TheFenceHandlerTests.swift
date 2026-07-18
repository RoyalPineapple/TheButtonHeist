import ButtonHeistTestSupport
import XCTest
import Network
import ButtonHeistSupport
@_spi(ButtonHeistTooling) @testable import ButtonHeist
@_spi(ButtonHeistInternals) import ThePlans
@_spi(ButtonHeistInternals) import TheScore

private func invocationPath(_ dottedName: String) -> HeistInvocationPath {
    do {
        return try HeistInvocationPath(validating: dottedName)
    } catch {
        preconditionFailure("invalid fence fixture path \(dottedName): \(error)")
    }
}

private func exactSemanticString(_ value: String) -> HeistSemanticStringMatch {
    HeistSemanticStringMatch(mode: .exact, value: .literal(value))
}

private func existsLabel(_ label: String) -> AccessibilityPredicate {
    .exists(.label(label))
}

private struct FailureClassificationExpectation {
    let kind: DiagnosticFailureKind
    let phase: FailurePhase
    let retryable: Bool
    let hint: String?

    init(
        _ kind: DiagnosticFailureKind,
        _ phase: FailurePhase,
        retryable: Bool,
        hint: String?
    ) {
        self.kind = kind
        self.phase = phase
        self.retryable = retryable
        self.hint = hint
    }
}

// MARK: - TheFence Handler Dispatch & Validation Tests
//
// These tests exercise the command dispatch router and the argument-validation
// paths inside TheFence+Handlers using mock DeviceConnecting/DeviceDiscovering
// implementations injected via TheHandoff closures (see Mocks.swift).

final class TheFenceHandlerTests: XCTestCase {

    // MARK: - Helpers

    private static let pureRuntimeHeistSource = """
    HeistPlan("agentFlow") {
        HeistDef<String>("Cart.addItem", parameter: "item") { item in
            Activate(.label(item))
        }

        Warn("start")
        Activate(.label("Pay"))

        ForEach("Milk", "Bread") { item in
            RunHeist("Cart.addItem", item)
        }
    }
    """

    private static let nativeSwiftRuntimeSource = """
    HeistPlan {
        let label = "Pay"
        Activate(.label(label))
    }
    """

    private static let knownFailureCodeClassificationExpectations: [KnownFailureCode: FailureClassificationExpectation] = [
        .requestInvalid: .init(.request, .request, retryable: false, hint: "Fix the request shape or arguments before retrying."),
        .requestMissingTarget: .init(.request, .request, retryable: false, hint: "get_interface()"),
        .requestAccessibilityTreeUnavailable: .init(
            .request,
            .request,
            retryable: true,
            hint: "Wait for a traversable app window, then refresh the interface or retry the command."
        ),
        .requestElementNotFound: .init(
            .request,
            .request,
            retryable: false,
            hint: "Refresh the interface and verify the target's accessibility properties."
        ),
        .requestTimeout: .init(.request, .request, retryable: true, hint: FenceError.actionTimeoutRecoveryHint),
        .requestValidationError: .init(
            .request,
            .request,
            retryable: false,
            hint: "Fix the request so it satisfies the server-side validation rules."
        ),
        .requestActionFailed: .init(.request, .request, retryable: false, hint: nil),
        .discoveryNoDeviceFound: .init(
            .discovery,
            .discovery,
            retryable: true,
            hint: "Start the app and confirm it advertises a session for The Button Heist."
        ),
        .discoveryNoMatchingDevice: .init(
            .discovery,
            .discovery,
            retryable: false,
            hint: "Check the device filter or target name against 'buttonheist list_devices'."
        ),
        .discoveryAmbiguousDeviceTarget: .init(
            .discovery,
            .discovery,
            retryable: false,
            hint: "Narrow the device target using a unique app name, device name, instance ID, installation ID, "
                + "simulator UDID, or direct host:port."
        ),
        .setupTimeout: .init(
            .connection,
            .setup,
            retryable: true,
            hint: "Is the app running? Check 'buttonheist list_devices' to see available devices."
        ),
        .connectionFailed: .init(
            .connection,
            .transport,
            retryable: true,
            hint: "Check that the app is running and reachable, then retry."
        ),
        .connectionNotConnected: .init(
            .connection,
            .request,
            retryable: true,
            hint: "Check that the app is running, then retry the command. Use 'buttonheist list_devices' to see available devices."
        ),
        .connectionEndpointUnreachable: .init(
            .connection,
            .transport,
            retryable: true,
            hint: "Check that the app is running at the configured endpoint, then retry the command."
        ),
        .transportNetworkError: .init(
            .connection,
            .transport,
            retryable: true,
            hint: "Check that the app is still running and reachable, then retry."
        ),
        .transportBufferOverflow: .init(
            .connection,
            .transport,
            retryable: false,
            hint: "Request a smaller payload or narrow the interface query before retrying."
        ),
        .transportEventBacklogOverflow: .init(
            .connection,
            .transport,
            retryable: true,
            hint: "Reconnect and retry after reducing event volume or response size."
        ),
        .transportServerClosed: .init(
            .connection,
            .transport,
            retryable: true,
            hint: "Check that the app is still running and reachable, then retry."
        ),
        .authFailed: .init(.authentication, .authentication, retryable: false, hint: nil),
        .sessionLocked: .init(
            .session,
            .session,
            retryable: true,
            hint: "Wait for the current driver to disconnect or for the session to time out. If this is your own stale session, "
                + "retry with the same BUTTONHEIST_DRIVER_ID or restart the app."
        ),
        .protocolMismatch: .init(
            .connection,
            .protocolNegotiation,
            retryable: false,
            hint: "Rebuild or reinstall so the CLI, MCP server, and iOS app use the same Button Heist version."
        ),
        .tlsMissingToken: .init(.connection, .tls, retryable: false, hint: "Set BUTTONHEIST_TOKEN, pass --token, or configure a target token."),
        .clientLocalDisconnect: .init(.client, .client, retryable: false, hint: nil),
        .clientUnknown: .init(.unknown, .client, retryable: false, hint: nil),
        .serverGeneral: .init(.server, .server, retryable: false, hint: nil),
        .configReadFailed: .init(
            .configuration,
            .setup,
            retryable: false,
            hint: "Verify the config path points to a readable JSON file matching the Button Heist config schema."
        ),
        .configDecodeFailed: .init(
            .configuration,
            .setup,
            retryable: false,
            hint: "Verify the config path points to a readable JSON file matching the Button Heist config schema."
        ),
        .formattingJSONEncodingFailed: .init(
            .client,
            .client,
            retryable: false,
            hint: "Report this diagnostic with the command that produced it."
        ),
        .screenInlinePayloadTooLarge: .init(
            .client,
            .client,
            retryable: false,
            hint: "Omit inlineData or pass output to receive a screenshot artifact path."
        ),
    ]

    private static var expectedDiagnosticFailures: [ExpectedDiagnosticFailure] {
        let validationError = SchemaValidationError(
            field: "target",
            observed: "string",
            expected: "object"
        )
        return [
            ExpectedDiagnosticFailure(
                name: "server",
                response: FenceResponse.failure(FenceError.serverError(ServerError(
                    kind: .general,
                    message: "server crashed"
                ))),
                code: .serverGeneral,
                kind: .server,
                phase: .server,
                message: "Action failed: server crashed",
                retryable: false
            ),
            ExpectedDiagnosticFailure(
                name: "routing",
                response: FenceResponse.failure(FenceOperationRoutingError(message: "Unknown tool: warp")),
                code: .requestInvalid,
                kind: .request,
                phase: .request,
                message: "Unknown tool: warp",
                retryable: false
            ),
            ExpectedDiagnosticFailure(
                name: "validation",
                response: FenceResponse.failure(validationError),
                code: .requestValidationError,
                kind: .request,
                phase: .request,
                message: validationError.message,
                retryable: false
            ),
            ExpectedDiagnosticFailure(
                name: "action",
                response: FenceResponse.failure(FenceError.actionFailed("could not activate target")),
                code: .requestActionFailed,
                kind: .request,
                phase: .request,
                message: "Action failed: could not activate target",
                retryable: false
            ),
            ExpectedDiagnosticFailure(
                name: "discovery",
                response: FenceResponse.failure(FenceError.noDeviceFound),
                code: .discoveryNoDeviceFound,
                kind: .discovery,
                phase: .discovery,
                message: "No devices found within timeout. Is the app running?",
                retryable: true
            ),
            ExpectedDiagnosticFailure(
                name: "transport",
                response: FenceResponse.failure(FenceError.connectionFailure(ConnectionFailure(
                    message: "network down",
                    failureCode: .transportNetworkError,
                    hint: "retry"
                ))),
                code: .transportNetworkError,
                kind: .connection,
                phase: .transport,
                message: "network down",
                retryable: true
            ),
            ExpectedDiagnosticFailure(
                name: "known-fence",
                response: FenceResponse.failure(FenceError.notConnected),
                code: .connectionNotConnected,
                kind: .connection,
                phase: .request,
                message: "Not connected to device.",
                retryable: true
            ),
            ExpectedDiagnosticFailure(
                name: "connection-domain",
                response: FenceResponse.failure(HandoffConnectionError.timeout),
                code: .setupTimeout,
                kind: .connection,
                phase: .setup,
                message: "Connection timed out",
                retryable: true
            ),
        ]
    }

    @ButtonHeistActor
    private func assertValidationFailure(
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        file: StaticString = #filePath,
        line: UInt = #line,
        verify: (DiagnosticFailure) -> Void
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(command: command, values: arguments)
            guard case .error(let failure) = response else {
                return XCTFail("Expected .error response, got: \(response)", file: file, line: line)
            }
            verify(failure)
        } catch {
            XCTFail("Unexpected throw: \(error)", file: file, line: line)
        }
    }

    @ButtonHeistActor
    private func assertValidationError(
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        contains substring: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        await assertValidationFailure(
            command: command,
            arguments: arguments,
            file: file,
            line: line
        ) { failure in
            XCTAssertTrue(
                failure.message.contains(substring),
                "Expected error containing '\(substring)', got: \(failure.message)",
                file: file,
                line: line
            )
        }
    }

    @ButtonHeistActor
    private func assertValidationError(
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        await assertValidationFailure(
            command: command,
            arguments: arguments,
            file: file,
            line: line
        ) { failure in
            XCTAssertEqual(failure.message, expected, file: file, line: line)
        }
    }

    @ButtonHeistActor
    private func assertDirectCommandHeistExecution(
        _ response: FenceResponse,
        command: TheFence.Command,
        stepKind: HeistExecutionStepKind,
        reportCommandName: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .heistExecution(_, let result, _) = response else {
            return XCTFail("Expected .heistExecution response, got \(response)", file: file, line: line)
        }
        XCTAssertEqual(result.steps.map(\.kind), [stepKind], file: file, line: line)
        if stepKind == .action {
            XCTAssertEqual(result.steps.first?.reportCommandName, reportCommandName ?? command.rawValue, file: file, line: line)
        }
    }

    /// Assert that executing a typed operation passes validation (returns a non-error response).
    @ButtonHeistActor
    private func assertPassesValidation(
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(command: command, values: arguments)
            if case .error(let failure) = response {
                XCTFail("Got validation error: \(failure.message)", file: file, line: line)
            }
        } catch {
            XCTFail("Unexpected throw: \(error)", file: file, line: line)
        }
    }

    @ButtonHeistActor
    private func decodedAccessibilityTarget(
        target: HeistValue? = nil
    ) throws -> AccessibilityTarget? {
        var arguments: [String: HeistValue] = [:]
        if let target {
            arguments["target"] = target
        }
        return try TheFence.CommandArgumentEnvelope(values: arguments).decodedAccessibilityTarget()
    }

    private func selectionTestInterface(includeDuplicateGroup: Bool = false) -> Interface {
        let header = makeTestHeistElement(label: "Menu", traits: [.header])
        let submit = makeTestHeistElement(label: "Submit", traits: [.button])
        let cancel = makeTestHeistElement(label: "Cancel", traits: [.button])
        let footer = makeTestHeistElement(label: "Footer", traits: [])
        var nodes: [TestInterfaceNode] = [
            .element(header),
            .container(
                makeTestSemanticContainer(
                    label: "Actions",
                    identifier: "actions",
                    frameX: 0,
                    frameY: 40,
                    frameWidth: 200,
                    frameHeight: 100
                ),
                containerName: "semantic_actions__actions",
                children: [.element(submit), .element(cancel)]
            ),
            .element(footer),
        ]
        if includeDuplicateGroup {
            let archive = makeTestHeistElement(label: "Archive", traits: [.button])
            nodes.insert(
                .container(
                    makeTestSemanticContainer(
                        label: "Actions",
                        identifier: "secondary_actions",
                        frameX: 0,
                        frameY: 160,
                        frameWidth: 200,
                        frameHeight: 60
                    ),
                    containerName: "semantic_actions__secondary_actions",
                    children: [.element(archive)]
                ),
                at: 2
            )
        }
        return makeTestInterface(nodes: nodes)
    }

    // MARK: - Public Failure Mapping

    func testDiagnosticFailureIsDiagnosticFailureBoundaryValue() {
        let details = FailureDetails(
            code: .requestValidationError,
            hint: "Fix the request."
        )

        let diagnostic = DiagnosticFailure(message: "Invalid request", details: details)
        let diagnosticFailure: DiagnosticFailure = diagnostic

        XCTAssertEqual(diagnosticFailure.failureCode, .requestValidationError)
        XCTAssertEqual(diagnosticFailure.code, "request.validation_error")
        XCTAssertEqual(diagnosticFailure.kind, .request)
        XCTAssertEqual(diagnosticFailure.message, "Invalid request")
        XCTAssertEqual(diagnosticFailure.displayMessage, "Invalid request")
        XCTAssertEqual(diagnosticFailure.details, details)
        XCTAssertEqual(diagnosticFailure.phase, .request)
        XCTAssertEqual(diagnosticFailure.retryable, false)
        XCTAssertEqual(diagnosticFailure.hint, "Fix the request.")
    }

    func testFenceErrorRendersTypedHintAtDisplayBoundary() throws {
        let error = FenceError.connectionTimeout
        let hint = try XCTUnwrap(error.failureDetails.hint)

        XCTAssertEqual(error.coreMessage, "Connection timed out")
        XCTAssertEqual(error.errorDescription, "Connection timed out\n  Hint: \(hint)")
    }

    func testErrorResponseCarriesTypedDiagnosticFailure() throws {
        let details = FailureDetails(
            code: .requestInvalid
        )
        let failure = DiagnosticFailure(message: "schema validation failed", details: details)

        let response = FenceResponse.error(failure)

        guard case .error(let encodedFailure) = response else {
            return XCTFail("Expected typed error response")
        }
        XCTAssertEqual(encodedFailure, failure)
        XCTAssertEqual(response.diagnosticFailure, failure)

        let data = try response.jsonData()
        let encoded = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(let responseObject) = encoded,
              let detailsValue = responseObject["details"],
              case .object(let detailsObject) = detailsValue else {
            return XCTFail("Expected canonical public failure object")
        }
        XCTAssertEqual(Set(responseObject.keys), ["status", "message", "code", "details"])
        XCTAssertEqual(Set(detailsObject.keys), ["kind", "phase", "retryable", "hint"])

        let json = try JSONProbe(data: data).object()
        XCTAssertEqual(failure.failureCode, .requestInvalid)
        XCTAssertEqual(failure.details.code, .requestInvalid)
        XCTAssertEqual(try json.string("status"), "error")
        XCTAssertEqual(try json.string("message"), failure.displayMessage)
        XCTAssertEqual(try json.string("code"), failure.code)
        try json.assertMissing("errorCode")
        try json.assertMissing("kind")
        try json.assertMissing("phase")
        try json.assertMissing("retryable")
        try json.assertMissing("hint")

        let detailsJSON = try json.object("details")
        try detailsJSON.assertMissing("code")
        try detailsJSON.assertMissing("errorCode")
        XCTAssertEqual(try detailsJSON.string("kind"), failure.kind.rawValue)
        XCTAssertEqual(try detailsJSON.string("phase"), failure.phase.rawValue)
        XCTAssertEqual(try detailsJSON.bool("retryable"), failure.retryable)
        XCTAssertEqual(try detailsJSON.string("hint"), failure.hint)
        try detailsJSON.assertMissing("buildDiagnostics")
    }

    func testHeistBuildDiagnosticsPreservedThroughFailurePipeline() throws {
        let diagnostics = [
            HeistBuildDiagnostic(
                code: .sourceInvalidSyntax,
                phase: .sourceCompilation,
                sourceSpan: HeistBuildSourceSpan(
                    sourceName: "inline.heist",
                    offset: 12,
                    line: 2,
                    column: 5,
                    length: 3
                ),
                message: "expected an identifier",
                hint: "Use valid ButtonHeist DSL."
            ),
            HeistBuildDiagnostic(
                code: .planRuntimeSafety,
                kind: .warning,
                phase: .planValidation,
                path: "flow.heist",
                message: "runtime safety warning"
            ),
        ]
        let response = FenceResponse.failure(FenceError.heistBuildDiagnostics(diagnostics))
        let failure = try XCTUnwrap(response.diagnosticFailure)
        let expectedFailureCode = KnownFailureCode.requestInvalid.rawValue

        XCTAssertEqual(failure.failureCode, .requestInvalid)
        XCTAssertEqual(failure.code, expectedFailureCode)
        XCTAssertEqual(failure.kind, .request)
        XCTAssertEqual(failure.phase, .request)
        XCTAssertFalse(failure.retryable)
        XCTAssertEqual(failure.hint, diagnostics[0].hint)
        XCTAssertEqual(failure.buildDiagnostics, diagnostics)
        XCTAssertTrue(failure.message.contains("expected an identifier"), failure.message)

        let json = try publicJSONProbe(response).object()
        XCTAssertEqual(try json.string("code"), expectedFailureCode)
        try json.assertMissing("errorCode")
        try json.assertMissing("kind")
        try json.assertMissing("phase")
        try json.assertMissing("retryable")
        try json.assertMissing("hint")

        let detailsJSON = try json.object("details")
        try detailsJSON.assertMissing("code")
        try detailsJSON.assertMissing("errorCode")
        XCTAssertEqual(try detailsJSON.string("kind"), DiagnosticFailureKind.request.rawValue)
        XCTAssertEqual(try detailsJSON.string("phase"), FailurePhase.request.rawValue)
        XCTAssertFalse(try detailsJSON.bool("retryable"))
        XCTAssertEqual(try detailsJSON.string("hint"), diagnostics[0].hint)

        let buildDiagnostics = try detailsJSON.array("buildDiagnostics")
        XCTAssertEqual(buildDiagnostics.count, 2)

        let first = try buildDiagnostics[0].object()
        XCTAssertEqual(try first.string("code"), diagnostics[0].code.rawValue)
        XCTAssertEqual(try first.string("kind"), HeistBuildDiagnosticKind.error.rawValue)
        XCTAssertEqual(try first.string("phase"), HeistBuildPhase.sourceCompilation.rawValue)
        XCTAssertEqual(try first.string("message"), diagnostics[0].message)
        XCTAssertEqual(try first.string("hint"), diagnostics[0].hint)
        try first.assertMissing("path")
        let sourceSpan = try first.object("sourceSpan")
        XCTAssertEqual(try sourceSpan.string("sourceName"), "inline.heist")
        XCTAssertEqual(try sourceSpan.int("offset"), 12)
        XCTAssertEqual(try sourceSpan.int("line"), 2)
        XCTAssertEqual(try sourceSpan.int("column"), 5)
        XCTAssertEqual(try sourceSpan.int("length"), 3)

        let second = try buildDiagnostics[1].object()
        XCTAssertEqual(try second.string("code"), diagnostics[1].code.rawValue)
        XCTAssertEqual(try second.string("kind"), HeistBuildDiagnosticKind.warning.rawValue)
        XCTAssertEqual(try second.string("phase"), HeistBuildPhase.planValidation.rawValue)
        XCTAssertEqual(try second.string("message"), diagnostics[1].message)
        XCTAssertEqual(try second.string("path"), "flow.heist")
        try second.assertMissing("hint")
        try second.assertMissing("sourceSpan")
    }

    func testKnownFailureCodesExposeTypedClassification() throws {
        let expected = Self.knownFailureCodeClassificationExpectations

        XCTAssertEqual(Set(expected.keys), Set(KnownFailureCode.allCases))

        for knownCode in KnownFailureCode.allCases {
            let expectation = try XCTUnwrap(expected[knownCode])
            let code = knownCode
            let details = FailureDetails(code: knownCode)

            XCTAssertEqual(code.rawValue, knownCode.rawValue)
            XCTAssertEqual(code, knownCode)
            XCTAssertEqual(code.kind, expectation.kind)
            XCTAssertEqual(code.phase, expectation.phase)
            XCTAssertEqual(code.retryable, expectation.retryable)
            XCTAssertEqual(code.defaultHint, expectation.hint)
            XCTAssertEqual(details.code, code)
            XCTAssertEqual(details.code.rawValue, knownCode.rawValue)
            XCTAssertEqual(details.phase, expectation.phase)
            XCTAssertEqual(details.retryable, expectation.retryable)
            XCTAssertEqual(details.hint, expectation.hint)
        }
    }

    func testUnknownFailureCodeDecodeFailsAtBoundary() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(
            KnownFailureCode.self,
            from: Data(#""plugin.custom_failure""#.utf8)
        )) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("plugin.custom_failure"))
        }
    }

    func testKnownFailuresExposeCompleteDiagnosticFields() throws {
        for expected in Self.expectedDiagnosticFailures {
            let failure = try XCTUnwrap(expected.response.diagnosticFailure, expected.name)
            let json = try publicJSONProbe(expected.response).object()
            let detailsJSON = try json.object("details")

            XCTAssertEqual(failure.failureCode, expected.code, expected.name)
            XCTAssertEqual(failure.failureCode.rawValue, expected.code.rawValue, expected.name)
            XCTAssertEqual(failure.code, expected.code.rawValue, expected.name)
            XCTAssertEqual(failure.kind, expected.kind, expected.name)
            XCTAssertEqual(failure.phase, expected.phase, expected.name)
            XCTAssertEqual(failure.message, expected.message, expected.name)
            XCTAssertEqual(failure.displayMessage, expected.message, expected.name)
            XCTAssertEqual(failure.retryable, expected.retryable, expected.name)
            XCTAssertEqual(failure.details.code, expected.code, expected.name)
            XCTAssertEqual(failure.details.phase, expected.phase, expected.name)
            XCTAssertEqual(failure.details.retryable, expected.retryable, expected.name)
            XCTAssertFalse(failure.code.isEmpty, expected.name)
            XCTAssertFalse(failure.kind.rawValue.isEmpty, expected.name)
            XCTAssertFalse(failure.message.isEmpty, expected.name)
            XCTAssertEqual(try json.string("status"), "error", expected.name)
            XCTAssertEqual(try json.string("message"), expected.message, expected.name)
            XCTAssertEqual(try json.string("code"), expected.code.rawValue, expected.name)
            XCTAssertNoThrow(try json.assertMissing("errorCode"), expected.name)
            XCTAssertNoThrow(try json.assertMissing("kind"), expected.name)
            XCTAssertNoThrow(try json.assertMissing("phase"), expected.name)
            XCTAssertNoThrow(try json.assertMissing("retryable"), expected.name)
            XCTAssertNoThrow(try json.assertMissing("hint"), expected.name)
            XCTAssertNoThrow(try detailsJSON.assertMissing("code"), expected.name)
            XCTAssertNoThrow(try detailsJSON.assertMissing("errorCode"), expected.name)
            XCTAssertEqual(try detailsJSON.string("kind"), expected.kind.rawValue, expected.name)
            XCTAssertEqual(try detailsJSON.string("phase"), expected.phase.rawValue, expected.name)
            XCTAssertEqual(try detailsJSON.bool("retryable"), expected.retryable, expected.name)
        }
    }

    func testAmbiguousDeviceTargetKeepsDistinctFailureProjection() throws {
        let response = FenceResponse.failure(HandoffConnectionError.ambiguousDeviceTarget(
            filter: "Demo",
            matches: ["Demo#one", "Demo#two"]
        ))
        let failure = try XCTUnwrap(response.diagnosticFailure)

        XCTAssertEqual(failure.failureCode, .discoveryAmbiguousDeviceTarget)
        XCTAssertNotEqual(failure.failureCode, .discoveryNoMatchingDevice)
        XCTAssertEqual(failure.code, KnownFailureCode.discoveryAmbiguousDeviceTarget.rawValue)
        XCTAssertEqual(failure.kind, .discovery)
        XCTAssertEqual(failure.phase, .discovery)
        XCTAssertFalse(failure.retryable)
        XCTAssertEqual(failure.hint, KnownFailureCode.discoveryAmbiguousDeviceTarget.defaultHint)
        XCTAssertEqual(failure.message, "Ambiguous device target 'Demo' (matches: Demo#one, Demo#two)")

        let json = try publicJSONProbe(response).object()
        XCTAssertEqual(try json.string("status"), "error")
        XCTAssertEqual(try json.string("code"), KnownFailureCode.discoveryAmbiguousDeviceTarget.rawValue)
        let detailsJSON = try json.object("details")
        XCTAssertEqual(try detailsJSON.string("kind"), DiagnosticFailureKind.discovery.rawValue)
        XCTAssertEqual(try detailsJSON.string("phase"), FailurePhase.discovery.rawValue)
    }

    func testTransportDisconnectFailureUsesNetworkDiagnosticShape() throws {
        let transportFailure = NetworkTransportFailure(.posix(.ECONNRESET))
        let response = FenceResponse.failure(HandoffConnectionError.disconnected(.networkError(transportFailure)))
        let failure = try XCTUnwrap(response.diagnosticFailure)

        XCTAssertEqual(failure.failureCode, .transportNetworkError)
        XCTAssertEqual(failure.code, KnownFailureCode.transportNetworkError.rawValue)
        XCTAssertEqual(failure.kind, .connection)
        XCTAssertEqual(failure.phase, .transport)
        XCTAssertTrue(failure.retryable)
        XCTAssertEqual(failure.hint, KnownFailureCode.transportNetworkError.defaultHint)
        XCTAssertTrue(failure.message.contains("posix"), failure.message)
        XCTAssertTrue(failure.message.contains("connection failed in transport"), failure.message)
    }
    func testAuthFailureMappingPreservesSourceHint() throws {
        let hint = "Retry with the configured token."
        let response = FenceResponse.failure(HandoffConnectionError.disconnected(
            .authFailed("Invalid token", hint: hint)
        ))
        let failure = try XCTUnwrap(response.diagnosticFailure)

        XCTAssertEqual(failure.failureCode, .authFailed)
        XCTAssertEqual(failure.code, KnownFailureCode.authFailed.rawValue)
        XCTAssertEqual(failure.kind, .authentication)
        XCTAssertEqual(failure.phase, .authentication)
        XCTAssertEqual(failure.retryable, false)
        XCTAssertEqual(failure.hint, hint)
        XCTAssertEqual(failure.details.hint, hint)

        let json = try publicJSONProbe(response).object()
        XCTAssertEqual(try json.string("code"), KnownFailureCode.authFailed.rawValue)
        try json.assertMissing("kind")
        try json.assertMissing("phase")
        try json.assertMissing("hint")

        let detailsJSON = try json.object("details")
        try detailsJSON.assertMissing("code")
        try detailsJSON.assertMissing("errorCode")
        XCTAssertEqual(try detailsJSON.string("kind"), DiagnosticFailureKind.authentication.rawValue)
        XCTAssertEqual(try detailsJSON.string("phase"), FailurePhase.authentication.rawValue)
        XCTAssertEqual(try detailsJSON.string("hint"), hint)
    }

    func testAuthFailureMappingPreservesReason() throws {
        let reason = "Invalid token"
        let response = FenceResponse.failure(HandoffConnectionError.disconnected(
            .authFailed(reason, hint: "Retry with the configured token.")
        ))
        let failure = try XCTUnwrap(response.diagnosticFailure)

        XCTAssertEqual(failure.failureCode, .authFailed)
        XCTAssertTrue(failure.message.contains(reason), failure.message)
        XCTAssertEqual(failure.hint, "Retry with the configured token.")

        let json = try publicJSONProbe(response).object()
        XCTAssertEqual(try json.string("code"), KnownFailureCode.authFailed.rawValue)
        XCTAssertEqual(
            try json.object("details").string("kind"),
            DiagnosticFailureKind.authentication.rawValue
        )
        XCTAssertTrue(try json.string("message").contains(reason))
    }

    @ButtonHeistActor
    func testTransportSendFailureUsesNetworkDiagnosticShape() async throws {
        let (fence, mockConn) = makeConnectedFence(configuration: .init(autoReconnect: false))
        mockConn.sendOutcome = .failed(.transportFailed(NetworkTransportFailure(.posix(.ECONNRESET))))

        let response: FenceResponse
        do {
            response = try await fence.execute(command: .getInterface)
        } catch {
            response = FenceResponse.failure(error)
        }
        let failure = try XCTUnwrap(response.diagnosticFailure)

        XCTAssertEqual(failure.failureCode, .transportNetworkError)
        XCTAssertNotEqual(failure.failureCode, .requestActionFailed)
        XCTAssertEqual(failure.code, KnownFailureCode.transportNetworkError.rawValue)
        XCTAssertEqual(failure.kind, .connection)
        XCTAssertEqual(failure.phase, .transport)
        XCTAssertEqual(failure.retryable, true)
        XCTAssertEqual(failure.hint, KnownFailureCode.transportNetworkError.defaultHint)
        XCTAssertTrue(failure.message.contains("posix"), failure.message)
        XCTAssertFalse(failure.message.contains(KnownFailureCode.requestActionFailed.rawValue), failure.message)

        let json = try publicJSONProbe(response).object()
        XCTAssertEqual(try json.string("status"), "error")
        XCTAssertEqual(try json.string("code"), KnownFailureCode.transportNetworkError.rawValue)
        try json.assertMissing("errorCode")
        try json.assertMissing("kind")
        try json.assertMissing("phase")
        try json.assertMissing("retryable")
        try json.assertMissing("hint")

        let detailsJSON = try json.object("details")
        try detailsJSON.assertMissing("code")
        try detailsJSON.assertMissing("errorCode")
        XCTAssertEqual(try detailsJSON.string("kind"), DiagnosticFailureKind.connection.rawValue)
        XCTAssertEqual(try detailsJSON.string("phase"), FailurePhase.transport.rawValue)
        XCTAssertTrue(try detailsJSON.bool("retryable"))
        XCTAssertEqual(try detailsJSON.string("hint"), KnownFailureCode.transportNetworkError.defaultHint)
    }

    @ButtonHeistActor
    func testDirectActionExpectIsRejectedBeforeDispatch() async throws {
        await assertValidationError(
            command: .scroll,
            arguments: [
                "expect": .object([
                    "type": .string("changed"),
                    "scope": .string("screen"),
                    "assertions": .array([]),
                ]),
            ],
            equals: "command \"scroll\" direct dispatch does not support expect"
        )
    }

    func testSchemaFailureUsesDiagnosticFailureMapper() throws {
        let validationError = SchemaValidationError(
            field: "target",
            observed: "integer 7",
            expected: "object"
        )
        let response = FenceResponse.failure(validationError)
        let failure = try XCTUnwrap(response.diagnosticFailure)

        XCTAssertEqual(failure.failureCode, .requestValidationError)
        XCTAssertEqual(failure.code, KnownFailureCode.requestValidationError.rawValue)
        XCTAssertEqual(failure.kind, .request)
        XCTAssertEqual(failure.message, validationError.message)
        XCTAssertEqual(failure.details.phase, .request)
        XCTAssertEqual(failure.details.retryable, false)
        XCTAssertEqual(failure.details.hint, "Fix the request so it satisfies the server-side validation rules.")
    }

    // MARK: - Connect

    @ButtonHeistActor
    func testConnectReturnsSessionStateWithoutInterfaceObservation() async throws {
        let mockConn = MockConnection()
        mockConn.serverInfo = TheFenceFixtures.testServerInfo

        let mockDiscovery = MockDiscovery()
        mockDiscovery.discoveredDevices = [TheFenceFixtures.testDevice]

        let fence = TheFence(configuration: .init(
            deviceFilter: "MockApp",
            autoReconnect: false
        ))
        fence.handoff.makeDiscovery = { mockDiscovery }
        fence.handoff.makeConnection = { _ in mockConn }

        let previousReachability = makeReachabilityConnection
        makeReachabilityConnection = { _ in
            let probe = MockConnection()
            probe.emitTransportReadyOnConnect = true
            probe.responseScript = { message in
                if case .status = message {
                    return .status(StatusPayload(
                        identity: StatusIdentity(
                            appName: "Mock", bundleIdentifier: "com.test",
                            appBuild: "1", deviceName: "Mock",
                            systemVersion: "18.0", buttonHeistVersion: "0.0.1"
                        ),
                        session: StatusSession(active: false, watchersAllowed: false, activeConnections: 0)
                    ))
                }
                return .actionResult(ActionResult.success(method: .activate))
            }
            return probe
        }
        defer { makeReachabilityConnection = previousReachability }

        XCTAssertFalse(fence.handoff.connectionLifecycle.isConnected)
        XCTAssertFalse(mockConn.isConnected)
        let response = try await fence.execute(command: .connect)

        guard case .sessionState(let payload) = response else {
            return XCTFail("Expected sessionState response, got \(response)")
        }
        XCTAssertEqual(payload.connected, true)
        XCTAssertEqual(mockConn.connectCount, 1)

        for (message, _) in mockConn.sent {
            switch message {
            case .requestInterface:
                XCTFail("connect must not send UI observation message \(message)")
            default:
                break
            }
        }
    }

    // MARK: - Run Heist Input Loading

    @ButtonHeistActor
    func testValidateHeistAdmitsCanonicalPlanWithoutConnection() async throws {
        let fence = TheFence(configuration: .init())

        let response = try await fence.execute(command: .validateHeist, values: [
            "plan": .string("HeistPlan { Warn(\"Check\") }"),
        ])

        guard case .heistValidation(let report) = response else {
            return XCTFail("Expected heistValidation response, got \(response)")
        }
        XCTAssertTrue(report.admissible)
        XCTAssertTrue(report.commandPassed)
        XCTAssertEqual(report.invocation.state, .valid)
        XCTAssertEqual(report.lint.mode, .compositionQuality)
        XCTAssertNotNil(report.canonicalPlan)
        XCTAssertFalse(fence.handoff.connectionLifecycle.isConnected)
    }

    @ButtonHeistActor
    func testValidateHeistReturnsInvalidPlanAsNormalValidationResponse() async throws {
        let fence = TheFence(configuration: .init())

        let response = try await fence.execute(command: .validateHeist, values: [
            "plan": .string("HeistPlan { Activate( }"),
        ])

        guard case .heistValidation(let report) = response else {
            return XCTFail("Expected heistValidation response, got \(response)")
        }
        XCTAssertFalse(response.isFailure)
        XCTAssertFalse(report.admissible)
        XCTAssertFalse(report.commandPassed)
        XCTAssertFalse(report.plan.diagnostics.isEmpty)
        XCTAssertEqual(report.invocation.state, .notEvaluated)
        XCTAssertEqual(report.lint.state, .notEvaluated)
        XCTAssertNil(report.canonicalPlan)
    }

    @ButtonHeistActor
    func testValidateHeistReportsMissingParameterizedRootArgument() async throws {
        let fence = TheFence(configuration: .init())
        let response = try await fence.execute(command: .validateHeist, values: [
            "plan": .string("HeistPlan(\"search\", parameter: \"query\") { query in Warn(\"Check\") }"),
        ])

        guard case .heistValidation(let report) = response else {
            return XCTFail("Expected heistValidation response, got \(response)")
        }
        XCTAssertTrue(report.plan.isValid)
        XCTAssertEqual(report.invocation.state, .invalid)
        XCTAssertFalse(report.invocation.argumentProvided)
        XCTAssertFalse(report.invocation.diagnostics.isEmpty)
        XCTAssertFalse(report.admissible)
    }

    @ButtonHeistActor
    func testValidateHeistStrictLintCanFailOtherwiseAdmissiblePlan() async throws {
        let fence = TheFence(configuration: .init())
        let response = try await fence.execute(command: .validateHeist, values: [
            "plan": .string("HeistPlan { Activate(.label(\"Save\")) }"),
            "lint": .string("strict_test"),
        ])

        guard case .heistValidation(let report) = response else {
            return XCTFail("Expected heistValidation response, got \(response)")
        }
        XCTAssertTrue(report.admissible)
        XCTAssertFalse(report.commandPassed)
        XCTAssertEqual(report.lint.state, .findings)
        XCTAssertTrue(report.lint.hasErrors)
        XCTAssertEqual(report.lint.findings.map(\.message), ["Semantic action has no expectation"])
    }

    @ButtonHeistActor
    func testRunHeistReadsPlanFromArtifactPathIntoSwiftObjects() async throws {
        let fence = TheFence(configuration: .init())
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fence-runheist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        // A hyphenated file name is NOT a valid Swift-style identifier. The fence
        // must run the plan exactly as authored — stamping the file name into the
        // plan's `name` would fail runtime safety and silently reduce the run
        // to zero steps (the run_heist replay no-op regression).
        let heistURL = temp.appendingPathComponent("bh-demo-smoke.heist")
        let plan = try HeistPlan(name: "demoSmoke", body: [.warn(WarnStep(message: "from artifact"))])
        try HeistArtifactCodec.writePlan(plan, to: heistURL)

        let request = try fence.decodeRunHeistRequest(
            TheFence.CommandArgumentEnvelope(values: ["path": .string(heistURL.path)])
        )

        // The fence reads the file into a HeistPlan directly — no parameter
        // round-trip — and does not invent a name from the file.
        XCTAssertEqual(request.plan.body, plan.body)
        XCTAssertEqual(request.plan.name, "demoSmoke")
    }

    @ButtonHeistActor
    func testRunHeistRejectsPathCombinedWithAnyInlinePlanField() async {
        let fence = TheFence(configuration: .init())
        // Every canonical inline plan field combined with `path` must fail,
        // before the artifact is touched. Values are irrelevant — key presence
        // alone is the conflict.
        let inlineFields: [String: HeistValue] = [
            "version": .int(1),
            "name": .string("flow"),
            "parameter": .object(["type": .string("none")]),
            "definitions": .array([]),
            "body": .array([.object(["type": .string("warn")])]),
        ]
        for (field, value) in inlineFields {
            XCTAssertThrowsError(try fence.decodeRunHeistRequest(
                TheFence.CommandArgumentEnvelope(values: [
                    "path": .string("/tmp/Flow.heist"),
                    field: value,
                ])
            ), "path + \(field) must fail") { error in
                XCTAssertTrue(
                    String(describing: error).contains("raw JSON HeistPlan IR field"),
                    "path + \(field): \(error)"
                )
            }
        }
    }

    @ButtonHeistActor
    func testRunHeistRejectsPlanSourceCombinedWithPathOrStructuredPlanFields() async throws {
        let fence = TheFence(configuration: .init())
        XCTAssertThrowsError(try fence.decodeRunHeistRequest(
            TheFence.CommandArgumentEnvelope(values: [
                "path": .string("/tmp/Flow.heist"),
                "plan": .string("HeistPlan { Activate(.label(\"Pay\")) }"),
            ])
        )) { error in
            XCTAssertTrue(String(describing: error).contains("run_heist accepts exactly one plan source"), "\(error)")
        }

        var arguments = try Self.inlineArguments(for: try HeistPlan(body: [.warn(WarnStep(message: "x"))])).values
        arguments["plan"] = .string("HeistPlan { Activate(.label(\"Pay\")) }")
        XCTAssertThrowsError(try fence.decodeRunHeistRequest(
            TheFence.CommandArgumentEnvelope(values: arguments)
        )) { error in
            XCTAssertTrue(String(describing: error).contains("raw JSON HeistPlan IR field"), "\(error)")
        }
    }

    @ButtonHeistActor
    func testRunHeistDecodesHeistPlanSourceThroughThePlans() async throws {
        let fence = TheFence(configuration: .init())
        let request = try fence.decodeRunHeistRequest(
            TheFence.CommandArgumentEnvelope(values: [
                "plan": .string("""
                HeistPlan {
                    Activate(.label("Pay")).expect(.changed(.screen()))
                }
                """),
            ])
        )

        XCTAssertEqual(request.plan.body, [
            .action(ActionStep(
                command: .activate(.predicate(.label("Pay"))),
                expectationPolicy: .expect(ActionExpectation(predicate: .changed(.screen()), timeout: 1)))),
        ])
    }

    @ButtonHeistActor
    func testPerformExecutesOnePrimitiveStepThroughValidatedPlan() async throws {
        let (fence, mockConn) = makeConnectedFence()
        fence.handoff.connect(to: TheFenceFixtures.testDevice)

        let response = try await fence.execute(command: .perform, values: [
            "step": .string(#"Activate(.label("Pay"))"#),
        ])

        guard case .heistExecution(let plan, let result, _) = response else {
            return XCTFail("Expected heistExecution response, got \(response)")
        }
        XCTAssertEqual(plan.body, [
            .action(ActionStep(command: .activate(.predicate(.label("Pay"))))),
        ])
        XCTAssertEqual(mockConn.sent.sentHeistPlan, plan)
        XCTAssertEqual(result.steps.map(\.kind), [.action])
        XCTAssertFalse(result.isFailure)

        let json = try publicJSONProbe(response).object()
        try json.assertMissing("method")
        let firstNode = try XCTUnwrap(try json.object("report").array("nodes").first)
        XCTAssertEqual(try firstNode.string("kind"), "action")
        try firstNode.assertMissing("action")
        try firstNode.object("evidence").assertPresent("action")
    }

    @ButtonHeistActor
    func testPerformDecodesSimpleWaitStepThroughThePlans() async throws {
        let fence = TheFence(configuration: .init())

        let request = try fence.decodePerformRequest(TheFence.CommandArgumentEnvelope(values: [
            "step": .string(#"WaitFor(.exists(.label("Pay")), timeout: 5)"#),
        ]))

        XCTAssertEqual(request.plan.body, [
            .wait(WaitStep(predicate: .exists(.label("Pay")), timeout: 5)),
        ])
        XCTAssertEqual(request.step, .wait(WaitStep(predicate: .exists(.label("Pay")), timeout: 5)))
    }

    @ButtonHeistActor
    func testPerformRejectsWaitForElseBranch() async {
        let fence = TheFence(configuration: .init())

        XCTAssertThrowsError(try fence.decodePerformRequest(TheFence.CommandArgumentEnvelope(values: [
            "step": .string("""
            WaitFor(.exists(.label("Receipt")), timeout: 5).else {
                Warn("fallback")
            }
            """),
        ]))) { error in
            let message = String(describing: error)
            XCTAssertTrue(
                message.contains("perform accepts one action statement or one simple WaitFor statement"),
                message
            )
        }
    }

    @ButtonHeistActor
    func testPerformUnsupportedStepDiagnosticBranchUsesCodeNotMessage() async {
        let fence = TheFence(configuration: .init())
        let guidance = "perform accepts one action statement or one simple WaitFor statement"

        let codeSelectedError = fence.performStepSourceLoadError(for: [
            HeistBuildDiagnostic(
                code: .sourceWaitForGate,
                phase: .sourceCompilation,
                message: "compiler wording can change"
            ),
        ])
        let codeSelectedMessage = String(describing: codeSelectedError)
        XCTAssertTrue(codeSelectedMessage.contains(guidance), codeSelectedMessage)
        XCTAssertFalse(codeSelectedMessage.contains("compiler wording can change"), codeSelectedMessage)

        let messageOnlyError = fence.performStepSourceLoadError(for: [
            HeistBuildDiagnostic(
                code: .sourceInvalidSyntax,
                phase: .sourceCompilation,
                message: "WaitFor is a gate"
            ),
        ])
        let messageOnlyMessage = String(describing: messageOnlyError)
        XCTAssertTrue(messageOnlyMessage.contains("WaitFor is a gate"), messageOnlyMessage)
        XCTAssertFalse(messageOnlyMessage.contains(guidance), messageOnlyMessage)
    }

    @ButtonHeistActor
    func testPerformRejectsProgramShapedSource() async throws {
        let fence = TheFence(configuration: .init())
        let invalidSteps = [
            """
            Activate(.label("Pay"))
            Activate(.label("Confirm"))
            """,
            """
            HeistDef<Void>("helper") {
                Activate(.label("Pay"))
            }
            Activate(.label("Pay"))
            """,
            """
            If(.exists(.label("Pay"))) {
                Activate(.label("Pay"))
            }
            """,
            """
            WaitFor(.exists(.label("Receipt")), timeout: 5) {
                Activate(.label("Done"))
            }
            """,
            """
            ForEach("Milk") { item in
                TypeText(item)
            }
            """,
            #"Warn("ready")"#,
            #"Fail("stop")"#,
        ]

        for step in invalidSteps {
            XCTAssertThrowsError(try fence.decodePerformRequest(TheFence.CommandArgumentEnvelope(values: [
                "step": .string(step),
            ])), step) { error in
                let message = String(describing: error)
                XCTAssertTrue(
                    message.contains("perform accepts one action statement or one simple WaitFor statement")
                        || message.contains("expected an identifier"),
                    message
                )
            }
        }
    }

    @ButtonHeistActor
    func testPerformRejectsNativeSwiftAtRuntimeBoundary() async {
        await assertValidationError(
            command: .perform,
            arguments: [
                "step": .string("""
                let label = "Pay"
                Activate(.label(label))
                """),
            ],
            contains: "let declarations are not supported inside ButtonHeist DSL bodies"
        )
    }

    @ButtonHeistActor
    func testRunHeistSendsValidatedPlanAndProjectsServerReceipt() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let scriptedResult = HeistReceiptFixture.result(steps: [
            HeistReceiptFixture.warning(message: "server receipt"),
        ])
        mockConn.responseScript = { _ in scriptedHeistResponse(scriptedResult) }
        fence.handoff.connect(to: TheFenceFixtures.testDevice)

        let response = try await fence.execute(command: .runHeist, values: [
            "plan": .string(Self.pureRuntimeHeistSource),
        ])

        guard case .heistExecution(let plan, let result, _) = response else {
            return XCTFail("Expected heistExecution response, got \(response)")
        }
        XCTAssertEqual(plan.name, "agentFlow")
        XCTAssertEqual(mockConn.sent.sentHeistPlan, plan)
        XCTAssertEqual(mockConn.sent.sentHeistRun?.argument, HeistArgument.none)
        XCTAssertEqual(result.steps, scriptedResult.steps)
    }

    @ButtonHeistActor
    func testRunHeistRecordsReceiptArtifactWhenEnvironmentConfigured() async throws {
        try await withReceiptDirectory { directory in
            let previousDirectory = EnvironmentKey.buttonheistReceiptsDir.value
            let previousMode = EnvironmentKey.buttonheistReceiptsMode.value
            setEnvironment(EnvironmentKey.buttonheistReceiptsDir.rawValue, directory.path)
            setEnvironment(EnvironmentKey.buttonheistReceiptsMode.rawValue, HeistReceiptRecordingMode.failingAndPassing.rawValue)
            defer {
                setEnvironment(EnvironmentKey.buttonheistReceiptsDir.rawValue, previousDirectory)
                setEnvironment(EnvironmentKey.buttonheistReceiptsMode.rawValue, previousMode)
            }

            let (fence, mockConn) = makeConnectedFence()
            let scriptedResult = HeistReceiptFixture.result(steps: [
                HeistReceiptFixture.warning(message: "recorded receipt"),
            ])
            mockConn.responseScript = { _ in scriptedHeistResponse(scriptedResult) }
            fence.handoff.connect(to: TheFenceFixtures.testDevice)

            let response = try await fence.execute(command: .runHeist, values: [
                "plan": .string(Self.pureRuntimeHeistSource),
            ])

            guard case .heistExecution(_, let result, _) = response else {
                return XCTFail("Expected heistExecution response, got \(response)")
            }
            XCTAssertEqual(result.steps, scriptedResult.steps)
            let receiptURL = try assertSingleReceiptArtifactURL(in: directory)
            XCTAssertEqual(try HeistReceiptCodec.decode(contentsOf: receiptURL), result)
        }
    }

    @ButtonHeistActor
    func testRunHeistRejectsNonHeistAndEmptyInput() async {
        let fence = TheFence(configuration: .init())
        // Standalone .json is internal to the package, and plan source is an
        // inline field rather than a local file path accepted by the fence.
        for path in ["Flow.txt", "Flow.json", "Flow.plan"] {
            XCTAssertThrowsError(try fence.decodeRunHeistRequest(
                TheFence.CommandArgumentEnvelope(values: ["path": .string(path)])
            )) { error in
                XCTAssertTrue(String(describing: error).contains("generated `.heist` package artifact"), "\(path): \(error)")
            }
        }
        // Empty path fails.
        XCTAssertThrowsError(try fence.decodeRunHeistRequest(
            TheFence.CommandArgumentEnvelope(values: ["path": .string("   ")])
        )) { error in
            XCTAssertTrue(String(describing: error).contains("path must not be empty"), "\(error)")
        }
    }

    private func setEnvironment(_ key: String, _ value: String?) {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
    }

    @ButtonHeistActor
    func testRunHeistDecodesComposableInlinePlan() async throws {
        let fence = TheFence(configuration: .init())
        let item: HeistReferenceName = "item"
        // Nested definitions + invoke + a string parameter all round-trip.
        let definition = try HeistPlan(
            name: "addToCart",
            parameter: .string(name: "item"),
            body: [.action(ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: .exact(item))))))]
        )
        let plan = try HeistPlan(definitions: [definition], body: [
            .invoke(HeistInvocationStep(path: "addToCart", argument: .string("Milk"))),
        ])

        let request = try fence.decodeRunHeistRequest(try Self.planSourceArguments(for: plan))
        XCTAssertEqual(request.plan, plan)
    }

    @ButtonHeistActor
    func testRunHeistDecodesInlinePlanWithAccessibilityTargetParameter() async throws {
        let fence = TheFence(configuration: .init())
        let definition = try HeistPlan(
            name: "tapEach",
            parameter: .accessibilityTarget(name: "input"),
            body: [.action(ActionStep(command: .activate(.ref("input"))))]
        )
        let plan = try HeistPlan(
            definitions: [definition],
            body: [.warn(WarnStep(message: "namespace"))]
        )

        let request = try fence.decodeRunHeistRequest(try Self.planSourceArguments(for: plan))
        XCTAssertEqual(request.plan, plan)
    }

    @ButtonHeistActor
    func testRunHeistDecodesParameterizedRootWithStringArgument() async throws {
        let fence = TheFence(configuration: .init())
        let plan = try HeistPlan(
            name: "search",
            parameter: .string(name: "query"),
            body: [.action(ActionStep(command: .typeText(
                reference: "query",
                target: .predicate(.label("Search"))
            )))]
        )
        var arguments = try Self.planSourceArguments(for: plan).values
        arguments["argument"] = .object([
            "type": .string("string"),
            "value": .string("milk"),
        ])

        let request = try fence.decodeRunHeistRequest(TheFence.CommandArgumentEnvelope(values: arguments))

        XCTAssertEqual(request.plan, plan)
        XCTAssertEqual(request.argument, .string("milk"))
    }

    @ButtonHeistActor
    func testRunHeistRejectsMultipleStringRootArgumentValues() async throws {
        let fence = TheFence(configuration: .init())
        let plan = try HeistPlan(
            name: "search",
            parameter: .string(name: "query"),
            body: [.action(ActionStep(command: .typeText(
                reference: "query",
                target: .predicate(.label("Search"))
            )))]
        )
        var arguments = try Self.planSourceArguments(for: plan).values
        arguments["argument"] = .object([
            "type": .string("string"),
            "values": .array([.string("milk"), .string("eggs")]),
        ])

        XCTAssertThrowsError(try fence.decodeRunHeistRequest(TheFence.CommandArgumentEnvelope(values: arguments))) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("Unknown heist argument field"), message)
            XCTAssertTrue(message.contains("values"), message)
        }
    }

    @ButtonHeistActor
    func testRunHeistDecodesParameterizedRootWithAccessibilityTargetArgument() async throws {
        let fence = TheFence(configuration: .init())
        let plan = try HeistPlan(
            name: "tapRow",
            parameter: .accessibilityTarget(name: "row"),
            body: [.action(ActionStep(command: .activate(.ref("row"))))]
        )
        var arguments = try Self.planSourceArguments(for: plan).values
        arguments["argument"] = .object([
            "type": .string("accessibility_target"),
            "target": targetValue(label: "Row 1"),
        ])

        let request = try fence.decodeRunHeistRequest(TheFence.CommandArgumentEnvelope(values: arguments))

        XCTAssertEqual(request.plan, plan)
        XCTAssertEqual(request.argument, .accessibilityTarget(.predicate(.label("Row 1"))))
    }

    @ButtonHeistActor
    func testRunHeistRejectsMissingRootArgumentForParameterizedRoot() async throws {
        let fence = TheFence(configuration: .init())
        let plan = try HeistPlan(
            name: "search",
            parameter: .string(name: "query"),
            body: [.action(ActionStep(command: .typeText(
                reference: "query",
                target: .predicate(.label("Search"))
            )))]
        )

        XCTAssertThrowsError(try fence.decodeRunHeistRequest(try Self.planSourceArguments(for: plan))) { error in
            XCTAssertTrue(String(describing: error).contains("run_heist argument does not match root heist parameter"))
        }
    }

    @ButtonHeistActor
    func testRunHeistRejectsRawJSONIRFieldsInsteadOfDecodingThem() async throws {
        let fence = TheFence(configuration: .init())
        XCTAssertThrowsError(try fence.decodeRunHeistRequest(
            TheFence.CommandArgumentEnvelope(values: [
                "version": .int(999),
                "body": .array([.object(["type": .string("warn"), "warn": .object(["message": .string("x")])])]),
            ])
        )) { error in
            XCTAssertTrue(String(describing: error).contains("raw JSON HeistPlan IR field"), "\(error)")
            XCTAssertTrue(String(describing: error).contains("ButtonHeist DSL"), "\(error)")
            XCTAssertTrue(String(describing: error).contains(".heist"), "\(error)")
        }
        XCTAssertThrowsError(try fence.decodeRunHeistRequest(
            TheFence.CommandArgumentEnvelope(values: ["version": .int(1), "body": .array([])])
        )) { error in
            XCTAssertTrue(String(describing: error).contains("raw JSON HeistPlan IR field"), "\(error)")
        }
    }

    @ButtonHeistActor
    func testRunHeistDescriptorRejectsRawJSONIRFieldsAndAcceptsCanonicalSource() async throws {
        // The descriptor must declare canonical ButtonHeist source but not raw
        // JSON IR fields. Structured JSON remains an internal codec, not the
        // public authoring surface.
        let fence = TheFence(configuration: .init())
        let definition = try HeistPlan(
            name: "addToCart",
            parameter: .string(name: "item"),
            body: [.warn(WarnStep(message: "x"))]
        )
        let plan = try HeistPlan(
            name: "flow",
            definitions: [definition],
            body: [.invoke(HeistInvocationStep(path: "addToCart", argument: .string("Milk")))]
        )
        XCTAssertThrowsError(try fence.parseRequest(command: .runHeist, arguments: try Self.inlineArguments(for: plan)))
        XCTAssertNoThrow(try fence.parseRequest(
            command: .runHeist,
            arguments: try Self.planSourceArguments(for: plan)
        ))
    }

    @ButtonHeistActor
    func testListHeistsReturnsCatalogFromValidatedInlinePlan() async throws {
        let fence = TheFence(configuration: .init())
        let item: HeistReferenceName = "item"
        let definition = try HeistPlan(
            name: "addToCart",
            parameter: .string(name: "item"),
            body: [.action(ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: .exact(item))))))]
        )
        let plan = try HeistPlan(
            name: "shop",
            definitions: [definition],
            body: [.warn(WarnStep(message: "ready"))]
        )

        let response = try await fence.execute(command: .listHeists, arguments: try Self.planSourceArguments(for: plan))

        guard case .heistCatalog(let catalog) = response else {
            return XCTFail("Expected heistCatalog response, got \(response)")
        }
        XCTAssertEqual(catalog.heists.map(\.identity.displayName), ["shop", "addToCart"])
        XCTAssertEqual(catalog.heists[1].parameterKind, .string)
        XCTAssertTrue(catalog.heists[1].requiresArgument)
        XCTAssertEqual(catalog.heists[1].summary, "Reusable heist capability requiring string argument")
        XCTAssertEqual(catalog.heists[1].tags, [.capability, .parameterized, .semanticAction])
        XCTAssertNil(catalog.heists[1].parameterName)
        XCTAssertNil(catalog.heists[1].actionCommands)
        XCTAssertNil(catalog.heists[1].nestedRunHeists)
        XCTAssertNil(catalog.heists[1].waitCount)
        XCTAssertNil(catalog.heists[1].expectationCount)
        XCTAssertNil(catalog.heists[1].semanticSurfaces)
        XCTAssertNil(catalog.heists[1].validationStatus)
    }

    @ButtonHeistActor
    func testListHeistsAcceptsCanonicalSourcePlan() async throws {
        let fence = TheFence(configuration: .init())
        let response = try await fence.execute(
            command: .listHeists,
            arguments: TheFence.CommandArgumentEnvelope(values: [
                "plan": .string("""
                HeistPlan("shop") {
                    HeistDef<String>("addToCart", parameter: "item") { item in
                        Activate(.label(item))
                    }

                    Warn("ready")
                }
                """),
            ])
        )

        guard case .heistCatalog(let catalog) = response else {
            return XCTFail("Expected heistCatalog response, got \(response)")
        }
        XCTAssertEqual(catalog.heists.map(\.identity.displayName), ["shop", "addToCart"])
        XCTAssertEqual(catalog.heists[1].parameterKind, .string)
        XCTAssertTrue(catalog.heists[1].requiresArgument)
    }

    @ButtonHeistActor
    func testDiscoveryCommandsUseSamePureRuntimeSourceAsRunHeist() async throws {
        let fence = TheFence(configuration: .init())
        let item: HeistReferenceName = "item"
        let sourceArguments = TheFence.CommandArgumentEnvelope(values: [
            "plan": .string(Self.pureRuntimeHeistSource),
            "detail": .string("detailed"),
        ])

        let listResponse = try await fence.execute(command: .listHeists, arguments: sourceArguments)
        guard case .heistCatalog(let catalog) = listResponse else {
            return XCTFail("Expected heistCatalog response, got \(listResponse)")
        }
        XCTAssertEqual(catalog.heists.map(\.identity.displayName), ["agentFlow", "Cart", "Cart.addItem"])
        let addItem = try XCTUnwrap(catalog.heists.first { $0.identity.displayName == "Cart.addItem" })
        XCTAssertEqual(addItem.parameterKind, .string)
        XCTAssertEqual(addItem.actionCommands, [.activate])
        XCTAssertEqual(addItem.validationStatus, .validated)

        let describeResponse = try await fence.execute(
            command: .describeHeist,
            arguments: TheFence.CommandArgumentEnvelope(values: [
                "plan": .string(Self.pureRuntimeHeistSource),
                "heist": .string("Cart.addItem"),
            ])
        )
        guard case .heistDescription(let description) = describeResponse else {
            return XCTFail("Expected heistDescription response, got \(describeResponse)")
        }
        XCTAssertEqual(description.identity.displayName, "Cart.addItem")
        XCTAssertEqual(description.parameterKind, .string)
        XCTAssertEqual(description.semanticSurface.actionCommands, [.activate])
        XCTAssertEqual(description.semanticSurface.targetPredicates, [.predicate(.label(item))])
    }

    @ButtonHeistActor
    func testRuntimeSourceRejectsNativeSwiftAtFenceBoundary() async {
        await assertValidationError(
            command: .runHeist,
            arguments: ["plan": .string(Self.nativeSwiftRuntimeSource)],
            contains: "let declarations are not supported inside ButtonHeist DSL bodies"
        )
        await assertValidationError(
            command: .listHeists,
            arguments: ["plan": .string(Self.nativeSwiftRuntimeSource)],
            contains: "let declarations are not supported inside ButtonHeist DSL bodies"
        )
        await assertValidationError(
            command: .describeHeist,
            arguments: [
                "heist": .string("agentFlow"),
                "plan": .string(Self.nativeSwiftRuntimeSource),
            ],
            contains: "let declarations are not supported inside ButtonHeist DSL bodies"
        )
    }

    @ButtonHeistActor
    func testListHeistsDetailedModeReturnsDerivedSafeFields() async throws {
        let fence = TheFence(configuration: .init())
        let definition = try HeistPlan(
            name: "checkout",
            definitions: [
                try HeistPlan(
                    name: "confirm",
                    body: [
                        .action(ActionStep(command: .activate(.predicate(.identifier("confirm_button"))))),
                    ]
                ),
            ],
            body: [
                .action(ActionStep(
                    command: .activate(.predicate(.label("Checkout"))),
                    expectationPolicy: .expect(ActionExpectation(predicate: .exists(.label("Done")), timeout: 1)))),
                .wait(WaitStep(predicate: .exists(.label("Receipt")), timeout: 1)),
                .invoke(HeistInvocationStep(path: "confirm")),
            ]
        )
        let plan = try HeistPlan(
            name: "shop",
            definitions: [definition],
            body: [.warn(WarnStep(message: "ready"))]
        )
        var arguments = try Self.planSourceArguments(for: plan).values
        arguments["detail"] = .string("detailed")

        let response = try await fence.execute(
            command: .listHeists,
            arguments: TheFence.CommandArgumentEnvelope(values: arguments)
        )

        guard case .heistCatalog(let catalog) = response else {
            return XCTFail("Expected heistCatalog response, got \(response)")
        }
        let checkout = try XCTUnwrap(catalog.heists.first { $0.identity.displayName == "checkout" })
        XCTAssertEqual(checkout.nestedRunHeists, [invocationPath("checkout.confirm")])
        XCTAssertEqual(checkout.actionCommands, [.activate])
        XCTAssertEqual(checkout.waitCount, 1)
        XCTAssertEqual(checkout.expectationCount, 1)
        XCTAssertEqual(checkout.semanticSurfaces, [
            .label(exactSemanticString("Checkout")),
            .label(exactSemanticString("Done")),
            .label(exactSemanticString("Receipt")),
            .identifier(exactSemanticString("confirm_button")),
        ])
        XCTAssertEqual(checkout.validationStatus, .validated)
    }

    @ButtonHeistActor
    func testListHeistsReturnsValidationFailureDiagnostics() async throws {
        let fence = TheFence(configuration: .init())

        let response = try await fence.execute(
            command: .listHeists,
            arguments: TheFence.CommandArgumentEnvelope(values: [
                "plan": .string("""
                HeistPlan("root") {
                    HeistDef<Void>("duplicate") {
                        Warn("one")
                    }

                    HeistDef<Void>("duplicate") {
                        Warn("two")
                    }

                    Warn("invalid")
                }
                """),
            ])
        )

        guard case .error(let failure) = response else {
            return XCTFail("Expected error response, got \(response)")
        }
        let message = failure.message
        XCTAssertTrue(message.contains("duplicate heist definition names"), message)
    }

    @ButtonHeistActor
    func testListHeistsRejectsUnknownDetailMode() async throws {
        let fence = TheFence(configuration: .init())
        let plan = try HeistPlan(
            name: "shop",
            body: [.warn(WarnStep(message: "ready"))]
        )
        var arguments = try Self.planSourceArguments(for: plan).values
        arguments["detail"] = .string("full")

        let response = try await fence.execute(
            command: .listHeists,
            arguments: TheFence.CommandArgumentEnvelope(values: arguments)
        )

        guard case .error(let failure) = response else {
            return XCTFail("Expected error response, got \(response)")
        }
        let message = failure.message
        XCTAssertTrue(message.contains("detail"), message)
        XCTAssertTrue(message.contains("summary"), message)
        XCTAssertTrue(message.contains("detailed"), message)
    }

    @ButtonHeistActor
    func testDescribeHeistReturnsSemanticSurfaceFromValidatedPlan() async throws {
        let fence = TheFence(configuration: .init())
        let definition = try HeistPlan(
            name: "checkout",
            body: [
                .action(ActionStep(
                    command: .activate(.predicate(.label("Checkout"))),
                    expectationPolicy: .expect(ActionExpectation(predicate: .exists(.label("Done")), timeout: 1)))),
            ]
        )
        let plan = try HeistPlan(
            name: "shop",
            definitions: [definition],
            body: [.warn(WarnStep(message: "ready"))]
        )
        var arguments = try Self.planSourceArguments(for: plan).values
        arguments["heist"] = .string("checkout")

        let response = try await fence.execute(
            command: .describeHeist,
            arguments: TheFence.CommandArgumentEnvelope(values: arguments)
        )

        guard case .heistDescription(let description) = response else {
            return XCTFail("Expected heistDescription response, got \(response)")
        }
        XCTAssertEqual(description.identity.displayName, "checkout")
        XCTAssertEqual(description.role, .capability)
        XCTAssertEqual(description.semanticSurface.actionCommands, [.activate])
        XCTAssertEqual(description.semanticSurface.expectations, [existsLabel("Done")])
        XCTAssertEqual(description.semanticSurface.targetPredicates, [
            .predicate(.label("Checkout")),
            .predicate(.label("Done")),
        ])
    }

    @ButtonHeistActor
    func testDescribeHeistAcceptsCanonicalSourcePlan() async throws {
        let fence = TheFence(configuration: .init())
        let response = try await fence.execute(
            command: .describeHeist,
            arguments: TheFence.CommandArgumentEnvelope(values: [
                "heist": .string("checkout"),
                "plan": .string("""
                HeistPlan("shop") {
                    HeistDef<Void>("checkout") {
                        Activate(.label("Checkout"))
                            .expect(.exists(.label("Done")), timeout: 1)
                    }

                    Warn("ready")
                }
                """),
            ])
        )

        guard case .heistDescription(let description) = response else {
            return XCTFail("Expected heistDescription response, got \(response)")
        }
        XCTAssertEqual(description.identity.displayName, "checkout")
        XCTAssertEqual(description.semanticSurface.actionCommands, [.activate])
        XCTAssertEqual(description.semanticSurface.targetPredicates, [
            .predicate(.label("Checkout")),
            .predicate(.label("Done")),
        ])
    }

    @ButtonHeistActor
    func testDescribeHeistMissingNameDiagnosticIncludesAvailableNames() async throws {
        let fence = TheFence(configuration: .init())
        let plan = try HeistPlan(
            name: "shop",
            definitions: [
                try HeistPlan(name: "openCart", body: [.warn(WarnStep(message: "open"))]),
            ],
            body: [.warn(WarnStep(message: "ready"))]
        )
        var arguments = try Self.planSourceArguments(for: plan).values
        arguments["heist"] = .string("checkout")

        let response = try await fence.execute(
            command: .describeHeist,
            arguments: TheFence.CommandArgumentEnvelope(values: arguments)
        )

        guard case .error(let failure) = response else {
            return XCTFail("Expected error response, got \(response)")
        }
        let message = failure.message
        XCTAssertTrue(message.contains(#"heist "checkout" was not found"#), message)
        XCTAssertTrue(message.contains("shop, openCart"), message)
    }

    func testHeistExecutionResponseFailureDerivesFromTypedReceipt() throws {
        let result = HeistReceiptFixture.result(
            steps: [HeistReceiptFixture.explicitFailure(message: "boom", durationMs: 5)],
            durationMs: 5
        )
        let response = FenceResponse.heistExecution(
            plan: try HeistPlan(body: [.warn(WarnStep(message: "x"))]),
            result: result,
            accessibilityTrace: nil
        )
        XCTAssertTrue(response.isFailure)
        XCTAssertEqual(result.abortedAtPath, "$.body[0]")
    }

    /// Build a lower-level run_heist argument envelope from the canonical JSON
    /// object fields. This is intentionally not the public MCP authoring shape.
    private static func inlineArguments(for plan: HeistPlan) throws -> TheFence.CommandArgumentEnvelope {
        let data = try JSONEncoder().encode(plan)
        let value = try JSONDecoder().decode(HeistValue.self, from: data)
        let fields: [String: HeistValue] = try XCTUnwrap(
            { () -> [String: HeistValue]? in
                guard case .object(let fields) = value else { return nil }
                return fields
            }(),
            "Expected the plan to encode as a JSON object"
        )
        return TheFence.CommandArgumentEnvelope(values: fields)
    }

    private static func planSourceArguments(for plan: HeistPlan) throws -> TheFence.CommandArgumentEnvelope {
        TheFence.CommandArgumentEnvelope(values: [
            "plan": .string(try plan.canonicalSwiftDSL()),
        ])
    }

    private static func inlineArguments(for plan: HeistPlanAdmissionCandidate) throws -> TheFence.CommandArgumentEnvelope {
        let data = try JSONEncoder().encode(plan)
        let value = try JSONDecoder().decode(HeistValue.self, from: data)
        let fields: [String: HeistValue] = try XCTUnwrap(
            { () -> [String: HeistValue]? in
                guard case .object(let fields) = value else { return nil }
                return fields
            }(),
            "Expected the plan admission candidate to encode as a JSON object"
        )
        return TheFence.CommandArgumentEnvelope(values: fields)
    }

    @ButtonHeistActor
    func testAccessibilityTargetPayloadShapesDecodeCanonically() async throws {
        let publicExpected = AccessibilityTarget.predicate(
            ElementPredicateTemplate(label: "Save", identifier: "saveButton", traits: [.button]),
            ordinal: 1
        )
        let jsonMCPShape = accessibilityTargetValue([
            "checks": .array([
                predicateCheckValue(kind: "label", match: stringMatchValue(mode: "exact", value: "Save")),
                predicateCheckValue(kind: "identifier", match: stringMatchValue(mode: "exact", value: "saveButton")),
                predicateCheckValue(kind: "traits", values: [.string("button")]),
            ]),
            "ordinal": .int(1),
        ])
        let containerShape = accessibilityTargetValue([
            "container": .object([
                "checks": .array([.object([
                    "kind": .string("scrollable"),
                    "value": .bool(true),
                ])]),
            ]),
        ])
        let cases: [(String, HeistValue?, AccessibilityTarget?)] = [
            (
                "identifier",
                targetValue(identifier: "myButton"),
                .predicate(ElementPredicateTemplate(identifier: "myButton"))
            ),
            (
                "matcher fields",
                targetValue(label: "Save", traits: ["button"]),
                .predicate(ElementPredicateTemplate(label: "Save", traits: [.button]))
            ),
            (
                "CLI public shape",
                targetValue(label: "Save", identifier: "saveButton", traits: ["button"], ordinal: 1),
                publicExpected
            ),
            ("JSON/MCP public shape", jsonMCPShape, publicExpected),
            (
                "ordinal",
                targetValue(label: "Save", ordinal: 2),
                .predicate(ElementPredicateTemplate(label: "Save"), ordinal: 2)
            ),
            (
                "no ordinal",
                targetValue(label: "Save"),
                .predicate(ElementPredicateTemplate(label: "Save"))
            ),
            ("missing", nil, nil),
            ("container", containerShape, .container(.matching(.scrollable(true)))),
        ]

        for (name, value, expected) in cases {
            XCTAssertEqual(try decodedAccessibilityTarget(target: value), expected, name)
        }
    }

    @ButtonHeistActor
    func testAccessibilityTargetRejectsHeistIdField() async throws {
        // heistId is no longer a targeting field — it is rejected as unknown.
        XCTAssertThrowsError(try decodedAccessibilityTarget(target: legacyHeistIdTargetValue("button_save")))
    }

    @ButtonHeistActor
    func testAccessibilityTargetRejectsRemovedContainerPredicateShapes() async {
        let exactOrders = stringMatchValue(mode: "exact", value: "orders")
        let removedShapes = [
            accessibilityTargetValue([
                "container": .object(["identifier": .string("orders")]),
            ]),
            accessibilityTargetValue([
                "container": .object([
                    "checks": .array([
                        .object([
                            "kind": .string("identifier"),
                            "match": exactOrders,
                            "semantic": .object([
                                "kind": .string("label"),
                                "match": exactOrders,
                            ]),
                        ]),
                    ]),
                ]),
            ]),
        ]

        for target in removedShapes {
            XCTAssertThrowsError(try decodedAccessibilityTarget(target: target))
        }
    }

    @ButtonHeistActor
    func testAccessibilityTargetRejectsUnknownTargetField() async throws {
        XCTAssertThrowsError(
            try decodedAccessibilityTarget(
                target: accessibilityTargetValue([
                    "checks": .array([
                        predicateCheckValue(kind: "label", match: stringMatchValue(mode: "exact", value: "Save")),
                    ]),
                    "unexpectedTargetField": .string("button_save"),
                ])
            )
        ) { error in
            XCTAssertTrue(
                "\(error)".contains("unexpectedTargetField"),
                "Expected unknown target field rejection, got \(error)"
            )
        }
    }

    @ButtonHeistActor
    func testRequestTargetRejectsNegativeOrdinal() async {
        await assertValidationError(
            command: .activate,
            arguments: ["target": targetValue(label: "Save", ordinal: -1)],
            equals: "schema validation failed for target.ordinal: observed integer -1; expected ordinal must be non-negative, got -1"
        )
    }

    @ButtonHeistActor
    func testElementOnlyCommandRejectsContainerTargetWithTypedError() async {
        let arguments = TheFence.CommandArgumentEnvelope(values: [
            "target": .object([
                "container": .object([
                    "checks": .array([.object([
                        "kind": .string("scrollable"),
                        "value": .bool(true),
                    ])]),
                ]),
            ]),
        ])

        XCTAssertThrowsError(try arguments.requiredAccessibilityTarget(command: .activate)) { error in
            XCTAssertEqual(error as? TheFence.ContainerTargetRequiresElement, .init(command: .activate))
        }
    }

    @ButtonHeistActor
    func testDirectCommandResolvesTargetRefsAtRuntimeBoundary() async {
        let arguments = TheFence.CommandArgumentEnvelope(values: [
            "target": .object(["ref": .string("item")]),
        ])

        XCTAssertThrowsError(try arguments.requiredAccessibilityTarget(command: .activate)) { error in
            XCTAssertEqual(error as? HeistExpressionError, .unresolvedTargetReference("item"))
        }
    }

    // MARK: - Schema Validation Diagnostics

    @ButtonHeistActor
    func testSchemaValidationReportsBadCoercedValue() async {
        await assertValidationError(
            command: .wait,
            arguments: [
                "predicate": .object([
                    "type": .string("changed"),
                    "scope": .string("elements"),
                    "assertions": .array([]),
                ]),
                "timeout": .string("forever"),
            ],
            equals: "schema validation failed for timeout: observed string \"forever\"; expected number"
        )
    }

    // MARK: - Gesture Validation

    @ButtonHeistActor
    func testTapAndLongPressValidPayloadsPassValidation() async {
        let cases: [(TheFence.Command, [String: HeistValue])] = [
            (.oneFingerTap, ["point": .object(["x": .double(100), "y": .double(200)])]),
            (.oneFingerTap, ["element": targetValue(identifier: "myButton")]),
            (.longPress, ["point": .object(["x": .double(50), "y": .double(50)])]),
        ]

        for (command, arguments) in cases {
            await assertPassesValidation(command: command, arguments: arguments)
        }
    }

    @ButtonHeistActor
    func testTapAndLongPressMissingTargetsAreRejected() async {
        for command in [TheFence.Command.oneFingerTap, .longPress] {
            await assertValidationError(
                command: command,
                contains: "point requires element, element with unitPoint, or ScreenPoint"
            )
        }
    }

    @ButtonHeistActor
    func testTapAndLongPressInvalidPayloadsAreRejected() async {
        let cases: [(TheFence.Command, [String: HeistValue], String)] = [
            (
                .oneFingerTap,
                ["point": .object(["x": .double(100)])],
                "schema validation failed for point.y: observed missing; expected number"
            ),
            (
                .oneFingerTap,
                [
                    "element": targetValue(identifier: "myButton"),
                    "unitPoint": .object(["x": .double(1.2), "y": .double(0.5)]),
                ],
                "schema validation failed for unitPoint.x: observed number 1.2; expected number in 0...1"
            ),
            (
                .oneFingerTap,
                ["point": .object(["x": .double(Double.nan), "y": .double(200)])],
                "schema validation failed for point.x: observed number nan; expected number"
            ),
            (
                .oneFingerTap,
                ["point": .object(["x": .double(Double.infinity), "y": .double(200)])],
                "schema validation failed for point.x: observed number inf; expected number"
            ),
            (
                .longPress,
                [
                    "point": .object(["x": .double(50), "y": .double(50)]),
                    "duration": .double(-1),
                ],
                "schema validation failed for duration: observed number -1.0; expected number > 0"
            ),
            (
                .longPress,
                [
                    "point": .object(["x": .double(50), "y": .double(50)]),
                    "duration": .double(61),
                ],
                "schema validation failed for duration: observed number 61.0; expected number in 0...60.0"
            ),
        ]

        for (command, arguments, message) in cases {
            await assertValidationError(command: command, arguments: arguments, equals: message)
        }
    }

    @ButtonHeistActor
    func testDirectTapReturnsHeistExecutionBeforeFormatting() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let point = ScreenPoint(x: 12, y: 34)
        let scriptedResult = HeistReceiptFixture.result(steps: [
            HeistReceiptFixture.action(
                command: .mechanicalTap(TapTarget(selection: .coordinate(point))),
                result: HeistReceiptFixture.actionResult(method: .syntheticTap)
            ),
        ])
        mockConn.responseScript = { _ in scriptedHeistResponse(scriptedResult) }

        let response = try await fence.execute(command: .oneFingerTap, values: [
            "point": .object(["x": .double(12), "y": .double(34)]),
        ])

        assertDirectCommandHeistExecution(
            response,
            command: .oneFingerTap,
            stepKind: .action,
            reportCommandName: "oneFingerTap"
        )
        assertCompactHeistSummary(response, stepLine: "  [0] oneFingerTap")
    }

    @ButtonHeistActor
    func testGestureTargetRejectsHeistId() async {
        await assertValidationError(
            command: .oneFingerTap,
            arguments: [
                "element": accessibilityTargetValue([
                    "heistId": .string("button_save"),
                ]),
            ],
            contains: "Unknown accessibility target field \"heistId\""
        )
    }

    @ButtonHeistActor
    func testSwipeAndDragValidPayloadsPassValidation() async {
        let cases: [(TheFence.Command, [String: HeistValue])] = [
            (
                .swipe,
                ["elementUnitPoints": .object([
                    "element": targetValue(identifier: "row_5"),
                    "start": .object(["x": .double(0.8), "y": .double(0.5)]),
                    "end": .object(["x": .double(0.2), "y": .double(0.5)]),
                ])]
            ),
            (
                .drag,
                ["elementToPoint": .object([
                    "element": targetValue(identifier: "source"),
                    "end": .object(["x": .double(100), "y": .double(200)]),
                ])]
            ),
        ]

        for (command, arguments) in cases {
            await assertPassesValidation(command: command, arguments: arguments)
        }
    }

    @ButtonHeistActor
    func testSwipeAndDragInvalidPayloadsAreRejected() async {
        let point = HeistValue.object(["x": .double(10), "y": .double(20)])
        let dragStart = HeistValue.object(["x": .double(10), "y": .double(10)])
        let end = HeistValue.object(["x": .double(100), "y": .double(200)])
        let swipeEnd = HeistValue.object(["x": .double(30), "y": .double(40)])
        let cases: [(TheFence.Command, [String: HeistValue], String)] = [
            (
                .swipe,
                ["pointDirection": .object(["start": point, "direction": .string("diagonal")])],
                "schema validation failed for pointDirection.direction: observed string \"diagonal\"; " +
                    "expected enum one of up, down, left, right"
            ),
            (
                .swipe,
                ["pointDirection": .object(["direction": .string("up")])],
                "schema validation failed for pointDirection.start: observed missing; expected object"
            ),
            (
                .swipe,
                ["pointToPoint": .object([
                    "start": .object(["x": .double(10)]),
                    "end": end,
                ])],
                "schema validation failed for pointToPoint.start.y: observed missing; expected number"
            ),
            (
                .swipe,
                ["elementUnitPoints": .object([
                    "element": targetValue(identifier: "row_5"),
                    "start": .object(["x": .double(1.2), "y": .double(0.5)]),
                    "end": .object(["x": .double(0.2), "y": .double(0.5)]),
                ])],
                "schema validation failed for elementUnitPoints.start.x: observed number 1.2; expected number in 0...1"
            ),
            (
                .swipe,
                [
                    "pointDirection": .object(["start": point, "direction": .string("down")]),
                    "pointToPoint": .object(["start": point, "end": swipeEnd]),
                ],
                "swipe accepts exactly one gesture intent"
            ),
            (
                .drag,
                ["pointToPoint": .object(["start": dragStart])],
                "schema validation failed for pointToPoint.end: observed missing; expected object"
            ),
            (
                .drag,
                ["pointToPoint": .object(["end": end])],
                "schema validation failed for pointToPoint.start: observed missing; expected object"
            ),
            (
                .drag,
                [
                    "elementToPoint": .object([
                        "element": targetValue(identifier: "source"),
                        "end": end,
                    ]),
                    "pointToPoint": .object(["start": point, "end": end]),
                ],
                "drag accepts exactly one gesture intent"
            ),
        ]

        for (command, arguments, message) in cases {
            await assertValidationError(command: command, arguments: arguments, equals: message)
        }
    }

    @ButtonHeistActor
    func testSwipeDirectionWithElementDispatchesElementDirectionPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(command: .swipe, values: [
            "elementDirection": .object([
                "element": targetValue(identifier: "row_5"),
                "direction": .string("left"),
            ]),
        ])
        guard let message = mockConn.sent.sentPlanMessages.last,
              case .mechanicalSwipe(let target) = message,
              case .elementDirection(let target, let direction) = target.selection else {
            XCTFail("Expected element direction swipe to lower to element direction swipe")
            return
        }
        XCTAssertEqual(target, .predicate(.identifier("row_5")))
        XCTAssertEqual(direction, .left)
    }

    @ButtonHeistActor
    func testDragWithStartCoordinatesDispatchesCanonicalPayload() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(command: .drag, values: [
                "pointToPoint": .object([
                    "start": .object(["x": .double(100.0), "y": .double(300.0)]),
                    "end": .object(["x": .double(300.0), "y": .double(600.0)]),
                ]),
            ])
        guard let message = mockConn.sent.sentPlanMessages.last,
              case .mechanicalDrag(let target) = message,
              case .pointToPoint(let start, let end) = target.selection else {
            XCTFail("Expected drag message")
            return
        }
        XCTAssertEqual(start, ScreenPoint(x: 100.0, y: 300.0))
        XCTAssertEqual(end, ScreenPoint(x: 300.0, y: 600.0))
    }

    @ButtonHeistActor
    func testPublicMutatingCommandsUseDurableOrTransientDeviceWire() async throws {
        let target = targetValue(identifier: "target")
        let durableCases: [(command: TheFence.Command, arguments: [String: HeistValue])] = [
            (.activate, ["target": target]),
            (.activate, ["target": target, "action": .string("increment")]),
            (.activate, ["target": target, "action": .string("decrement")]),
            (.activate, ["target": target, "action": .string("Archive")]),
            (.rotor, ["target": target, "rotor": .string("Errors")]),
            (.oneFingerTap, ["point": .object(["x": .double(12), "y": .double(34)])]),
            (.longPress, ["point": .object(["x": .double(12), "y": .double(34)])]),
            (.swipe, [
                "elementDirection": .object([
                    "element": target,
                    "direction": .string(SwipeDirection.left.rawValue),
                ]),
            ]),
            (.drag, [
                "elementToPoint": .object([
                    "element": target,
                    "end": .object(["x": .double(120), "y": .double(240)]),
                ]),
            ]),
            (.typeText, ["text": .string("hello"), "target": target]),
            (.editAction, ["action": .string(EditAction.paste.rawValue)]),
            (.setPasteboard, ["text": .string("clipboard")]),
            (.dismissKeyboard, [:]),
            (.wait, [
                "predicate": .object([
                    "type": .string("changed"),
                    "scope": .string("elements"),
                    "assertions": .array([]),
                ]),
                "timeout": .double(1),
            ]),
        ]
        let transientCases: [(command: TheFence.Command, arguments: [String: HeistValue])] = [
            (.scroll, ["direction": .string(ScrollDirection.down.rawValue)]),
            (.scrollToVisible, ["target": target]),
            (.scrollToEdge, ["edge": .string(ScrollEdge.bottom.rawValue)]),
        ]

        for testCase in durableCases {
            let (fence, mockConn) = makeConnectedFence()

            _ = try await fence.execute(command: testCase.command, values: testCase.arguments)

            XCTAssertEqual(mockConn.sent.count, 1, testCase.command.rawValue)
            guard case .heistPlan(let run) = mockConn.sent.first?.0 else {
                return XCTFail("Expected \(testCase.command.rawValue) to send heistPlan, got \(String(describing: mockConn.sent.first?.0))")
            }
            XCTAssertEqual(run.plan.body.count, 1, testCase.command.rawValue)
        }

        for testCase in transientCases {
            let (fence, mockConn) = makeConnectedFence()

            _ = try await fence.execute(command: testCase.command, values: testCase.arguments)

            XCTAssertEqual(mockConn.sent.count, 1, testCase.command.rawValue)
            guard case .runtimeAction(let command) = mockConn.sent.first?.0 else {
                return XCTFail(
                    "Expected \(testCase.command.rawValue) to send runtimeAction, got \(String(describing: mockConn.sent.first?.0))"
                )
            }
            XCTAssertNotNil(command.durableHeistActionFailure, testCase.command.rawValue)
        }
    }

    // MARK: - Scroll Action Validation

    @ButtonHeistActor
    func testScrollPayloadsPassValidation() async {
        let target = targetValue(identifier: "scrollView")
        let cases: [(TheFence.Command, [String: HeistValue])] = [
            (.scroll, ["target": target]),
            (.scroll, ["direction": .string("down")]),
            (.scroll, ["direction": .string("down"), "target": target]),
            (.scroll, ["direction": .string("down"), "containerName": .string("main_scroll")]),
            (.scroll, [:]),
            (.scrollToVisible, ["target": targetValue(identifier: "targetElement")]),
            (.scrollToEdge, ["edge": .string("bottom"), "containerName": .string("main_scroll")]),
            (.scrollToEdge, ["target": target]),
            (.scrollToEdge, ["edge": .string("bottom")]),
            (.scrollToEdge, ["edge": .string("bottom"), "target": target]),
        ]

        for (command, arguments) in cases {
            await assertPassesValidation(command: command, arguments: arguments)
        }
    }

    @ButtonHeistActor
    func testInvalidScrollEnumsAreRejected() async {
        let cases: [(TheFence.Command, [String: HeistValue], String)] = [
            (
                .scroll,
                ["target": targetValue(identifier: "scrollView"), "direction": .string("diagonal")],
                "schema validation failed for direction: observed string \"diagonal\"; expected enum one of up, down, left, right"
            ),
            (
                .scrollToEdge,
                ["target": targetValue(identifier: "scrollView"), "edge": .string("middle")],
                "schema validation failed for edge: observed string \"middle\"; expected enum one of top, bottom, left, right"
            ),
        ]

        for (command, arguments, message) in cases {
            await assertValidationError(command: command, arguments: arguments, equals: message)
        }
    }

    @ButtonHeistActor
    func testLegacyScrollContainerPayloadsAreRejected() async {
        let cases: [(TheFence.Command, [String: HeistValue])] = [
            (.scroll, ["container": .object(["unexpected": .string("main_scroll")])]),
            (.scroll, ["container": .string("main_scroll")]),
            (.scrollToEdge, ["edge": .string("bottom"), "container": .string("main_scroll")]),
        ]

        for (command, arguments) in cases {
            await assertValidationError(
                command: command,
                arguments: arguments,
                contains: "schema validation failed for container"
            )
        }
    }

    @ButtonHeistActor
    func testElementCommandsReportMissingTargetContracts() async {
        let cases: [(TheFence.Command, [String: HeistValue])] = [
            (.scrollToVisible, [:]),
            (.activate, [:]),
            (.rotor, ["rotor": .string("Errors")]),
        ]

        for (command, arguments) in cases {
            await assertValidationFailure(
                command: command,
                arguments: arguments
            ) { failure in
                let expectedMessages = [
                    "\(command.rawValue) request contract failed: missing target",
                    "requires target object",
                    "Next: get_interface()",
                ]
                XCTAssertTrue(expectedMessages.allSatisfy(failure.message.contains))
                XCTAssertEqual(failure.details.code, .requestMissingTarget)
                XCTAssertEqual(failure.details.phase, .request)
                XCTAssertEqual(failure.details.retryable, false)
                XCTAssertEqual(failure.details.hint, "get_interface()")
            }
        }
    }

    // MARK: - Accessibility Action Validation

    @ButtonHeistActor
    func testInvalidRotorAndActivateEnumsAreRejected() async {
        let target = targetValue(identifier: "myElement")
        let cases: [(TheFence.Command, [String: HeistValue], String)] = [
            (
                .rotor,
                ["target": target, "rotorIndex": .int(-1)],
                "schema validation failed for rotorIndex: observed integer -1; expected integer >= 0"
            ),
            (
                .rotor,
                ["target": target, "direction": .string("sideways")],
                "schema validation failed for direction: observed string \"sideways\"; expected enum one of next, previous"
            ),
            (
                .activate,
                ["target": target, "action": .string("")],
                "schema validation failed for action: observed string \"\"; expected non-empty string"
            ),
        ]

        for (command, arguments, message) in cases {
            await assertValidationError(command: command, arguments: arguments, equals: message)
        }
    }

    @ButtonHeistActor
    func testMixedAndLegacyRotorSelectorsAreRejected() async {
        let target = targetValue(identifier: "myElement")
        let cases: [([String: HeistValue], String)] = [
            (
                ["target": target, "rotor": .string("Errors"), "rotorIndex": .int(1)],
                "either rotor or rotorIndex"
            ),
            (
                ["target": target, "currentTextStartOffset": .int(4)],
                "schema validation failed for currentTextStartOffset:"
            ),
        ]

        for (arguments, message) in cases {
            await assertValidationError(command: .rotor, arguments: arguments, contains: message)
        }
    }

    @ButtonHeistActor
    func testActivateActionIncrementDispatchesSingleIncrementStep() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(command: .activate, values: [
            "target": targetValue(identifier: "myElement"),
            "action": .string("increment"),
        ])

        XCTAssertNotNil(response.leafAction, "Expected single-step action response, got \(response)")
        let commands = mockConn.sent.sentHeistActionCommands
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands.first?.wireType, .increment)
    }

    @ButtonHeistActor
    func testDirectActivateReturnsHeistExecutionBeforeFormatting() async throws {
        let (fence, _) = makeConnectedFence()

        let response = try await fence.execute(command: .activate, values: [
            "target": targetValue(identifier: "myElement"),
        ])

        assertDirectCommandHeistExecution(response, command: .activate, stepKind: .action)
        let json = try publicJSONProbe(response).object()
        try json.assertMissing("method")
        try json.assertPresent("report")
        assertCompactHeistSummary(response, stepLine: "  [0] activate")
    }

    // MARK: - Text Input Validation

    @ButtonHeistActor
    func testRequiredTextAndEditFieldsAreValidated() async {
        let cases: [(TheFence.Command, [String: HeistValue], String)] = [
            (.typeText, [:], "schema validation failed for text: observed missing; expected string"),
            (
                .typeText,
                ["text": .string("")],
                "schema validation failed for text: observed string \"\"; expected non-empty string"
            ),
            (
                .editAction,
                [:],
                "schema validation failed for action: observed missing; expected enum one of copy, paste, cut, select, selectAll, delete"
            ),
            (.setPasteboard, [:], "schema validation failed for text: observed missing; expected string"),
        ]

        for (command, arguments, message) in cases {
            await assertValidationError(command: command, arguments: arguments, equals: message)
        }
    }

    @ButtonHeistActor
    func testTypeTextWithTextPassesValidation() async {
        await assertPassesValidation(
            command: .typeText,
            arguments: ["text": .string("hello")]
        )
    }

    @ButtonHeistActor
    func testTypeTextTypedPayloadDispatchesCanonicalWireMessage() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(command: .typeText, values: [
            "text": .string("hello"),
            "target": targetValue(identifier: "search_field"),
        ])

        XCTAssertNotNil(response.leafAction, "Expected single-step action response, got \(response)")
        guard let message = mockConn.sent.sentPlanMessages.last,
              case .typeText(let payload) = message else {
            return XCTFail("Expected typeText message, got \(String(describing: mockConn.sent.sentPlanMessages.last))")
        }
        XCTAssertEqual(payload.text, "hello")
        XCTAssertEqual(payload.target, .predicate(.identifier("search_field")))
        XCTAssertEqual(payload.text.mode, .append)
    }

    @ButtonHeistActor
    func testTypeTextReplacingExistingTypedPayloadDispatchesCanonicalWireMessage() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(command: .typeText, values: [
            "text": .string(""),
            "target": targetValue(identifier: "search_field"),
            "mode": .string("replace"),
        ])

        XCTAssertNotNil(response.leafAction, "Expected single-step action response, got \(response)")
        guard let message = mockConn.sent.sentPlanMessages.last,
              case .typeText(let payload) = message else {
            return XCTFail("Expected typeText message, got \(String(describing: mockConn.sent.sentPlanMessages.last))")
        }
        XCTAssertEqual(payload.text, .replacing(""))
        XCTAssertEqual(payload.target, .predicate(.identifier("search_field")))
    }

    @ButtonHeistActor
    func testInvalidTextPayloadsAreRejectedBeforeDispatch() async throws {
        let cases: [(TheFence.Command, [String: HeistValue], String)] = [
            (
                .typeText,
                ["text": .int(3)],
                "schema validation failed for text: observed integer 3; expected string"
            ),
            (
                .setPasteboard,
                ["text": .string("")],
                "schema validation failed for text: observed string \"\"; expected non-empty string"
            ),
        ]

        for (command, arguments, message) in cases {
            let (fence, connection) = makeConnectedFence()
            let response = try await fence.execute(command: command, values: arguments)

            guard case .error(let failure) = response else {
                XCTFail("Expected error response, got \(response)")
                continue
            }
            XCTAssertEqual(failure.message, message)
            XCTAssertTrue(connection.sent.isEmpty)
        }
    }

    @ButtonHeistActor
    func testEditActionValuesPassValidation() async {
        for action in ["copy", "delete"] {
            await assertPassesValidation(
                command: .editAction,
                arguments: ["action": .string(action)]
            )
        }
    }

    // MARK: - Pasteboard Validation

    func testSetPasteboardCatalogDeclaresNonEmptyText() throws {
        let parameter = try XCTUnwrap(TheFence.Command.setPasteboard.descriptor.parameters.first { $0.key == "text" })

        XCTAssertEqual(parameter.minLength, 1)
        guard case .object(let schema) = parameter.schema.heistValue else {
            return XCTFail("Expected text parameter schema")
        }
        XCTAssertEqual(schema["minLength"], .int(1))
    }

    @ButtonHeistActor
    func testGetPasteboardRejectsExpectationBecauseItIsARead() async {
        await assertValidationError(
            command: .getPasteboard,
            arguments: ["expect": .object([
                "type": .string("changed"),
                "scope": .string("screen"),
                "assertions": .array([]),
            ])],
            contains: "valid get_pasteboard parameter"
        )
    }

    @ButtonHeistActor
    func testPureReadCommandsRemainDirectWireMessages() async throws {
        let cases: [(command: TheFence.Command, wireType: ClientWireMessageType)] = [
            (.getInterface, .requestInterface),
            (.getPasteboard, .getPasteboard),
        ]

        for testCase in cases {
            let (fence, connection) = makeConnectedFence()
            _ = try await fence.execute(command: testCase.command)

            XCTAssertEqual(connection.sent.last?.0.wireType, testCase.wireType, testCase.command.rawValue)
        }
    }

    // MARK: - Ping

    @ButtonHeistActor
    func testPingSendsRequestScopedClientPingAndReturnsPayload() async throws {
        let (fence, mockConn) = makeConnectedFence()
        fence.handoff.connect(to: TheFenceFixtures.testDevice)

        let response = try await fence.execute(command: .ping)

        guard case .pong(let payload) = response else {
            return XCTFail("Expected pong response, got \(response)")
        }
        XCTAssertEqual(payload.appName, "MockApp")
        XCTAssertEqual(payload.bundleIdentifier, "com.test.mock")
        XCTAssertEqual(payload.serverTimestampMs, 1_700_000_000_000)

        guard let sent = mockConn.sent.last else {
            return XCTFail("Expected ping to be sent")
        }
        guard case .ping = sent.0 else {
            return XCTFail("Expected ClientMessage.ping, got \(sent.0)")
        }
        XCTAssertNotNil(sent.1)
    }

    @ButtonHeistActor
    func testPingDoesNotAutoConnectWhenDisconnected() async {
        let device = DiscoveredDevice(host: "127.0.0.1", port: 1234)
        let mockConn = MockConnection()
        let fence = TheFence(configuration: .init(autoReconnect: false, directDevice: device))
        fence.handoff.makeConnection = { _ in mockConn }

        do {
            _ = try await fence.execute(command: .ping)
            XCTFail("Expected notConnected")
        } catch FenceError.notConnected {
            XCTAssertEqual(mockConn.connectCount, 0)
        } catch {
            XCTFail("Expected notConnected, got \(error)")
        }
    }

    @ButtonHeistActor
    func testPingTimeoutUsesPongTracker() async throws {
        let (fence, mockConn) = makeConnectedFence()
        fence.handoff.connect(to: TheFenceFixtures.testDevice)
        mockConn.responseScript = nil

        do {
            _ = try await fence.sendAndAwaitPong(timeout: 0.01)
            XCTFail("Expected actionTimeout")
        } catch FenceError.actionTimeout {
            guard let sent = mockConn.sent.last else {
                return XCTFail("Expected ping to be sent")
            }
            guard case .ping = sent.0 else {
                return XCTFail("Expected ClientMessage.ping, got \(sent.0)")
            }
            XCTAssertNotNil(sent.1)
        } catch {
            XCTFail("Expected actionTimeout, got \(error)")
        }
    }

    // MARK: - Wait Validation

    @ButtonHeistActor
    func testWaitMissingPredicate() async {
        await assertValidationError(command: .wait, contains: "predicate")
    }

    @ButtonHeistActor
    func testWaitPredicateShapesPassValidation() async {
        let cases: [[String: HeistValue]] = [
            ["predicate": .object([
                "type": .string("exists"),
                "target": elementPredicateValue(label: "Loading"),
            ])],
            [
                "predicate": .object([
                    "type": .string("missing"),
                    "target": elementPredicateValue(label: "Loading"),
                ]),
                "timeout": .double(5),
            ],
            ["predicate": .object([
                "type": .string("changed"),
                "scope": .string("screen"),
                "assertions": .array([]),
            ])],
            [
                "predicate": .object([
                    "type": .string("changed"),
                    "scope": .string("elements"),
                    "assertions": .array([]),
                ]),
                "timeout": .double(5),
            ],
            ["predicate": .object([
                "type": .string("changed"),
                "scope": .string("screen"),
                "assertions": .array([
                    .object(["type": .string("exists"), "target": elementPredicateValue(label: "Done")]),
                    .object(["type": .string("missing"), "target": elementPredicateValue(label: "Loading")]),
                ]),
            ])],
            ["predicate": .object([
                "type": .string("changed"),
                "scope": .string("screen"),
                "assertions": .array([.object([
                    "type": .string("exists"),
                    "target": elementPredicateValue(label: "Home"),
                ])]),
            ])],
        ]

        for arguments in cases {
            await assertPassesValidation(command: .wait, arguments: arguments)
        }
    }

    @ButtonHeistActor
    func testWaitSendsDefaultMaximumTimeout() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(command: .wait, values: [
            "predicate": .object([
                "type": .string("changed"),
                "scope": .string("screen"),
                "assertions": .array([]),
            ]),
            "timeout": .double(60.0),
        ])
        guard let step = mockConn.sent.sentWaitSteps.last else {
            return XCTFail("Expected wait step")
        }
        XCTAssertEqual(step.predicate, .changed(.screen()))
        XCTAssertEqual(step.timeout, 60.0)
    }

    @ButtonHeistActor
    func testDirectWaitReturnsHeistExecutionBeforeFormatting() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let scriptedResult = HeistReceiptFixture.result(steps: [HeistReceiptFixture.wait()])
        mockConn.responseScript = { _ in scriptedHeistResponse(scriptedResult) }

        let response = try await fence.execute(command: .wait, values: [
            "predicate": .object([
                "type": .string("changed"),
                "scope": .string("elements"),
                "assertions": .array([]),
            ]),
        ])

        assertDirectCommandHeistExecution(response, command: .wait, stepKind: .wait)
        let json = try publicJSONProbe(response).object()
        try json.assertMissing("method")
        try json.assertPresent("report")
    }

    @ButtonHeistActor
    func testInvalidExpectationIsRejectedBeforeDispatch() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(command: .activate, values: [
            "target": targetValue(identifier: "myElement"),
            "expect": .string("change"),
        ])

        guard case .error(let failure) = response else {
            return XCTFail("Expected .error response, got \(response)")
        }
        XCTAssertFalse(failure.message.isEmpty)
        XCTAssertTrue(mockConn.sent.isEmpty)
    }

    @ButtonHeistActor
    func testActionExpectationIsSentAsServerSideExpectationStep() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let predicate = AccessibilityPredicate.exists(.label("Home"))

        _ = try await fence.execute(command: .activate, values: [
            "target": targetValue(identifier: "myElement"),
            "expect": .object([
                "type": .string("exists"),
                "target": elementPredicateValue(label: "Home"),
            ]),
        ])

        // The action and its expectation cross the wire as one heist plan; the
        // expectation is a server-side step on the action, not a separate
        // client-issued wait round-trip.
        XCTAssertEqual(mockConn.sent.count, 1)
        guard case .action(let step)? = mockConn.sent.sentHeistPlan?.body.first else {
            return XCTFail("Expected a single action step, got \(String(describing: mockConn.sent.sentHeistPlan))")
        }
        XCTAssertEqual(step.expectationPolicy.expectedStep?.predicate, predicate)
    }

    // MARK: - Expectation Parsing

    @ButtonHeistActor
    func testParseExpectationNilWhenAbsent() async throws {
        let result = try parseTypedExpectation(nil)
        XCTAssertNil(result)
    }

    @ButtonHeistActor
    func testParseExpectationScreenChangedObject() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("changed"),
            "scope": .string("screen"),
            "assertions": .array([]),
        ]))
        XCTAssertEqual(result, .changed(.screen()))
    }

    @ButtonHeistActor
    func testParseExpectationRejectsGenericChangedPredicate() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("changed"),
            "assertions": .array([]),
        ]))) { error in
            XCTAssertTrue(String(describing: error).contains("scope"), "Unexpected error: \(error)")
        }
    }

    func testNormalizeToolCallRoutesWithoutParsingRequestArguments() throws {
        let result = TheFence.Command.routeToolCall(named: "perform")

        guard case .success(let command) = result else {
            return XCTFail("Expected successful command, got \(result)")
        }

        XCTAssertEqual(command, .perform)
    }

    func testNormalizeToolCallRejectsNonMCPCommands() {
        for tool in ["activate", "type_text", "wait", "swipe", "scroll", "help"] {
            let result = TheFence.Command.routeToolCall(named: tool)

            guard case .failure(let error) = result else {
                return XCTFail("Expected non-MCP command rejection, got \(result)")
            }

            XCTAssertEqual(error.message, "Unknown tool: \(tool)")
        }
    }

    @ButtonHeistActor
    func testHeistPlanCarriesTypedActionExpectation() async throws {
        let expectation = AccessibilityPredicate.changed(.elements([
            .updated(.identifier("counter"), .value(after: "5")),
        ]))
        let sourceStep = HeistStep.action(ActionStep(
            command: .activate(.predicate(ElementPredicateTemplate(identifier: .exact("counter")))),
            expectationPolicy: .expect(ActionExpectation(predicate: expectation, timeout: 10))))
        let plan = try HeistPlan(body: [sourceStep])
        guard case .action(let action)? = plan.body.first else {
            return XCTFail("Expected action step")
        }

        XCTAssertEqual(action.expectationPolicy.expectedStep?.predicate, expectation)
    }

    // MARK: - Parse Expectation: Discriminator Wire Shape

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementUpdatedFull() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("changed"),
            "scope": .string("elements"),
            "assertions": .array([.object([
                "type": .string("updated"),
                "target": elementPredicateValue(identifier: "slider"),
                "before": stringMatchValue(mode: "exact", value: "0"),
                "after": stringMatchValue(mode: "exact", value: "50"),
                "property": .string("value"),
            ])]),
        ]))
        XCTAssertEqual(
            result,
            .changed(.elements([
                .updated(.identifier("slider"), .value(before: "0", after: "50")),
            ]))
        )
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementUpdatedInvalidPropertyListsValidValues() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("changed"),
            "scope": .string("elements"),
            "assertions": .array([.object([
                "type": .string("updated"),
                "target": elementPredicateValue(identifier: "slider"),
                "property": .string("bogus"),
            ])]),
        ]))) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("ElementProperty"), msg)
            XCTAssertTrue(msg.contains("bogus"), msg)
        }
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementUpdatedRequiresTargetAndProperty() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("changed"),
            "scope": .string("elements"),
            "assertions": .array([.object(["type": .string("updated")])]),
        ])))
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorPresentWithElement() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("exists"),
            "target": elementPredicateValue(label: "Cart", identifier: "cart.button"),
        ]))
        XCTAssertEqual(
            result,
            .exists(.predicate(ElementPredicateTemplate(label: "Cart", identifier: "cart.button")))
        )
    }

    @ButtonHeistActor
    func testParseExpectationAcceptsContainerTarget() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("exists"),
            "target": .object([
                "container": .object([
                    "checks": .array([.object([
                        "kind": .string("scrollable"),
                        "value": .bool(true),
                    ])]),
                ]),
            ]),
        ]))

        XCTAssertEqual(result, .exists(.container(.matching(.scrollable(true)))))
    }

    @ButtonHeistActor
    func testParseExpectationPreservesTargetRefsForExecutionResolution() async throws {
        let item: HeistReferenceName = "item"
        let result = try parseTypedExpectation(.object([
            "type": .string("exists"),
            "target": .object(["ref": .string("item")]),
        ]))

        XCTAssertEqual(result, .exists(.ref(item)))
    }

    @ButtonHeistActor
    func testParseExpectationTypedPayloadPreservesTargetTraits() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("missing"),
            "target": accessibilityTargetValue([
                "checks": .array([
                    predicateCheckValue(kind: "label", match: stringMatchValue(mode: "exact", value: "Spinner")),
                    predicateCheckValue(kind: "traits", values: [.string("button")]),
                    predicateCheckValue(
                        kind: "exclude",
                        check: predicateCheckValue(kind: "traits", values: [.string("selected")])
                    ),
                ]),
            ]),
        ]))

        XCTAssertEqual(
            result,
            .missing(.element(
                .label("Spinner"),
                .traits([.button]),
                .exclude(.traits([.selected]))
            ))
        )
    }

    @ButtonHeistActor
    func testParseExpectationAcceptsAnnouncementWithOptionalCanonicalMatch() async throws {
        let cases: [(value: HeistValue, expected: AccessibilityPredicate)] = [
            (.object(["type": .string("announcement")]), .announcement),
            (
                .object([
                    "type": .string("announcement"),
                    "match": stringMatchValue(mode: "contains", value: "Payment complete"),
                ]),
                .announcement(.contains("Payment complete"))
            ),
        ]

        for testCase in cases {
            XCTAssertEqual(try parseTypedExpectation(testCase.value), testCase.expected)
        }
    }

    @ButtonHeistActor
    func testParseExpectationRejectsAnnouncementInChangedAssertionContexts() async {
        for (scope, context) in [("screen", "screen assertion"), ("elements", "elements assertion")] {
            XCTAssertThrowsError(try parseTypedExpectation(.object([
                "type": .string("changed"),
                "scope": .string(scope),
                "assertions": .array([.object([
                    "type": .string("announcement"),
                ])]),
            ]))) { error in
                XCTAssertTrue(String(describing: error).contains(context), "Unexpected error: \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testCanonicalExpectationDecoderRejectsUnknownTargetFields() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("exists"),
            "target": .object([
                "checks": .array([
                    predicateCheckValue(kind: "label", match: stringMatchValue(mode: "exact", value: "Done")),
                ]),
                "unknown": .string("ignored before"),
            ]),
        ])))
    }

    // MARK: - get_interface

    @ButtonHeistActor
    func testGetInterfaceDefaultSendsRequestInterfaceQuery() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(command: .getInterface)
        guard let (message, _) = mockConn.sent.last,
              case .requestInterface(let query) = message else {
            XCTFail("Expected requestInterface message, got \(String(describing: mockConn.sent.last))")
            return
        }
        XCTAssertNil(query.subtree)
        XCTAssertNil(query.maxScrollsPerContainer)
        XCTAssertNil(query.maxScrollsPerDiscovery)
    }

    @ButtonHeistActor
    func testCommandContractsRejectInvalidParameters() async {
        let cases: [(TheFence.Command, [String: HeistValue], String)] = [
            (
                .activate,
                ["target": targetValue(identifier: "save"), "mode": .string("tap")],
                "schema validation failed for mode: observed string \"tap\"; expected valid activate parameter"
            ),
            (
                .getScreen,
                ["target": targetValue(label: "Save")],
                "schema validation failed for target: observed object; expected valid get_screen parameter"
            ),
            (
                .getInterface,
                ["timeout": .int(15)],
                "schema validation failed for timeout: observed integer 15; expected valid get_interface parameter"
            ),
            (
                .getInterface,
                ["maxScrollsPerContainer": .int(0)],
                "schema validation failed for maxScrollsPerContainer: observed integer 0; expected integer between 1 and 2000"
            ),
        ]

        for (command, arguments, message) in cases {
            await assertValidationError(command: command, arguments: arguments, equals: message)
        }
    }

    @ButtonHeistActor
    func testGetInterfaceDefaultNoSubtreeReturnsWholeHierarchy() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let interfaceFixture = selectionTestInterface()
        mockConn.responseScript = { message in
            switch message {
            case .requestInterface:
                return .interface(interfaceFixture)
            default:
                return .actionResult(ActionResult.success(method: .activate))
            }
        }

        let response = try await fence.execute(command: .getInterface)

        let interface = try publicJSONProbe(response).object("interface")
        XCTAssertEqual(try interface.string("screenDescription"), "Menu — 2 buttons")
        XCTAssertEqual(try interface.string("screenId"), "menu")
        let navigation = try interface.object("navigation")
        XCTAssertEqual(try navigation.string("screenTitle"), "Menu")
        try navigation.assertMissing("backButton")
        try navigation.assertMissing("tabBarItems")
        let tree = try interface.array("tree")
        XCTAssertEqual(tree.count, 3)
        let container = try tree[1].object("container")
        XCTAssertEqual(try container.string("containerName"), "semantic_actions__actions")
        let children = try container.array("children")
        XCTAssertEqual(children.count, 2)
    }

    @ButtonHeistActor
    func testGetInterfaceQueryIsSentToInsideJobBoundaryAndReturnsSelectedInterface() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.responseScript = { message in
            switch message {
            case .requestInterface:
                let source = self.selectionTestInterface()
                let selectedNode = source.tree[1]
                let annotations = source.annotations(
                    forSubtree: selectedNode,
                    originalPath: TreePath([1]),
                    rootPath: TreePath([0])
                )
                return .interface(Interface(
                    timestamp: source.timestamp,
                    projecting: [selectedNode],
                    elementMetadata: { path, _, _ in
                        annotations.elementByPath[path].map {
                            InterfaceElementProjectionMetadata(actions: $0.actions)
                        }
                    },
                    containerMetadata: { path, _ in
                        annotations.containerByPath[path].map {
                            InterfaceContainerProjectionMetadata(
                                containerName: $0.containerName,
                                scrollInventory: $0.scrollInventory
                            )
                        }
                    }
                ))
            default:
                return .actionResult(ActionResult.success(method: .activate))
            }
        }

        let response = try await fence.execute(command: .getInterface, values: [
            "subtree": .object([
                "container": .object([
                    "checks": .array([
                        containerPredicateCheckValue(
                            kind: "identifier",
                            match: stringMatchValue(mode: "exact", value: "actions")
                        ),
                    ]),
                ]),
            ]),
            "maxScrollsPerContainer": .int(25),
            "maxScrollsPerDiscovery": .int(40),
        ])

        guard let (message, _) = mockConn.sent.last,
              case .requestInterface(let query) = message else {
            XCTFail("Expected requestInterface query, got \(String(describing: mockConn.sent.last))")
            return
        }
        XCTAssertNotNil(query.subtree)
        XCTAssertEqual(query.maxScrollsPerContainer, 25)
        XCTAssertEqual(query.maxScrollsPerDiscovery, 40)

        let tree = try publicJSONProbe(response).object("interface").array("tree")
        XCTAssertEqual(tree.count, 1)
        let container = try tree[0].object("container")
        XCTAssertEqual(try container.string("containerName"), "semantic_actions__actions")
        let children = try container.array("children")
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(try children[0].object("element").string("label"), "Submit")
        try children[0].object("element").assertMissing("heistId")
        XCTAssertEqual(try children[1].object("element").string("label"), "Cancel")
    }

    @ButtonHeistActor
    func testGetInterfaceSubtreeRejectsUnknownTargetFields() async {
        let cases: [(subtree: [String: HeistValue], field: String)] = [
            (
                [
                    "heistId": .string("button_save"),
                    "ordinal": .int(1),
                ],
                "heistId"
            ),
            (
                [
                    "checks": .array([
                        predicateCheckValue(kind: "label", match: stringMatchValue(mode: "exact", value: "Save")),
                    ]),
                    "unexpectedTargetField": .string("button_save"),
                ],
                "unexpectedTargetField"
            ),
        ]

        for testCase in cases {
            await assertValidationError(
                command: .getInterface,
                arguments: ["subtree": .object(testCase.subtree)],
                contains: testCase.field
            )
        }
    }

    func testContainerNameAppearsInSummaryJsonAndCompactOutput() throws {
        let response = FenceResponse.interface(selectionTestInterface(), detail: .summary)

        let tree = try publicJSONProbe(response)
            .object("interface")
            .array("tree")
        let container = try tree[1].object("container")
        XCTAssertEqual(try container.string("containerName"), "semantic_actions__actions")
        try container.assertMissing("frameX")

        let compact = response.compactFormatted()
        XCTAssertTrue(
            compact.contains(#"── group "Actions" id="actions" "semantic_actions__actions" ──"#),
            compact
        )
        XCTAssertFalse(compact.contains("stableId"), compact)
    }

    @ButtonHeistActor
    func testGetInterfaceDetailDoesNotChangeObservationDispatch() async {
        let (fullFence, fullMock) = makeConnectedFence()
        _ = try? await fullFence.execute(command: .getInterface, values: ["detail": .string("full")])
        guard let (fullMessage, _) = fullMock.sent.last,
              case .requestInterface = fullMessage else {
            XCTFail("Expected detail=full on get_interface to send requestInterface, got \(String(describing: fullMock.sent.last))")
            return
        }
    }

    @ButtonHeistActor
    func testGetInterfaceRejectsScopeParameter() async {
        await assertValidationError(
            command: .getInterface,
            arguments: ["scope": .string("current")],
            equals: "schema validation failed for scope: observed string \"current\"; expected valid get_interface parameter"
        )
    }

}

private struct ExpectedDiagnosticFailure {
    let name: String
    let response: FenceResponse
    let code: KnownFailureCode
    let kind: DiagnosticFailureKind
    let phase: FailurePhase
    let message: String
    let retryable: Bool
}

private func legacyHeistIdTargetValue(_ legacyHeistId: String) -> HeistValue {
    accessibilityTargetValue(["heistId": .string(legacyHeistId)])
}

private func targetValue(
    label: String? = nil,
    identifier: String? = nil,
    value: String? = nil,
    traits: [String]? = nil,
    ordinal: Int? = nil
) -> HeistValue {
    var checks: [HeistValue] = []
    if let label {
        checks.append(predicateCheckValue(kind: "label", match: stringMatchValue(mode: "exact", value: label)))
    }
    if let identifier {
        checks.append(predicateCheckValue(kind: "identifier", match: stringMatchValue(mode: "exact", value: identifier)))
    }
    if let value {
        checks.append(predicateCheckValue(kind: "value", match: stringMatchValue(mode: "exact", value: value)))
    }
    if let traits {
        checks.append(predicateCheckValue(kind: "traits", values: traits.map { .string($0) }))
    }
    var target: [String: HeistValue] = ["checks": .array(checks)]
    if let ordinal { target["ordinal"] = .int(ordinal) }
    return accessibilityTargetValue(target)
}

private func elementPredicateValue(
    label: String? = nil,
    identifier: String? = nil,
    value: String? = nil,
    traits: [String]? = nil
) -> HeistValue {
    var checks: [HeistValue] = []
    if let label {
        checks.append(predicateCheckValue(kind: "label", match: stringMatchValue(mode: "exact", value: label)))
    }
    if let identifier {
        checks.append(predicateCheckValue(kind: "identifier", match: stringMatchValue(mode: "exact", value: identifier)))
    }
    if let value {
        checks.append(predicateCheckValue(kind: "value", match: stringMatchValue(mode: "exact", value: value)))
    }
    if let traits {
        checks.append(predicateCheckValue(kind: "traits", values: traits.map { .string($0) }))
    }
    return accessibilityTargetValue(["checks": .array(checks)])
}

private func stringMatchValue(mode: String, value: String) -> HeistValue {
    .object([
        "mode": .string(mode),
        "value": .string(value),
    ])
}

private func accessibilityTargetValue(_ fields: [String: HeistValue]) -> HeistValue {
    .object(fields)
}

private func predicateCheckValue(
    kind: String,
    match: HeistValue? = nil,
    values: [HeistValue]? = nil,
    check: HeistValue? = nil
) -> HeistValue {
    var object: [String: HeistValue] = ["kind": .string(kind)]
    if let match { object["match"] = match }
    if let values { object["values"] = .array(values) }
    if let check { object["check"] = check }
    return .object(object)
}

private func containerPredicateCheckValue(
    kind: String,
    match: HeistValue? = nil,
    type: String? = nil,
    value: HeistValue? = nil
) -> HeistValue {
    var object: [String: HeistValue] = ["kind": .string(kind)]
    if let match { object["match"] = match }
    if let type { object["type"] = .string(type) }
    if let value { object["value"] = value }
    return .object(object)
}

private func assertCompactHeistSummary(
    _ response: FenceResponse,
    stepLine: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let lines = response.compactFormatted().split(separator: "\n").map(String.init)
    XCTAssertEqual(lines.count, 2, file: file, line: line)
    XCTAssertTrue(
        lines.first?.hasPrefix("heist: 1 top-level steps in ") == true,
        lines.first ?? "<missing>",
        file: file,
        line: line
    )
    XCTAssertTrue(
        lines.first?.hasSuffix("ms") == true,
        lines.first ?? "<missing>",
        file: file,
        line: line
    )
    XCTAssertEqual(lines.last, stepLine, file: file, line: line)
}

private func parseTypedExpectation(_ expectation: HeistValue?) throws -> AccessibilityPredicate? {
    var values: [String: HeistValue] = [:]
    if let expectation {
        values["expect"] = expectation
    }
    return try TheFence.ExpectationPayload(
        arguments: TheFence.CommandArgumentEnvelope(values: values)
    ).expectation
}
