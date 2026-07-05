import ButtonHeistTestSupport
import XCTest
import Network
@_spi(ButtonHeistTooling) @testable import ButtonHeist
@_spi(ButtonHeistInternals) import ThePlans
@_spi(ButtonHeistInternals) import TheScore

private extension AccessibilityTrace.Delta {
    var testKind: String {
        switch self {
        case .noChange:
            return AccessibilityTrace.DeltaKind.noChange.rawValue
        case .elementsChanged:
            return AccessibilityTrace.DeltaKind.elementsChanged.rawValue
        case .screenChanged:
            return AccessibilityTrace.DeltaKind.screenChanged.rawValue
        }
    }
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

        ForEach(["Milk", "Bread"]) { item in
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
        .tlsCertificateMismatch: .init(
            .connection,
            .tls,
            retryable: false,
            hint: "Current clients use token-derived TLS PSK. Rebuild or reinstall, then retry with the configured token."
        ),
        .tlsMissingFingerprint: .init(
            .connection,
            .tls,
            retryable: false,
            hint: "Current clients use token-derived TLS PSK. Rebuild or reinstall, then retry with the configured token."
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

    /// Assert that executing a typed operation returns a `.error(...)` response containing the substring.
    @ButtonHeistActor
    private func assertValidationError(
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        contains substring: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(command: command, values: arguments)
            if case .error(let failure) = response {
                XCTAssertTrue(
                    failure.message.contains(substring),
                    "Expected error containing '\(substring)', got: \(failure.message)",
                    file: file, line: line
                )
            } else {
                XCTFail("Expected .error response, got: \(response)", file: file, line: line)
            }
        } catch {
            XCTFail("Unexpected throw: \(error)", file: file, line: line)
        }
    }

    /// Assert that executing a typed operation returns a `.error(...)` response with the exact message.
    @ButtonHeistActor
    private func assertValidationError(
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(command: command, values: arguments)
            if case .error(let failure) = response {
                XCTAssertEqual(failure.message, expected, file: file, line: line)
            } else {
                XCTFail("Expected .error response, got: \(response)", file: file, line: line)
            }
        } catch {
            XCTFail("Unexpected throw: \(error)", file: file, line: line)
        }
    }

    @ButtonHeistActor
    private func assertContractError(
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        contains expectedSubstrings: [String],
        errorCode: KnownFailureCode,
        nextCommand: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(command: command, values: arguments)
            guard case .error(let failure) = response else {
                return XCTFail("Expected .error response, got: \(response)", file: file, line: line)
            }
            for substring in expectedSubstrings {
                XCTAssertTrue(
                    failure.message.contains(substring),
                    "Expected error containing '\(substring)', got: \(failure.message)",
                    file: file, line: line
                )
            }
            XCTAssertEqual(failure.details.code.knownCode, errorCode, file: file, line: line)
            XCTAssertEqual(failure.details.phase, .request, file: file, line: line)
            XCTAssertEqual(failure.details.retryable, false, file: file, line: line)
            XCTAssertEqual(failure.details.hint, nextCommand, file: file, line: line)
        } catch {
            XCTFail("Unexpected throw: \(error)", file: file, line: line)
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
    private func assertOperationValidationError(
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        contains substring: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(command: command, values: arguments)
            if case .error(let failure) = response {
                XCTAssertTrue(
                    failure.message.contains(substring),
                    "Expected error containing '\(substring)', got: \(failure.message)",
                    file: file,
                    line: line
                )
            } else {
                XCTFail("Expected .error response, got: \(response)", file: file, line: line)
            }
        } catch {
            XCTFail("Unexpected throw: \(error)", file: file, line: line)
        }
    }

    @ButtonHeistActor
    private func assertOperationValidationError(
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(command: command, values: arguments)
            if case .error(let failure) = response {
                XCTAssertEqual(failure.message, expected, file: file, line: line)
            } else {
                XCTFail("Expected .error response, got: \(response)", file: file, line: line)
            }
        } catch {
            XCTFail("Unexpected throw: \(error)", file: file, line: line)
        }
    }

    @ButtonHeistActor
    private func assertOperationPassesValidation(
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
    private func decodedElementTarget(
        target: HeistValue? = nil
    ) throws -> ElementTarget? {
        var arguments: [String: HeistValue] = [:]
        if let target {
            arguments["target"] = target
        }
        return try TheFence.CommandArgumentEnvelope(values: arguments).decodedElementTarget()
    }

    private func selectionTestInterface(includeDuplicateGroup: Bool = false) -> Interface {
        let header = TestHeistElementBuilder(label: "Menu", traits: [.header]).build()
        let submit = TestHeistElementBuilder(label: "Submit", traits: [.button]).build()
        let cancel = TestHeistElementBuilder(label: "Cancel", traits: [.button]).build()
        let footer = TestHeistElementBuilder(label: "Footer", traits: []).build()
        var nodes: [ReceiptTestInterfaceNode] = [
            .element(header),
            .container(
                makeReceiptTestSemanticContainer(
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
            let archive = TestHeistElementBuilder(label: "Archive", traits: [.button]).build()
            nodes.insert(
                .container(
                    makeReceiptTestSemanticContainer(
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
        return makeReceiptTestInterface(nodes: nodes)
    }

    // MARK: - Public Failure Mapping

    func testDiagnosticFailureIsDiagnosticFailureBoundaryValue() {
        let details = FailureDetails(
            code: .requestValidationError,
            hint: "Fix the request."
        )

        let diagnostic = DiagnosticFailure(message: "Invalid request", details: details)
        let diagnosticFailure: DiagnosticFailure = diagnostic

        XCTAssertEqual(diagnosticFailure.failureCode, FailureCode(.requestValidationError))
        XCTAssertEqual(diagnosticFailure.code, "request.validation_error")
        XCTAssertEqual(diagnosticFailure.kind, .request)
        XCTAssertEqual(diagnosticFailure.message, "Invalid request")
        XCTAssertEqual(diagnosticFailure.displayMessage, "Invalid request")
        XCTAssertEqual(diagnosticFailure.details, details)
        XCTAssertEqual(diagnosticFailure.phase, .request)
        XCTAssertEqual(diagnosticFailure.retryable, false)
        XCTAssertEqual(diagnosticFailure.hint, "Fix the request.")
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

        let json = try publicJSONProbe(response).object()
        XCTAssertEqual(failure.failureCode, FailureCode(.requestInvalid))
        XCTAssertEqual(failure.details.code, FailureCode(.requestInvalid))
        XCTAssertEqual(try json.string("status"), "error")
        XCTAssertEqual(try json.string("message"), failure.displayMessage)
        XCTAssertEqual(try json.string("code"), failure.code)
        XCTAssertEqual(try json.string("kind"), failure.kind.rawValue)
        XCTAssertEqual(try json.string("errorCode"), failure.code)
        XCTAssertEqual(try json.string("phase"), failure.phase.rawValue)
        XCTAssertEqual(try json.bool("retryable"), failure.retryable)
        XCTAssertEqual(try json.string("hint"), failure.hint)

        let detailsJSON = try json.object("details")
        XCTAssertEqual(try detailsJSON.string("code"), failure.code)
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

        XCTAssertEqual(failure.failureCode.rawValue, diagnostics[0].code.rawValue)
        XCTAssertNil(failure.failureCode.knownCode)
        XCTAssertEqual(failure.code, diagnostics[0].code.rawValue)
        XCTAssertEqual(failure.kind, .request)
        XCTAssertEqual(failure.phase, .request)
        XCTAssertFalse(failure.retryable)
        XCTAssertEqual(failure.hint, diagnostics[0].hint)
        XCTAssertEqual(failure.buildDiagnostics, diagnostics)
        XCTAssertTrue(failure.message.contains("expected an identifier"), failure.message)

        let json = try publicJSONProbe(response).object()
        XCTAssertEqual(try json.string("code"), diagnostics[0].code.rawValue)
        XCTAssertEqual(try json.string("errorCode"), diagnostics[0].code.rawValue)
        XCTAssertEqual(try json.string("kind"), DiagnosticFailureKind.request.rawValue)
        XCTAssertEqual(try json.string("phase"), FailurePhase.request.rawValue)
        XCTAssertFalse(try json.bool("retryable"))
        XCTAssertEqual(try json.string("hint"), diagnostics[0].hint)

        let detailsJSON = try json.object("details")
        XCTAssertEqual(try detailsJSON.string("code"), diagnostics[0].code.rawValue)
        XCTAssertEqual(try detailsJSON.string("phase"), FailurePhase.request.rawValue)
        XCTAssertFalse(try detailsJSON.bool("retryable"))

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
            let code = FailureCode(knownCode)
            let details = FailureDetails(code: knownCode)

            XCTAssertEqual(code.rawValue, knownCode.rawValue)
            XCTAssertEqual(code.knownCode, knownCode)
            XCTAssertEqual(code.kind, expectation.kind)
            XCTAssertEqual(code.phase, expectation.phase)
            XCTAssertEqual(code.retryable, expectation.retryable)
            XCTAssertEqual(code.defaultHint, expectation.hint)
            XCTAssertEqual(details.code, code)
            XCTAssertEqual(details.errorCode, knownCode.rawValue)
            XCTAssertEqual(details.phase, expectation.phase)
            XCTAssertEqual(details.retryable, expectation.retryable)
            XCTAssertEqual(details.hint, expectation.hint)
        }
    }

    func testCustomFailureCodeUsesExplicitBoundaryValueAndPhaseFallback() {
        let details = FailureDetails(
            code: FailureCode(boundaryRawValue: "plugin.custom_failure"),
            phase: .server,
            retryable: false,
            hint: nil
        )
        let failure = DiagnosticFailure(message: "Plugin failed", details: details)

        XCTAssertNil(failure.failureCode.knownCode)
        XCTAssertEqual(failure.failureCode.rawValue, "plugin.custom_failure")
        XCTAssertEqual(failure.code, "plugin.custom_failure")
        XCTAssertEqual(failure.kind, .server)
        XCTAssertEqual(failure.phase, .server)
    }

    func testDiagnosticFailureJSONPreservesRawKnownCodesAcrossRepresentativeKinds() throws {
        let cases: [(String, FenceResponse, KnownFailureCode, DiagnosticFailureKind, FailurePhase)] = [
            (
                "request",
                FenceResponse.failure(FenceOperationRoutingError(message: "Unknown tool: warp")),
                .requestInvalid,
                .request,
                .request
            ),
            (
                "discovery",
                FenceResponse.failure(FenceError.noDeviceFound),
                .discoveryNoDeviceFound,
                .discovery,
                .discovery
            ),
            (
                "transport",
                FenceResponse.failure(FenceError.connectionFailure(ConnectionFailure(
                    message: "network down",
                    failureCode: FailureCode(.transportNetworkError),
                    phase: .transport,
                    retryable: true,
                    hint: "retry"
                ))),
                .transportNetworkError,
                .connection,
                .transport
            ),
            (
                "action",
                FenceResponse.failure(FenceError.actionFailed("could not activate target")),
                .requestActionFailed,
                .request,
                .request
            ),
        ]

        for (name, response, knownCode, kind, phase) in cases {
            let failure = try XCTUnwrap(response.diagnosticFailure, name)
            let json = try publicJSONProbe(response).object()
            let detailsJSON = try json.object("details")

            XCTAssertEqual(failure.failureCode, FailureCode(knownCode), name)
            XCTAssertEqual(failure.code, knownCode.rawValue, name)
            XCTAssertEqual(failure.kind, kind, name)
            XCTAssertEqual(failure.phase, phase, name)
            XCTAssertEqual(try json.string("code"), knownCode.rawValue, name)
            XCTAssertEqual(try json.string("errorCode"), knownCode.rawValue, name)
            XCTAssertEqual(try json.string("kind"), kind.rawValue, name)
            XCTAssertEqual(try json.string("phase"), phase.rawValue, name)
            XCTAssertEqual(try detailsJSON.string("code"), knownCode.rawValue, name)
            XCTAssertEqual(try detailsJSON.string("kind"), kind.rawValue, name)
            XCTAssertEqual(try detailsJSON.string("phase"), phase.rawValue, name)
        }
    }

    func testKnownFailuresExposeCompleteDiagnosticFields() throws {
        let validationError = SchemaValidationError(
            field: "target",
            observed: "string",
            expected: "object"
        )
        let cases: [ExpectedDiagnosticFailure] = [
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
        ]

        for expected in cases {
            let failure = try XCTUnwrap(expected.response.diagnosticFailure, expected.name)
            XCTAssertEqual(failure.failureCode.knownCode, expected.code, expected.name)
            XCTAssertEqual(failure.failureCode.rawValue, expected.code.rawValue, expected.name)
            XCTAssertEqual(failure.code, expected.code.rawValue, expected.name)
            XCTAssertEqual(failure.kind, expected.kind, expected.name)
            XCTAssertEqual(failure.phase, expected.phase, expected.name)
            XCTAssertEqual(failure.message, expected.message, expected.name)
            XCTAssertEqual(failure.displayMessage, expected.message, expected.name)
            XCTAssertEqual(failure.retryable, expected.retryable, expected.name)
            XCTAssertEqual(failure.details.code.knownCode, expected.code, expected.name)
            XCTAssertEqual(failure.details.phase, expected.phase, expected.name)
            XCTAssertEqual(failure.details.retryable, expected.retryable, expected.name)
            XCTAssertFalse(failure.code.isEmpty, expected.name)
            XCTAssertFalse(failure.kind.rawValue.isEmpty, expected.name)
            XCTAssertFalse(failure.message.isEmpty, expected.name)
        }
    }

    func testDiagnosticFailureMapperMapsKnownFenceError() throws {
        let response = FenceResponse.failure(FenceError.notConnected)
        let failure = try XCTUnwrap(response.diagnosticFailure)

        XCTAssertEqual(failure.failureCode, FailureCode(.connectionNotConnected))
        XCTAssertEqual(failure.code, KnownFailureCode.connectionNotConnected.rawValue)
        XCTAssertEqual(failure.kind, .connection)
        XCTAssertEqual(failure.message, "Not connected to device.")
        XCTAssertEqual(failure.details.code.knownCode, .connectionNotConnected)
        XCTAssertEqual(failure.details.phase, .request)
        XCTAssertEqual(failure.details.retryable, true)
    }

    func testDiagnosticFailureMapperMapsConnectionDomainError() throws {
        let response = FenceResponse.failure(HandoffConnectionError.timeout)
        let failure = try XCTUnwrap(response.diagnosticFailure)

        XCTAssertEqual(failure.failureCode, FailureCode(.setupTimeout))
        XCTAssertEqual(failure.code, KnownFailureCode.setupTimeout.rawValue)
        XCTAssertEqual(failure.kind, .connection)
        XCTAssertEqual(failure.message, "Connection timed out")
        XCTAssertEqual(failure.details.phase, .setup)
        XCTAssertEqual(failure.details.retryable, true)
    }

    func testAuthFailureMappingPreservesSourceHint() throws {
        let hint = "Retry with the configured token."
        let response = FenceResponse.failure(HandoffConnectionError.disconnected(
            .authFailed("Invalid token", hint: hint)
        ))
        let failure = try XCTUnwrap(response.diagnosticFailure)

        XCTAssertEqual(failure.failureCode, FailureCode(.authFailed))
        XCTAssertEqual(failure.code, KnownFailureCode.authFailed.rawValue)
        XCTAssertEqual(failure.kind, .authentication)
        XCTAssertEqual(failure.phase, .authentication)
        XCTAssertEqual(failure.retryable, false)
        XCTAssertEqual(failure.hint, hint)
        XCTAssertEqual(failure.details.hint, hint)

        let json = try publicJSONProbe(response).object()
        XCTAssertEqual(try json.string("code"), KnownFailureCode.authFailed.rawValue)
        XCTAssertEqual(try json.string("kind"), DiagnosticFailureKind.authentication.rawValue)
        XCTAssertEqual(try json.string("phase"), FailurePhase.authentication.rawValue)
        XCTAssertEqual(try json.string("hint"), hint)

        let detailsJSON = try json.object("details")
        XCTAssertEqual(try detailsJSON.string("code"), KnownFailureCode.authFailed.rawValue)
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

        XCTAssertEqual(failure.failureCode, FailureCode(.authFailed))
        XCTAssertTrue(failure.message.contains(reason), failure.message)
        XCTAssertEqual(failure.hint, "Retry with the configured token.")

        let json = try publicJSONProbe(response).object()
        XCTAssertEqual(try json.string("code"), KnownFailureCode.authFailed.rawValue)
        XCTAssertEqual(try json.string("kind"), DiagnosticFailureKind.authentication.rawValue)
        XCTAssertTrue(try json.string("message").contains(reason))
    }

    @ButtonHeistActor
    func testTransportSendFailureUsesNetworkDiagnosticShape() async throws {
        let (fence, mockConn) = makeConnectedFence(configuration: .init(autoReconnect: false))
        mockConn.sendOutcome = .failed(.transportFailed(DeviceTransportFailure(.posix(.ECONNRESET))))

        let response: FenceResponse
        do {
            response = try await fence.execute(command: .getInterface)
        } catch {
            response = FenceResponse.failure(error)
        }
        let failure = try XCTUnwrap(response.diagnosticFailure)

        XCTAssertEqual(failure.failureCode, FailureCode(.transportNetworkError))
        XCTAssertNotEqual(failure.failureCode, FailureCode(.requestActionFailed))
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
        XCTAssertEqual(try json.string("errorCode"), KnownFailureCode.transportNetworkError.rawValue)
        XCTAssertEqual(try json.string("kind"), DiagnosticFailureKind.connection.rawValue)
        XCTAssertEqual(try json.string("phase"), FailurePhase.transport.rawValue)
        XCTAssertTrue(try json.bool("retryable"))
        XCTAssertEqual(try json.string("hint"), KnownFailureCode.transportNetworkError.defaultHint)

        let detailsJSON = try json.object("details")
        XCTAssertEqual(try detailsJSON.string("code"), KnownFailureCode.transportNetworkError.rawValue)
        XCTAssertEqual(try detailsJSON.string("kind"), DiagnosticFailureKind.connection.rawValue)
        XCTAssertEqual(try detailsJSON.string("phase"), FailurePhase.transport.rawValue)
        XCTAssertTrue(try detailsJSON.bool("retryable"))
    }

    @ButtonHeistActor
    func testDirectActionExpectIsRejectedBeforeDispatch() async throws {
        await assertValidationError(
            command: .scroll,
            arguments: [
                "expect": .object([
                    "type": .string("change"),
                    "scopes": .array([.object(["type": .string("screen")])]),
                ]),
            ],
            equals: "command \"scroll\" direct dispatch does not support expect"
        )
    }

    @ButtonHeistActor
    func testDispatchSchemaFailureUsesDiagnosticFailureMapper() async throws {
        let fence = TheFence(configuration: .init())
        let validationError = SchemaValidationError(
            field: "target",
            observed: "integer 7",
            expected: "object"
        )
        let parsed = TheFence.ParsedRequest(
            command: .listTargets,
            requestId: "public-failure-test",
            arguments: TheFence.CommandArgumentEnvelope(values: [:]),
            dispatch: TheFence.DecodedRequestDispatch(handler: { _, _ in
                throw validationError
            }),
            expectationPayload: TheFence.ExpectationPayload(expectation: nil, timeout: nil)
        )

        let response = try await fence.execute(parsed: parsed)
        let failure = try XCTUnwrap(response.diagnosticFailure)

        XCTAssertEqual(failure.failureCode.knownCode, .requestValidationError)
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
            probe.autoResponse = { message in
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

        XCTAssertFalse(fence.handoff.isConnected)
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

        var arguments = try Self.inlineArguments(for: try HeistPlan(body: [.warn(WarnStep(message: "x"))])).argumentValues
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
                    Activate(.label("Pay")).expect(.change(.screen()))
                }
                """),
            ])
        )

        XCTAssertEqual(request.plan.body, [
            .action(try ActionStep(
                command: .activate(.predicate(.label("Pay"))),
                expectationPolicy: .expect(ActionExpectation(predicate: .change(.screen()), timeout: 1)))),
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
            .action(try ActionStep(command: .activate(.predicate(.label("Pay"))))),
        ])
        XCTAssertEqual(mockConn.sent.sentHeistPlan, plan)
        XCTAssertEqual(result.steps.map(\.kind), [.action])
        XCTAssertFalse(result.isFailure)

        let json = try publicJSONProbe(response).object()
        try json.assertMissing("method")
        let report = try publicHeistReportResponseDTO(response).report
        let firstNode = try XCTUnwrap(report.nodes.first)
        XCTAssertEqual(firstNode.kind, "action")
        XCTAssertFalse(firstNode.containsKey("action"))
        let evidence = try XCTUnwrap(firstNode.evidence)
        XCTAssertNotNil(evidence.action)
    }

    @ButtonHeistActor
    func testPerformDecodesSimpleWaitStepThroughThePlans() async throws {
        let fence = TheFence(configuration: .init())

        let request = try fence.decodePerformRequest(TheFence.CommandArgumentEnvelope(values: [
            "step": .string(#"WaitFor(.exists(.label("Pay")), timeout: .seconds(5))"#),
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
            WaitFor(.exists(.label("Receipt")), timeout: .seconds(5)).else {
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
            WaitFor(.exists(.label("Receipt")), timeout: .seconds(5)) {
                Activate(.label("Done"))
            }
            """,
            """
            ForEach(["Milk"]) { item in
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
    func testRunHeistExecutesPureRuntimeSourceThroughValidatedPlan() async throws {
        let (fence, mockConn) = makeConnectedFence()
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
        XCTAssertEqual(result.steps.map(\.kind), [.warn, .action, .forEachString])
        XCTAssertFalse(result.isFailure)
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

            let (fence, _) = makeConnectedFence()
            fence.handoff.connect(to: TheFenceFixtures.testDevice)

            let response = try await fence.execute(command: .runHeist, values: [
                "plan": .string(Self.pureRuntimeHeistSource),
            ])

            guard case .heistExecution(_, let result, _) = response else {
                return XCTFail("Expected heistExecution response, got \(response)")
            }
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
        // Nested definitions + invoke + a string parameter all round-trip.
        let definition = try HeistPlan(
            name: "addToCart",
            parameter: .string(name: "item"),
            body: [.action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.ref("item")))))))]
        )
        let plan = try HeistPlan(definitions: [definition], body: [
            .invoke(HeistInvocationStep(path: ["addToCart"], argument: .string(.literal("Milk")))),
        ])

        let request = try fence.decodeRunHeistRequest(try Self.planSourceArguments(for: plan))
        XCTAssertEqual(request.plan, plan)
    }

    @ButtonHeistActor
    func testRunHeistDecodesInlinePlanWithElementTargetParameter() async throws {
        let fence = TheFence(configuration: .init())
        let definition = try HeistPlan(
            name: "tapEach",
            parameter: .elementTarget(name: "input"),
            body: [.action(try ActionStep(command: .activate(.ref("input"))))]
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
            body: [.action(try ActionStep(command: .typeText(
                text: .ref("query"),
                target: .target(.predicate(.label("Search")))
            )))]
        )
        var arguments = try Self.planSourceArguments(for: plan).argumentValues
        arguments["argument"] = .object([
            "type": .string("string"),
            "value": .string("milk"),
        ])

        let request = try fence.decodeRunHeistRequest(TheFence.CommandArgumentEnvelope(values: arguments))

        XCTAssertEqual(request.plan, plan)
        XCTAssertEqual(request.argument, .string(.literal("milk")))
    }

    @ButtonHeistActor
    func testRunHeistRejectsMultipleStringRootArgumentValues() async throws {
        let fence = TheFence(configuration: .init())
        let plan = try HeistPlan(
            name: "search",
            parameter: .string(name: "query"),
            body: [.action(try ActionStep(command: .typeText(
                text: .ref("query"),
                target: .target(.predicate(.label("Search")))
            )))]
        )
        var arguments = try Self.planSourceArguments(for: plan).argumentValues
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
    func testRunHeistDecodesParameterizedRootWithElementTargetArgument() async throws {
        let fence = TheFence(configuration: .init())
        let plan = try HeistPlan(
            name: "tapRow",
            parameter: .elementTarget(name: "row"),
            body: [.action(try ActionStep(command: .activate(.ref("row"))))]
        )
        var arguments = try Self.planSourceArguments(for: plan).argumentValues
        arguments["argument"] = .object([
            "type": .string("element_target"),
            "target": targetValue(label: "Row 1"),
        ])

        let request = try fence.decodeRunHeistRequest(TheFence.CommandArgumentEnvelope(values: arguments))

        XCTAssertEqual(request.plan, plan)
        XCTAssertEqual(request.argument, .elementTarget(.predicate(.label("Row 1"))))
    }

    @ButtonHeistActor
    func testRunHeistRejectsUnknownElementTargetArgumentKey() async throws {
        let fence = TheFence(configuration: .init())
        let plan = try HeistPlan(
            name: "tapRow",
            parameter: .elementTarget(name: "row"),
            body: [.action(try ActionStep(command: .activate(.ref("row"))))]
        )
        var arguments = try Self.planSourceArguments(for: plan).argumentValues
        arguments["argument"] = .object([
            "type": .string("element_target"),
            "target": .object([
                "label": stringMatchValue(mode: "exact", value: "Row 1"),
                "unexpected": .string("ignored before"),
            ]),
        ])

        XCTAssertThrowsError(try fence.decodeRunHeistRequest(TheFence.CommandArgumentEnvelope(values: arguments))) { error in
            guard let error = error as? SchemaValidationError else {
                return XCTFail("Expected SchemaValidationError, got \(error)")
            }
            XCTAssertEqual(error.field, "argument.target.unexpected")
            XCTAssertEqual(error.expected, "valid argument.target property")
        }
    }

    @ButtonHeistActor
    func testRunHeistRejectsMissingRootArgumentForParameterizedRoot() async throws {
        let fence = TheFence(configuration: .init())
        let plan = try HeistPlan(
            name: "search",
            parameter: .string(name: "query"),
            body: [.action(try ActionStep(command: .typeText(
                text: .ref("query"),
                target: .target(.predicate(.label("Search")))
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
            body: [.invoke(HeistInvocationStep(path: ["addToCart"], argument: .string(.literal("Milk"))))]
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
        let definition = try HeistPlan(
            name: "addToCart",
            parameter: .string(name: "item"),
            body: [.action(try ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.ref("item")))))))]
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
        XCTAssertEqual(catalog.heists.map(\.name), ["shop", "addToCart"])
        XCTAssertEqual(catalog.heists[1].parameterKind, .string)
        XCTAssertTrue(catalog.heists[1].requiresArgument)
        XCTAssertEqual(catalog.heists[1].summary, "Reusable heist capability requiring string argument")
        XCTAssertEqual(catalog.heists[1].tags, ["capability", "parameterized", "semantic-action"])
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
        XCTAssertEqual(catalog.heists.map(\.name), ["shop", "addToCart"])
        XCTAssertEqual(catalog.heists[1].parameterKind, .string)
        XCTAssertTrue(catalog.heists[1].requiresArgument)
    }

    @ButtonHeistActor
    func testDiscoveryCommandsUseSamePureRuntimeSourceAsRunHeist() async throws {
        let fence = TheFence(configuration: .init())
        let sourceArguments = TheFence.CommandArgumentEnvelope(values: [
            "plan": .string(Self.pureRuntimeHeistSource),
            "detail": .string("detailed"),
        ])

        let listResponse = try await fence.execute(command: .listHeists, arguments: sourceArguments)
        guard case .heistCatalog(let catalog) = listResponse else {
            return XCTFail("Expected heistCatalog response, got \(listResponse)")
        }
        XCTAssertEqual(catalog.heists.map(\.name), ["agentFlow", "Cart", "Cart.addItem"])
        let addItem = try XCTUnwrap(catalog.heists.first { $0.name == "Cart.addItem" })
        XCTAssertEqual(addItem.parameterKind, .string)
        XCTAssertEqual(addItem.actionCommands, ["activate"])
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
        XCTAssertEqual(description.name, "Cart.addItem")
        XCTAssertEqual(description.parameterKind, .string)
        XCTAssertEqual(description.semanticSurface.actionCommands, ["activate"])
        XCTAssertEqual(description.semanticSurface.targetPredicates, [#"predicate(label=stringRef("item"))"#])
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
                        .action(try ActionStep(command: .activate(.predicate(.identifier(.literal("confirm_button")))))),
                    ]
                ),
            ],
            body: [
                .action(try ActionStep(
                    command: .activate(.predicate(.label("Checkout"))),
                    expectationPolicy: .expect(ActionExpectation(predicate: .exists(.label("Done")), timeout: 1)))),
                .wait(WaitStep(predicate: .exists(.label("Receipt")), timeout: 1)),
                .invoke(HeistInvocationStep(path: ["confirm"])),
            ]
        )
        let plan = try HeistPlan(
            name: "shop",
            definitions: [definition],
            body: [.warn(WarnStep(message: "ready"))]
        )
        var arguments = try Self.planSourceArguments(for: plan).argumentValues
        arguments["detail"] = .string("detailed")

        let response = try await fence.execute(
            command: .listHeists,
            arguments: TheFence.CommandArgumentEnvelope(values: arguments)
        )

        guard case .heistCatalog(let catalog) = response else {
            return XCTFail("Expected heistCatalog response, got \(response)")
        }
        let checkout = try XCTUnwrap(catalog.heists.first { $0.name == "checkout" })
        XCTAssertEqual(checkout.nestedRunHeists, ["checkout.confirm"])
        XCTAssertEqual(checkout.actionCommands, ["activate"])
        XCTAssertEqual(checkout.waitCount, 1)
        XCTAssertEqual(checkout.expectationCount, 1)
        XCTAssertEqual(checkout.semanticSurfaces, [
            "label=Checkout",
            "label=Done",
            "label=Receipt",
            "identifier=confirm_button",
        ])
        XCTAssertEqual(checkout.validationStatus, .validated)
        XCTAssertFalse((checkout.semanticSurfaces ?? []).contains { $0.contains("predicate(") })
        XCTAssertFalse((checkout.semanticSurfaces ?? []).contains { $0.contains("target_ref") })
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
        var arguments = try Self.planSourceArguments(for: plan).argumentValues
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
                .action(try ActionStep(
                    command: .activate(.predicate(.label("Checkout"))),
                    expectationPolicy: .expect(ActionExpectation(predicate: .exists(.label("Done")), timeout: 1)))),
            ]
        )
        let plan = try HeistPlan(
            name: "shop",
            definitions: [definition],
            body: [.warn(WarnStep(message: "ready"))]
        )
        var arguments = try Self.planSourceArguments(for: plan).argumentValues
        arguments["heist"] = .string("checkout")

        let response = try await fence.execute(
            command: .describeHeist,
            arguments: TheFence.CommandArgumentEnvelope(values: arguments)
        )

        guard case .heistDescription(let description) = response else {
            return XCTFail("Expected heistDescription response, got \(response)")
        }
        XCTAssertEqual(description.name, "checkout")
        XCTAssertEqual(description.role, .capability)
        XCTAssertEqual(description.semanticSurface.actionCommands, ["activate"])
        XCTAssertEqual(description.semanticSurface.expectations, [#"exists(predicate(label="Done"))"#])
        XCTAssertEqual(description.semanticSurface.targetPredicates, [
            #"predicate(label="Checkout")"#,
            #"predicate(label="Done")"#,
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
                            .expect(.exists(.label("Done")), timeout: .seconds(1))
                    }

                    Warn("ready")
                }
                """),
            ])
        )

        guard case .heistDescription(let description) = response else {
            return XCTFail("Expected heistDescription response, got \(response)")
        }
        XCTAssertEqual(description.name, "checkout")
        XCTAssertEqual(description.semanticSurface.actionCommands, ["activate"])
        XCTAssertEqual(description.semanticSurface.targetPredicates, [
            #"predicate(label="Checkout")"#,
            #"predicate(label="Done")"#,
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
        var arguments = try Self.planSourceArguments(for: plan).argumentValues
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

    func testHeistExecutionResponseFailureDrivenByFailedStepNotFailedIndex() throws {
        // A failed child must mark the response as failure even when the top-level
        // abort location is carried by the receipt instead of an index.
        let childPath = "$.body[0].heist.body[0]"
        let child = HeistExecutionStepResult.failed(
            path: childPath,
            kind: .action,
            durationMs: 5,
            evidence: .action(.dispatch(
                dispatchResult: ActionResult.failure(
                    method: .activate,
                    errorKind: .actionFailed,
                    message: "boom")
            )),
            failure: HeistFailureDetail(
                category: .action,
                contract: "activate command succeeds",
                observed: "boom"
            )
        )
        let result = HeistExecutionResult(
            steps: [
                .childAborted(
                    path: "$.body[0]",
                    kind: .heist,
                    durationMs: 5,
                    evidence: .invocation(.heist(
                        name: "heist",
                        childFailedPath: childPath
                    )),
                    failure: HeistFailureDetail(
                        category: .invocation,
                        contract: "heist body completes without failure",
                        observed: "child failed at \(childPath)"
                    ),
                    abortedAtChildPath: childPath,
                    children: [child]
                ),
            ],
            durationMs: 5,
            abortedAtPath: childPath
        )
        let response = FenceResponse.heistExecution(
            plan: try HeistPlan(body: [.warn(WarnStep(message: "x"))]),
            result: result,
            accessibilityTrace: nil
        )
        XCTAssertTrue(response.isFailure)
    }

    /// Build a lower-level run_heist argument envelope from the canonical JSON
    /// object fields. This is intentionally not the public MCP authoring shape.
    private static func inlineArguments(for plan: HeistPlan) throws -> TheFence.CommandArgumentEnvelope {
        let data = try JSONEncoder().encode(plan)
        guard case .object(let fields) = try JSONDecoder().decode(HeistValue.self, from: data) else {
            throw XCTSkip("plan did not encode to a JSON object")
        }
        return TheFence.CommandArgumentEnvelope(values: fields)
    }

    private static func planSourceArguments(for plan: HeistPlan) throws -> TheFence.CommandArgumentEnvelope {
        TheFence.CommandArgumentEnvelope(values: [
            "plan": .string(try plan.canonicalSwiftDSL()),
        ])
    }

    private static func inlineArguments(for plan: HeistPlanAdmissionCandidate) throws -> TheFence.CommandArgumentEnvelope {
        let data = try JSONEncoder().encode(plan)
        guard case .object(let fields) = try JSONDecoder().decode(HeistValue.self, from: data) else {
            throw XCTSkip("plan did not encode to a JSON object")
        }
        return TheFence.CommandArgumentEnvelope(values: fields)
    }

    // MARK: - Typed Argument Parsing

    func testCommandArgumentEnvelopeReadsTypedScalarValues() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            FenceParameterKey.inlineData.rawValue: .bool(true),
            FenceParameterKey.ordinal.rawValue: .int(3),
            FenceParameterKey.duration.rawValue: .double(2.5),
            FenceParameterKey.requestId.rawValue: .string("abc123"),
        ])

        XCTAssertEqual(try envelope.schemaBoolean(.inlineData), true)
        XCTAssertEqual(try envelope.schemaInteger(.ordinal), 3)
        XCTAssertEqual(try envelope.schemaNumber(.duration), 2.5)
        XCTAssertEqual(envelope.observedDescription(for: .requestId), "string \"abc123\"")
        XCTAssertNil(envelope.observedDescription(forUnknownKey: "missing"))
    }

    func testCommandArgumentEnvelopeReadsNestedTypedValues() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            FenceParameterKey.target.rawValue: .object([
                FenceParameterKey.label.rawValue: .string("Pay"),
                FenceParameterKey.traits.rawValue: .array([.string("button"), .string("selected")]),
            ]),
            FenceParameterKey.elementUnitPoints.rawValue: .array([
                .object([FenceParameterKey.x.rawValue: .double(0.25), FenceParameterKey.y.rawValue: .double(0.75)]),
                .object([FenceParameterKey.x.rawValue: .double(0.5), FenceParameterKey.y.rawValue: .double(0.5)]),
            ]),
        ])

        let object = try XCTUnwrap(try envelope.schemaDictionary(.target))
        XCTAssertEqual(try object.schemaString(.label), "Pay")
        XCTAssertEqual(try object.schemaStringArray(.traits), ["button", "selected"])

        guard case .array(let array)? = envelope.value(for: .elementUnitPoints) else {
            return XCTFail("Expected typed array")
        }
        XCTAssertEqual(array.count, 2)
        guard case .object(let firstObject) = array[0] else {
            return XCTFail("Expected typed object")
        }
        let first = TheFence.CommandArgumentEnvelope(
            values: firstObject,
            fieldPrefix: "\(FenceParameterKey.elementUnitPoints.rawValue)[0]"
        )
        XCTAssertEqual(try first.schemaNumber(.x), 0.25)
        XCTAssertEqual(try first.schemaNumber(.y), 0.75)
        guard case .object(let secondObject) = array[1] else {
            return XCTFail("Expected typed object")
        }
        let second = TheFence.CommandArgumentEnvelope(
            values: secondObject,
            fieldPrefix: "\(FenceParameterKey.elementUnitPoints.rawValue)[1]"
        )
        XCTAssertEqual(try second.schemaNumber(.x), 0.5)
        XCTAssertEqual(try second.schemaNumber(.y), 0.5)
    }

    func testCommandArgumentEnvelopeReadsNestedTypedObjects() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            FenceParameterKey.subtree.rawValue: .object([
                FenceParameterKey.element.rawValue: .object([
                    FenceParameterKey.label.rawValue: .string("Pay"),
                    FenceParameterKey.traits.rawValue: .array([.string("button"), .string("selected")]),
                ]),
                FenceParameterKey.container.rawValue: .object([
                    FenceParameterKey.type.rawValue: .string("scrollable"),
                    FenceParameterKey.isModalBoundary.rawValue: .bool(true),
                    FenceParameterKey.scale.rawValue: .double(0.5),
                ]),
                FenceParameterKey.ordinal.rawValue: .int(2),
            ]),
        ])

        let subtree = try XCTUnwrap(try envelope.schemaDictionary(.subtree))
        let element = try XCTUnwrap(try subtree.schemaDictionary(.element))
        let container = try XCTUnwrap(try subtree.schemaDictionary(.container))
        XCTAssertEqual(try subtree.schemaInteger(.ordinal), 2)
        XCTAssertEqual(try element.schemaString(.label), "Pay")
        XCTAssertEqual(try element.schemaStringArray(.traits), ["button", "selected"])
        XCTAssertEqual(try container.schemaEnum(.type, as: ContainerTypeName.self), .scrollable)
        XCTAssertEqual(try container.schemaBoolean(.isModalBoundary), true)
        XCTAssertEqual(try container.schemaNumber(.scale), 0.5)
    }

    func testCommandArgumentEnvelopeNestedSchemaErrorsUseQualifiedFields() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            FenceParameterKey.subtree.rawValue: .object([
                FenceParameterKey.element.rawValue: .object([
                    FenceParameterKey.traits.rawValue: .array([.int(7)]),
                ]),
            ]),
        ])

        let subtree = try XCTUnwrap(try envelope.schemaDictionary(.subtree))
        let element = try XCTUnwrap(try subtree.schemaDictionary(.element))
        XCTAssertThrowsError(try element.schemaStringArray(.traits)) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for subtree.element.traits[0]: observed integer 7; expected string"
            )
        }
    }

    func testCommandArgumentEnvelopeReadsTypedObjectArrays() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            FenceParameterKey.elementUnitPoints.rawValue: .array([
                .object([FenceParameterKey.x.rawValue: .double(0.25), FenceParameterKey.y.rawValue: .double(0.75)]),
                .object([FenceParameterKey.x.rawValue: .int(1), FenceParameterKey.y.rawValue: .int(2)]),
            ]),
        ])

        let points = try envelope.requiredSchemaObjectArray(.elementUnitPoints)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(try points[0].requiredSchemaNumber(.x), 0.25)
        XCTAssertEqual(try points[0].requiredSchemaNumber(.y), 0.75)
        XCTAssertEqual(try points[1].requiredSchemaNumber(.x), 1)
        XCTAssertEqual(try points[1].requiredSchemaNumber(.y), 2)
    }

    func testCommandArgumentEnvelopeObjectArrayErrorsUseIndexedFields() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            FenceParameterKey.elementUnitPoints.rawValue: .array([
                .object([FenceParameterKey.x.rawValue: .string("bad")]),
            ]),
        ])

        let points = try envelope.requiredSchemaObjectArray(.elementUnitPoints)
        XCTAssertThrowsError(try points[0].requiredSchemaNumber(.x)) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for elementUnitPoints[0].x: observed string \"bad\"; expected number"
            )
        }
    }

    func testCommandArgumentEnvelopeReadsRequiredEnum() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            FenceParameterKey.direction.rawValue: .string("up"),
        ])

        XCTAssertEqual(
            try envelope.requiredSchemaEnum(.direction, as: SwipeDirection.self),
            .up
        )
    }

    func testCommandArgumentEnvelopeRequiredEnumErrorsUseExpectedCases() throws {
        let missing = TheFence.CommandArgumentEnvelope(values: [:])
        XCTAssertThrowsError(try missing.requiredSchemaEnum(.direction, as: SwipeDirection.self)) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for direction: observed missing; expected enum one of up, down, left, right"
            )
        }

        let invalid = TheFence.CommandArgumentEnvelope(values: [
            FenceParameterKey.direction.rawValue: .string("diagonal"),
        ])
        XCTAssertThrowsError(try invalid.requiredSchemaEnum(.direction, as: SwipeDirection.self)) { error in
            XCTAssertEqual(
                (error as? SchemaValidationError)?.message,
                "schema validation failed for direction: observed string \"diagonal\"; expected enum one of up, down, left, right"
            )
        }
    }

    @ButtonHeistActor
    func testElementTargetWithIdentifier() async throws {
        guard let target = try decodedElementTarget(target: targetValue(identifier: "myButton")),
              case .predicate(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertEqual(matcher.checks, [.identifier(.exact("myButton"))])
    }

    @ButtonHeistActor
    func testElementTargetRejectsHeistIdField() async throws {
        // heistId is no longer a targeting field — it is rejected as unknown.
        XCTAssertThrowsError(try decodedElementTarget(target: legacyHeistIdTargetValue("button_save")))
    }

    @ButtonHeistActor
    func testElementTargetWithMatcherFields() async throws {
        guard let target = try decodedElementTarget(target: targetValue(label: "Save", traits: ["button"])),
              case .predicate(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertEqual(matcher.checks, [
            .label(.exact("Save")),
            .traits([.button]),
        ])
    }

    @ButtonHeistActor
    func testElementTargetPublicPayloadShapesDecodeThroughSamePath() async throws {
        let expected = ElementTarget.predicate(
            ElementPredicate(label: "Save", identifier: "saveButton", traits: [.button]),
            ordinal: 1
        )
        let cliBuiltShape = targetValue(
            label: "Save",
            identifier: "saveButton",
            traits: ["button"],
            ordinal: 1
        )
        let jsonMCPShape = elementTargetValue([
            "checks": .array([
                .object([
                    "kind": .string("label"),
                    "match": stringMatchValue(mode: "exact", value: "Save"),
                ]),
                .object([
                    "kind": .string("identifier"),
                    "match": stringMatchValue(mode: "exact", value: "saveButton"),
                ]),
                .object([
                    "kind": .string("traits"),
                    "values": .array([.string("button")]),
                ]),
            ]),
            "ordinal": .int(1),
        ])

        XCTAssertEqual(try decodedElementTarget(target: cliBuiltShape), expected)
        XCTAssertEqual(try decodedElementTarget(target: jsonMCPShape), expected)
    }

    @ButtonHeistActor
    func testElementTargetRejectsUnknownTargetField() async throws {
        XCTAssertThrowsError(
            try decodedElementTarget(
                target: elementTargetValue([
                    "label": stringMatchValue(mode: "exact", value: "Save"),
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
    func testElementTargetWithOrdinal() async throws {
        guard let target = try decodedElementTarget(target: targetValue(label: "Save", ordinal: 2)),
              case .predicate(let matcher, let ordinal) = target else {
            return XCTFail("Expected .matcher with ordinal")
        }
        XCTAssertEqual(matcher.checks, [.label(.exact("Save"))])
        XCTAssertEqual(ordinal, 2)
    }

    @ButtonHeistActor
    func testRequestTargetRejectsNegativeOrdinal() async {
        await assertOperationValidationError(
            command: .activate,
            arguments: ["target": targetValue(label: "Save", ordinal: -1)],
            equals: "schema validation failed for target.ordinal: observed integer -1; expected ordinal must be non-negative, got -1"
        )
    }

    @ButtonHeistActor
    func testElementTargetWithoutOrdinal() async throws {
        guard let target = try decodedElementTarget(target: targetValue(label: "Save")),
              case .predicate(_, let ordinal) = target else {
            return XCTFail("Expected .matcher")
        }
        XCTAssertNil(ordinal)
    }

    @ButtonHeistActor
    func testElementTargetMissing() async throws {
        XCTAssertNil(try decodedElementTarget())
    }

    // MARK: - Schema Validation Diagnostics

    @ButtonHeistActor
    func testSchemaValidationReportsBadFieldType() async {
        await assertOperationValidationError(
            command: .typeText,
            arguments: ["text": .int(3)],
            equals: "schema validation failed for text: observed integer 3; expected string"
        )
    }

    @ButtonHeistActor
    func testSchemaValidationReportsBadCoercedValue() async {
        await assertOperationValidationError(
            command: .wait,
            arguments: ["timeout": .string("forever")],
            equals: "schema validation failed for timeout: observed string \"forever\"; expected number"
        )
    }

    // MARK: - Gesture Validation

    @ButtonHeistActor
    func testOneFingerTapMissingTarget() async {
        await assertOperationValidationError(
            command: .oneFingerTap,
            contains: "point requires element, element with unitPoint, or ScreenPoint"
        )
    }

    @ButtonHeistActor
    func testOneFingerTapWithCoordinatesPassesValidation() async {
        await assertOperationPassesValidation(
            command: .oneFingerTap,
            arguments: ["point": .object(["x": .double(100.0), "y": .double(200.0)])]
        )
    }

    @ButtonHeistActor
    func testOneFingerTapRejectsPartialCoordinates() async {
        await assertOperationValidationError(
            command: .oneFingerTap,
            arguments: ["point": .object(["x": .double(100.0)])],
            equals: "schema validation failed for point.y: observed missing; expected number"
        )
    }

    @ButtonHeistActor
    func testOneFingerTapRejectsOutOfRangeUnitPoint() async {
        await assertOperationValidationError(
            command: .oneFingerTap,
            arguments: [
                "element": targetValue(identifier: "myButton"),
                "unitPoint": .object(["x": .double(1.2), "y": .double(0.5)]),
            ],
            equals: "schema validation failed for unitPoint.x: observed number 1.2; expected number in 0...1"
        )
    }

    @ButtonHeistActor
    func testOneFingerTapRejectsNaNCoordinate() async {
        await assertOperationValidationError(
            command: .oneFingerTap,
            arguments: ["point": .object(["x": .double(Double.nan), "y": .double(200.0)])],
            equals: "schema validation failed for point.x: observed number nan; expected number"
        )
    }

    @ButtonHeistActor
    func testOneFingerTapRejectsInfiniteCoordinate() async {
        await assertOperationValidationError(
            command: .oneFingerTap,
            arguments: ["point": .object(["x": .double(Double.infinity), "y": .double(200.0)])],
            equals: "schema validation failed for point.x: observed number inf; expected number"
        )
    }

    @ButtonHeistActor
    func testOneFingerTapWithIdentifierPassesValidation() async {
        await assertOperationPassesValidation(
            command: .oneFingerTap,
            arguments: ["element": targetValue(identifier: "myButton")]
        )
    }

    @ButtonHeistActor
    func testDirectTapReturnsHeistExecutionBeforeFormatting() async throws {
        let (fence, _) = makeConnectedFence()

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
    func testGestureTargetRejectsHeistIdAndMatcher() async {
        await assertOperationValidationError(
            command: .oneFingerTap,
            arguments: [
                "element": elementTargetValue([
                    "heistId": .string("button_save"),
                    "label": stringMatchValue(mode: "exact", value: "Save"),
                ]),
            ],
            contains: "Unknown element target field \"heistId\""
        )
    }

    @ButtonHeistActor
    func testLongPressMissingTarget() async {
        await assertOperationValidationError(
            command: .longPress,
            contains: "point requires element, element with unitPoint, or ScreenPoint"
        )
    }

    @ButtonHeistActor
    func testLongPressWithCoordinatesPassesValidation() async {
        await assertOperationPassesValidation(
            command: .longPress,
            arguments: ["point": .object(["x": .double(50.0), "y": .double(50.0)])]
        )
    }

    @ButtonHeistActor
    func testLongPressRejectsNegativeDuration() async {
        await assertOperationValidationError(
            command: .longPress,
            arguments: [
                "point": .object(["x": .double(50.0), "y": .double(50.0)]),
                "duration": .double(-1.0),
            ],
            equals: "schema validation failed for duration: observed number -1.0; expected number > 0"
        )
    }

    @ButtonHeistActor
    func testLongPressRejectsOversizedDurationBeforeExecution() async {
        await assertOperationValidationError(
            command: .longPress,
            arguments: [
                "point": .object(["x": .double(50.0), "y": .double(50.0)]),
                "duration": .double(61.0),
            ],
            equals: "schema validation failed for duration: observed number 61.0; expected number in 0...60.0"
        )
    }

    @ButtonHeistActor
    func testSwipeInvalidDirection() async {
        await assertOperationValidationError(
            command: .swipe,
            arguments: [
                "pointDirection": .object([
                    "start": .object(["x": .double(10.0), "y": .double(20.0)]),
                    "direction": .string("diagonal"),
                ]),
            ],
            equals: "schema validation failed for pointDirection.direction: observed string \"diagonal\"; " +
                "expected enum one of up, down, left, right"
        )
    }

    @ButtonHeistActor
    func testSwipeDirectionWithoutTargetOrCoordinatesIsRejected() async {
        await assertOperationValidationError(
            command: .swipe,
            arguments: [
                "pointDirection": .object(["direction": .string("up")]),
            ],
            equals: "schema validation failed for pointDirection.start: observed missing; expected object"
        )
    }

    @ButtonHeistActor
    func testSwipeRejectsPartialStartCoordinates() async {
        await assertOperationValidationError(
            command: .swipe,
            arguments: [
                "pointToPoint": .object([
                    "start": .object(["x": .double(10.0)]),
                    "end": .object(["x": .double(100.0), "y": .double(200.0)]),
                ]),
            ],
            equals: "schema validation failed for pointToPoint.start.y: observed missing; expected number"
        )
    }

    @ButtonHeistActor
    func testSwipeWithUnitPointsPassesValidation() async {
        await assertOperationPassesValidation(
            command: .swipe,
            arguments: [
                "elementUnitPoints": .object([
                    "element": targetValue(identifier: "row_5"),
                    "start": .object(["x": .double(0.8), "y": .double(0.5)]),
                    "end": .object(["x": .double(0.2), "y": .double(0.5)]),
                ]),
            ]
        )
    }

    @ButtonHeistActor
    func testSwipeUnitPointsRejectOutOfRangeCoordinate() async {
        await assertOperationValidationError(
            command: .swipe,
            arguments: [
                "elementUnitPoints": .object([
                    "element": targetValue(identifier: "row_5"),
                    "start": .object(["x": .double(1.2), "y": .double(0.5)]),
                    "end": .object(["x": .double(0.2), "y": .double(0.5)]),
                ]),
            ],
            equals: "schema validation failed for elementUnitPoints.start.x: observed number 1.2; expected number in 0...1"
        )
    }

    @ButtonHeistActor
    func testSwipeDirectionWithElementPassesValidation() async {
        await assertOperationPassesValidation(
            command: .swipe,
            arguments: [
                "elementDirection": .object([
                    "element": targetValue(identifier: "row_5"),
                    "direction": .string("left"),
                ]),
            ]
        )
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
              case .swipe(let target) = message,
              case .elementDirection(let elementTarget, let direction) = target.selection else {
            XCTFail("Expected element direction swipe to lower to element direction swipe")
            return
        }
        XCTAssertEqual(elementTarget, .predicate(ElementPredicate(identifier: "row_5")))
        XCTAssertEqual(direction, .left)
    }

    @ButtonHeistActor
    func testSwipeRejectsMixedIntentObjects() async {
        await assertOperationValidationError(
            command: .swipe,
            arguments: [
                "pointDirection": .object([
                    "start": .object(["x": .double(10.0), "y": .double(20.0)]),
                    "direction": .string("down"),
                ]),
                "pointToPoint": .object([
                    "start": .object(["x": .double(10.0), "y": .double(20.0)]),
                    "end": .object(["x": .double(30.0), "y": .double(40.0)]),
                ]),
            ],
            equals: "swipe accepts exactly one gesture intent"
        )
    }

    @ButtonHeistActor
    func testDragMissingEndCoordinates() async {
        await assertOperationValidationError(
            command: .drag,
            arguments: [
                "pointToPoint": .object([
                    "start": .object(["x": .double(10.0), "y": .double(10.0)]),
                ]),
            ],
            equals: "schema validation failed for pointToPoint.end: observed missing; expected object"
        )
    }

    @ButtonHeistActor
    func testDragWithoutStartTargetIsRejected() async {
        await assertOperationValidationError(
            command: .drag,
            arguments: [
                "pointToPoint": .object([
                    "end": .object(["x": .double(100.0), "y": .double(200.0)]),
                ]),
            ],
            equals: "schema validation failed for pointToPoint.start: observed missing; expected object"
        )
    }

    @ButtonHeistActor
    func testDragWithElementTargetAndEndCoordinatesPassesValidation() async {
        await assertOperationPassesValidation(
            command: .drag,
            arguments: [
                "elementToPoint": .object([
                    "element": targetValue(identifier: "source"),
                    "end": .object(["x": .double(100.0), "y": .double(200.0)]),
                ]),
            ]
        )
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
              case .drag(let target) = message else {
            XCTFail("Expected drag message")
            return
        }
        XCTAssertEqual(target.start, .coordinate(ScreenPoint(x: 100.0, y: 300.0)))
        XCTAssertEqual(target.end, ScreenPoint(x: 300.0, y: 600.0))
    }

    @ButtonHeistActor
    func testDragRejectsMixedIntentObjects() async {
        await assertOperationValidationError(
            command: .drag,
            arguments: [
                "elementToPoint": .object([
                    "element": targetValue(identifier: "source"),
                    "end": .object(["x": .double(100.0), "y": .double(200.0)]),
                ]),
                "pointToPoint": .object([
                    "start": .object(["x": .double(10.0), "y": .double(20.0)]),
                    "end": .object(["x": .double(100.0), "y": .double(200.0)]),
                ]),
            ],
            equals: "drag accepts exactly one gesture intent"
        )
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
                    "type": .string("change"),
                    "scopes": .array([.object(["type": .string("elements")])]),
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
    func testScrollDefaultsDirection() async {
        await assertPassesValidation(
            command: .scroll,
            arguments: ["target": targetValue(identifier: "scrollView")]
        )
    }

    @ButtonHeistActor
    func testScrollInvalidDirection() async {
        await assertValidationError(
            command: .scroll,
            arguments: ["target": targetValue(identifier: "scrollView"), "direction": .string("diagonal")],
            equals: "schema validation failed for direction: observed string \"diagonal\"; expected enum one of up, down, left, right"
        )
    }

    @ButtonHeistActor
    func testScrollAllowsMissingElement() async {
        await assertPassesValidation(
            command: .scroll,
            arguments: ["direction": .string("down")]
        )
    }

    @ButtonHeistActor
    func testScrollValidPassesValidation() async {
        await assertPassesValidation(
            command: .scroll,
            arguments: ["direction": .string("down"), "target": targetValue(identifier: "scrollView")]
        )
    }

    @ButtonHeistActor
    func testScrollRejectsContainerObject() async {
        await assertValidationError(
            command: .scroll,
            arguments: ["container": .object(["unexpected": .string("main_scroll")])],
            contains: "schema validation failed for container"
        )
    }

    @ButtonHeistActor
    func testScrollRejectsPublicContainerName() async {
        await assertValidationError(
            command: .scroll,
            arguments: ["containerName": .string("main_scroll")],
            contains: "schema validation failed for containerName"
        )
    }

    @ButtonHeistActor
    func testScrollAllowsContainerArgument() async {
        await assertPassesValidation(
            command: .scroll,
            arguments: ["direction": .string("down"), "container": .string("main_scroll")]
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeRejectsPublicContainerName() async {
        await assertValidationError(
            command: .scrollToEdge,
            arguments: ["edge": .string("bottom"), "containerName": .string("main_scroll")],
            contains: "schema validation failed for containerName"
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeAllowsContainerArgument() async {
        await assertPassesValidation(
            command: .scrollToEdge,
            arguments: ["edge": .string("bottom"), "container": .string("main_scroll")]
        )
    }

    @ButtonHeistActor
    func testScrollDefaultsDirectionAndAllowsMissingTarget() async {
        await assertPassesValidation(
            command: .scroll
        )
    }

    @ButtonHeistActor
    func testScrollToVisibleMissingElement() async {
        await assertContractError(
            command: .scrollToVisible,
            contains: [
                "scroll_to_visible request contract failed: missing target",
                "requires target object",
                "Next: get_interface()",
            ],
            errorCode: .requestMissingTarget,
            nextCommand: "get_interface()"
        )
    }

    @ButtonHeistActor
    func testScrollToVisibleValidPassesValidation() async {
        await assertPassesValidation(
            command: .scrollToVisible,
            arguments: ["target": targetValue(identifier: "targetElement")]
        )
    }

    @ButtonHeistActor
    func testScrollToVisibleIdentifierTargetPassesValidation() async {
        await assertPassesValidation(
            command: .scrollToVisible,
            arguments: ["target": targetValue(identifier: "targetElement")]
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeDefaultsEdge() async {
        await assertPassesValidation(
            command: .scrollToEdge,
            arguments: ["target": targetValue(identifier: "scrollView")]
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeInvalidEdge() async {
        await assertValidationError(
            command: .scrollToEdge,
            arguments: ["target": targetValue(identifier: "scrollView"), "edge": .string("middle")],
            equals: "schema validation failed for edge: observed string \"middle\"; expected enum one of top, bottom, left, right"
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeAllowsMissingTarget() async {
        await assertPassesValidation(
            command: .scrollToEdge,
            arguments: ["edge": .string("bottom")]
        )
    }

    @ButtonHeistActor
    func testScrollToEdgeValidPassesValidation() async {
        await assertPassesValidation(
            command: .scrollToEdge,
            arguments: ["edge": .string("bottom"), "target": targetValue(identifier: "scrollView")]
        )
    }

    // MARK: - Accessibility Action Validation

    @ButtonHeistActor
    func testActivateMissingElement() async {
        await assertContractError(
            command: .activate,
            contains: [
                "activate request contract failed: missing target",
                "requires target object",
                "Next: get_interface()",
            ],
            errorCode: .requestMissingTarget,
            nextCommand: "get_interface()"
        )
    }

    @ButtonHeistActor
    func testActivateWithElementPassesValidation() async {
        await assertPassesValidation(
            command: .activate,
            arguments: ["target": targetValue(identifier: "myElement")]
        )
    }

    @ButtonHeistActor
    func testRotorMissingElement() async {
        await assertContractError(
            command: .rotor,
            arguments: ["rotor": .string("Errors")],
            contains: [
                "rotor request contract failed: missing target",
                "requires target object",
                "Next: get_interface()",
            ],
            errorCode: .requestMissingTarget,
            nextCommand: "get_interface()"
        )
    }

    @ButtonHeistActor
    func testRotorNegativeIndex() async {
        await assertValidationError(
            command: .rotor,
            arguments: ["target": targetValue(identifier: "myElement"), "rotorIndex": .int(-1)],
            equals: "schema validation failed for rotorIndex: observed integer -1; expected integer >= 0"
        )
    }

    @ButtonHeistActor
    func testRotorRejectsMixedSelectorShape() async {
        await assertValidationError(
            command: .rotor,
            arguments: [
                "target": targetValue(identifier: "myElement"),
                "rotor": .string("Errors"),
                "rotorIndex": .int(1),
            ],
            contains: "either rotor or rotorIndex"
        )
    }

    @ButtonHeistActor
    func testRotorInvalidDirection() async {
        await assertValidationError(
            command: .rotor,
            arguments: ["target": targetValue(identifier: "myElement"), "direction": .string("sideways")],
            equals: "schema validation failed for direction: observed string \"sideways\"; expected enum one of next, previous"
        )
    }

    @ButtonHeistActor
    func testRotorRejectsLegacyLooseContinuationFields() async {
        await assertValidationError(
            command: .rotor,
            arguments: ["target": targetValue(identifier: "myElement"), "currentTextStartOffset": .int(4)],
            contains: "schema validation failed for currentTextStartOffset:"
        )
    }

    @ButtonHeistActor
    func testRotorValidPassesValidation() async {
        await assertPassesValidation(
            command: .rotor,
            arguments: ["target": targetValue(identifier: "myElement"), "rotor": .string("Errors")]
        )
    }

    @ButtonHeistActor
    func testActivateWithCustomActionDispatches() async {
        await assertPassesValidation(
            command: .activate,
            arguments: ["target": targetValue(identifier: "myElement"), "action": .string("Delete")]
        )
    }

    @ButtonHeistActor
    func testActivateWithIncrementDispatches() async {
        await assertPassesValidation(
            command: .activate,
            arguments: ["target": targetValue(identifier: "myElement"), "action": .string("increment")]
        )
    }

    @ButtonHeistActor
    func testActivateWithDecrementDispatches() async {
        await assertPassesValidation(
            command: .activate,
            arguments: ["target": targetValue(identifier: "myElement"), "action": .string("decrement")]
        )
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

    @ButtonHeistActor
    func testActivateRejectsEmptyActionNameAtRequestBoundary() async {
        await assertValidationError(
            command: .activate,
            arguments: ["target": targetValue(identifier: "myElement"), "action": .string("")],
            equals: "schema validation failed for action: observed string \"\"; expected non-empty string"
        )
    }

    // MARK: - Text Input Validation

    @ButtonHeistActor
    func testTypeTextMissingBothFields() async {
        await assertValidationError(
            command: .typeText,
            equals: "schema validation failed for text: observed missing; expected string"
        )
    }

    @ButtonHeistActor
    func testTypeTextRejectsEmptyText() async {
        await assertValidationError(
            command: .typeText,
            arguments: ["text": .string("")],
            equals: "schema validation failed for text: observed string \"\"; expected non-empty string"
        )
    }

    @ButtonHeistActor
    func testTypeTextWithTextPassesValidation() async {
        await assertPassesValidation(
            command: .typeText,
            arguments: ["text": .string("hello")]
        )
    }

    @ButtonHeistActor
    func testTypeTextWithEmptyTextAndReplacingExistingPassesValidation() async {
        await assertPassesValidation(
            command: .typeText,
            arguments: [
                "text": .string(""),
                "replacingExisting": .bool(true),
            ]
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
              case .typeText(let target) = message else {
            return XCTFail("Expected typeText message, got \(String(describing: mockConn.sent.sentPlanMessages.last))")
        }
        XCTAssertEqual(target.text, "hello")
        XCTAssertEqual(target.elementTarget, .predicate(ElementPredicate(identifier: "search_field")))
        XCTAssertFalse(target.replacingExisting)
    }

    @ButtonHeistActor
    func testTypeTextReplacingExistingTypedPayloadDispatchesCanonicalWireMessage() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(command: .typeText, values: [
            "text": .string(""),
            "target": targetValue(identifier: "search_field"),
            "replacingExisting": .bool(true),
        ])

        XCTAssertNotNil(response.leafAction, "Expected single-step action response, got \(response)")
        guard let message = mockConn.sent.sentPlanMessages.last,
              case .typeText(let target) = message else {
            return XCTFail("Expected typeText message, got \(String(describing: mockConn.sent.sentPlanMessages.last))")
        }
        XCTAssertEqual(target.text, "")
        XCTAssertEqual(target.elementTarget, .predicate(ElementPredicate(identifier: "search_field")))
        XCTAssertTrue(target.replacingExisting)
    }

    @ButtonHeistActor
    func testTypeTextRejectsNonStringTextBeforeDispatch() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(command: .typeText, values: [
            "text": .int(3),
        ])

        guard case .error(let failure) = response else {
            return XCTFail("Expected error response, got \(response)")
        }
        XCTAssertEqual(failure.message, "schema validation failed for text: observed integer 3; expected string")
        XCTAssertTrue(mockConn.sent.isEmpty)
    }

    @ButtonHeistActor
    func testEditActionMissingAction() async {
        await assertValidationError(
            command: .editAction,
            equals: "schema validation failed for action: observed missing; expected enum one of copy, paste, cut, select, selectAll, delete"
        )
    }

    @ButtonHeistActor
    func testEditActionValidPassesValidation() async {
        await assertPassesValidation(
            command: .editAction,
            arguments: ["action": .string("copy")]
        )
    }

    @ButtonHeistActor
    func testEditActionDeletePassesValidation() async {
        await assertPassesValidation(
            command: .editAction,
            arguments: ["action": .string("delete")]
        )
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
    func testSetPasteboardMissingText() async {
        await assertValidationError(
            command: .setPasteboard,
            equals: "schema validation failed for text: observed missing; expected string"
        )
    }

    @ButtonHeistActor
    func testSetPasteboardRejectsEmptyTextBeforeRuntimeDispatch() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(command: .setPasteboard, values: ["text": .string("")])

        guard case .error(let failure) = response else {
            return XCTFail("Expected error response, got \(response)")
        }
        XCTAssertEqual(failure.message, "schema validation failed for text: observed string \"\"; expected non-empty string")
        XCTAssertTrue(mockConn.sent.isEmpty)
    }

    @ButtonHeistActor
    func testSetPasteboardWithTextPassesValidation() async {
        await assertPassesValidation(
            command: .setPasteboard,
            arguments: ["text": .string("hello")]
        )
    }

    @ButtonHeistActor
    func testGetPasteboardPassesValidation() async {
        await assertPassesValidation(
            command: .getPasteboard
        )
    }

    @ButtonHeistActor
    func testGetPasteboardRejectsExpectationBecauseItIsARead() async {
        await assertValidationError(
            command: .getPasteboard,
            arguments: ["expect": .object([
                "type": .string("change"),
                "scopes": .array([.object(["type": .string("screen")])]),
            ])],
            contains: "valid get_pasteboard parameter"
        )
    }

    @ButtonHeistActor
    func testPureReadCommandsRemainDirectWireMessages() async throws {
        let (interfaceFence, interfaceConn) = makeConnectedFence()
        _ = try await interfaceFence.execute(command: .getInterface)
        guard case .requestInterface = interfaceConn.sent.last?.0 else {
            return XCTFail("Expected get_interface to send requestInterface, got \(String(describing: interfaceConn.sent.last?.0))")
        }

        let (pasteboardFence, pasteboardConn) = makeConnectedFence()
        _ = try await pasteboardFence.execute(command: .getPasteboard)
        guard case .getPasteboard = pasteboardConn.sent.last?.0 else {
            return XCTFail("Expected get_pasteboard to send getPasteboard, got \(String(describing: pasteboardConn.sent.last?.0))")
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
        mockConn.autoResponse = nil

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
        let (fence, _) = makeConnectedFence()
        do {
            let response = try await fence.execute(command: .wait, values: [:])
            if case .error(let failure) = response {
                XCTAssertTrue(
                    failure.message.contains("predicate"),
                    "Expected predicate error, got: \(failure.message)"
                )
            } else {
                XCTFail("Expected error response, got \(response)")
            }
        } catch let error as FenceError {
            XCTAssertTrue("\(error)".contains("predicate"), "Expected predicate error, got: \(error)")
        } catch {
            XCTFail("Unexpected throw: \(error)")
        }
    }

    @ButtonHeistActor
    func testWaitPresentWithLabelPassesValidation() async {
        await assertPassesValidation(
            command: .wait,
            arguments: ["predicate": .object([
                "type": .string("exists"),
                "element": elementPredicateValue(label: "Loading"),
            ])]
        )
    }

    @ButtonHeistActor
    func testWaitAbsentWithLabelPassesValidation() async {
        await assertPassesValidation(
            command: .wait,
            arguments: ["predicate": .object([
                "type": .string("missing"),
                "element": elementPredicateValue(label: "Loading"),
            ]), "timeout": .double(5.0)]
        )
    }

    @ButtonHeistActor
    func testWaitChangedScreenPassesValidation() async {
        await assertPassesValidation(
            command: .wait,
            arguments: ["predicate": .object([
                "type": .string("change"),
                "scopes": .array([.object(["type": .string("screen")])]),
            ])]
        )
    }

    @ButtonHeistActor
    func testWaitChangedWithTimeoutPassesValidation() async {
        await assertPassesValidation(
            command: .wait,
            arguments: [
                "predicate": .object([
                    "type": .string("change"),
                    "scopes": .array([.object(["type": .string("elements")])]),
                ]),
                "timeout": .double(5.0),
            ]
        )
    }

    @ButtonHeistActor
    func testWaitAllStatesPassesValidation() async {
        await assertPassesValidation(
            command: .wait,
            arguments: ["predicate": .object([
                "type": .string("all"),
                "states": .array([
                    .object(["type": .string("exists"), "element": elementPredicateValue(label: "Done")]),
                    .object(["type": .string("missing"), "element": elementPredicateValue(label: "Loading")]),
                ]),
            ])]
        )
    }

    @ButtonHeistActor
    func testWaitScreenChangedWhereClausePassesValidation() async {
        await assertPassesValidation(
            command: .wait,
            arguments: ["predicate": .object([
                "type": .string("change"),
                "scopes": .array([.object([
                    "type": .string("screen"),
                    "assertions": .array([.object([
                        "type": .string("exists"),
                        "element": elementPredicateValue(label: "Home"),
                    ])]),
                ])]),
            ])]
        )
    }

    @ButtonHeistActor
    func testWaitSendsCorrectMessage() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(command: .wait, values: [
            "predicate": .object([
                "type": .string("change"),
                "scopes": .array([.object(["type": .string("screen")])]),
            ]),
            "timeout": .double(8.0),
        ])
        guard let message = mockConn.sent.sentPlanMessages.last,
              case .wait(let target) = message else {
            return XCTFail("Expected wait message")
        }
        XCTAssertEqual(target.predicate, .change(.screen()))
        XCTAssertEqual(target.timeout, 8.0)
    }

    @ButtonHeistActor
    func testDirectWaitReturnsHeistExecutionBeforeFormatting() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.runtimeActionResponse = { message in
            guard case .wait = message else {
                return .actionResult(ActionResult.success(method: .activate))
            }
            return .actionResult(ActionResult.success(
                method: .wait,
                accessibilityTrace: .projectingForTests(.elementsChanged(.init(elementCount: 1, edits: ElementEdits())))
            ))
        }

        let response = try await fence.execute(command: .wait, values: [
            "predicate": .object([
                "type": .string("change"),
                "scopes": .array([.object(["type": .string("elements")])]),
            ]),
        ])

        assertDirectCommandHeistExecution(response, command: .wait, stepKind: .wait)
        let json = try publicJSONProbe(response).object()
        try json.assertMissing("method")
        try json.assertPresent("report")
    }

    @ButtonHeistActor
    func testWaitChangedRequiresTraceDerivedExpectationMatch() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.runtimeActionResponse = { message in
            guard case .wait = message else {
                return .actionResult(ActionResult.success(method: .activate))
            }
            return .actionResult(ActionResult.success(
                method: .wait,
                message: "expectation met after observed change",
                accessibilityTrace: .projectingForTests(.noChange(.init(elementCount: 1)))
            ))
        }

        let response = try await fence.execute(command: .wait, values: [
            "predicate": .object([
                "type": .string("change"),
                "scopes": .array([.object(["type": .string("elements")])]),
            ]),
        ])

        guard case .heistExecution(_, let result, _) = response else {
            return XCTFail("Expected heistExecution response, got \(response)")
        }
        let waitEvidence = try XCTUnwrap(result.steps.first?.waitEvidence)
        XCTAssertEqual(waitEvidence.expectation.met, false)
        XCTAssertEqual(waitEvidence.expectation.actual, "noChange")
    }

    @ButtonHeistActor
    func testWaitChangedTimeoutDoesNotClaimExpectationMet() async throws {
        let (fence, mockConn) = makeConnectedFence()
        mockConn.runtimeActionResponse = { message in
            guard case .wait = message else {
                return .actionResult(ActionResult.success(method: .activate))
            }
            return .actionResult(ActionResult.failure(
                method: .wait,
                errorKind: .timeout,
                message: "timed out after 0.2s — expectation not met",
                accessibilityTrace: .projectingForTests(.noChange(.init(elementCount: 1)))
            ))
        }

        let response = try await fence.execute(command: .wait, values: [
            "predicate": .object([
                "type": .string("change"),
                "scopes": .array([.object(["type": .string("elements")])]),
            ]),
            "timeout": .double(0.2),
        ])

        guard case .heistExecution(_, let result, _) = response else {
            return XCTFail("Expected heistExecution response, got \(response)")
        }
        let waitEvidence = try XCTUnwrap(result.steps.first?.waitEvidence)
        XCTAssertEqual(waitEvidence.expectation.met, false)
        XCTAssertEqual(waitEvidence.actionResult.message, "timed out after 0.2s — expectation not met")
    }

    @ButtonHeistActor
    func testInvalidExpectationRejectedAtRequestEdge() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(command: .activate, values: [
            "target": targetValue(identifier: "myElement"),
            "expect": .string("change"),
        ])

        guard case .error(let failure) = response else {
            return XCTFail("Expected .error response, got \(response)")
        }
        XCTAssertEqual(failure.message, "Invalid predicate type: expected object with a \"type\" discriminator")
        XCTAssertEqual(failure.details.code.knownCode, .requestInvalid)
        XCTAssertTrue(mockConn.sent.isEmpty)
    }

    @ButtonHeistActor
    func testActionExpectationExecutesAsServerSideExpectationStep() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let predicate = AccessibilityPredicate.exists(ElementPredicate(label: "Home"))
        let interface = makeReceiptTestInterface([
            TestHeistElementBuilder(label: "Home").build(),
        ])
        let trace = AccessibilityTrace.projectingForTests(.screenChanged(.init(
            elementCount: 1,
            newInterface: interface
        )))

        mockConn.runtimeActionResponse = { message in
            switch message {
            case .activate:
                return .actionResult(ActionResult.success(
                    method: .activate,
                    accessibilityTrace: trace
                ))
            case .wait:
                return .actionResult(ActionResult.success(
                    method: .wait,
                    message: "expectation met after observed change",
                    accessibilityTrace: trace
                ))
            default:
                return .actionResult(ActionResult.success(method: .activate))
            }
        }

        let response = try await fence.execute(command: .activate, values: [
            "target": targetValue(identifier: "myElement"),
            "expect": .object([
                "type": .string("exists"),
                "element": elementPredicateValue(label: "Home"),
            ]),
        ])

        // The action and its expectation cross the wire as one heist plan; the
        // expectation is a server-side step on the action, not a separate
        // client-issued wait round-trip.
        XCTAssertEqual(mockConn.sent.count, 1)
        guard case .action(let step)? = mockConn.sent.sentHeistPlan?.body.first else {
            return XCTFail("Expected a single action step, got \(String(describing: mockConn.sent.sentHeistPlan))")
        }
        XCTAssertEqual(step.expectationPolicy.expectedStep?.predicate, .predicate(predicate))

        guard let leaf = response.leafAction else {
            return XCTFail("Expected single-step action response, got \(response)")
        }
        XCTAssertEqual(leaf.expectation?.met, true)
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
            "type": .string("change"),
            "scopes": .array([.object(["type": .string("screen")])]),
        ]))
        XCTAssertEqual(result, .change(.screen()))
    }

    func testNormalizeToolCallRoutesWithoutParsingRequestArguments() throws {
        let result = TheFence.Command.routeToolCall(named: "perform")

        guard case .success(let command) = result else {
            return XCTFail("Expected successful command, got \(result)")
        }

        XCTAssertEqual(command, .perform)
    }

    func testNormalizeToolCallRejectsGranularActionCommands() {
        for tool in ["activate", "type_text", "wait", "swipe", "scroll"] {
            let result = TheFence.Command.routeToolCall(named: tool)

            guard case .failure(let error) = result else {
                return XCTFail("Expected non-MCP command rejection, got \(result)")
            }

            XCTAssertEqual(error.message, "Unknown tool: \(tool)")
        }
    }

    func testNormalizeToolCallRejectsNonMCPCommands() {
        let result = TheFence.Command.routeToolCall(named: "help")

        guard case .failure(let error) = result else {
            return XCTFail("Expected non-MCP command rejection, got \(result)")
        }

        XCTAssertEqual(error.message, "Unknown tool: help")
    }

    func testRemovedProductCommandsAreUnknown() {
        let removedCommands = [
            "start_recording",
            "stop_recording",
            "archive_session",
            "get_session_log",
            "quit",
            "pinch",
            "rotate",
            "two_finger_tap",
        ]

        for commandName in removedCommands {
            XCTAssertNil(TheFence.Command(rawValue: commandName), commandName)

            let routed = TheFence.Command.routeCommandEnvelope(
                .init(values: [
                    "command": .string(commandName),
                ]),
                context: "direct command"
            )
            guard case .failure(let error) = routed else {
                return XCTFail("Expected \(commandName) to be rejected")
            }
            XCTAssertTrue(error.message.contains("unknown command \"\(commandName)\""), error.message)
        }
    }

    @ButtonHeistActor
    func testParseExpectationStringValuesThrowObjectRequired() async {
        for value in ["change", "exists", "updated", "layout", "bogus"] {
            XCTAssertThrowsError(try parseTypedExpectation(.string(value))) { error in
                guard case FenceError.invalidRequest(let msg) = error else {
                    XCTFail("Expected FenceError.invalidRequest, got \(error)")
                    return
                }
                XCTAssertEqual(msg, "Invalid predicate type: expected object with a \"type\" discriminator")
            }
        }
    }

    @ButtonHeistActor
    func testParseExpectationObjectWithoutTypeThrows() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object(["wrong": .string("key")]))) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("\"type\" discriminator"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationInvalidTypeThrows() async {
        XCTAssertThrowsError(try parseTypedExpectation(.int(42))) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Invalid predicate type"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationTopLevelArrayThrows() async {
        XCTAssertThrowsError(try parseTypedExpectation(.array([
            .object(["type": .string("exists")]),
            .object(["type": .string("change")]),
        ]))) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("expected object"))
        }
    }

    @ButtonHeistActor
    func testHeistPlanCarriesTypedActionExpectation() async throws {
        let expectation = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            element: ElementPredicate(identifier: "counter"),
            change: .value(after: "5")
        ))))
        let sourceStep = HeistStep.action(try ActionStep(
            command: .activate(.predicate(ElementPredicateTemplate(identifier: .exact(.literal("counter"))))),
            expectationPolicy: .expect(ActionExpectation(predicate: expectation, timeout: 10))))
        let plan = try HeistPlan(body: [sourceStep])
        guard case .action(let action)? = plan.body.first else {
            return XCTFail("Expected action step")
        }

        XCTAssertEqual(action.expectationPolicy.expectedStep?.predicate, .predicate(expectation))
    }

    // MARK: - Parse Expectation: Discriminator Wire Shape

    @ButtonHeistActor
    func testParseExpectationDiscriminatorScreenChanged() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("change"),
            "scopes": .array([.object(["type": .string("screen")])]),
        ]))
        XCTAssertEqual(result, .change(.screen()))
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementUpdatedFull() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("change"),
                "scopes": .array([.object([
                    "type": .string("elements"),
                    "assertions": .array([.object([
                        "type": .string("updated"),
                        "element": elementPredicateValue(identifier: "slider"),
                        "before": .string("0"),
                        "after": .string("50"),
                        "property": .string("value"),
                ])]),
            ])]),
        ]))
        XCTAssertEqual(
            result,
            .change(.elements(.updatedElement(ElementUpdatePredicate(
                element: ElementPredicate(identifier: "slider"),
                change: .value(before: "0", after: "50")
            ))))
        )
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementUpdatedInvalidPropertyListsValidValues() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("change"),
            "scopes": .array([.object([
                "type": .string("elements"),
                "assertions": .array([.object([
                    "type": .string("updated"),
                    "property": .string("bogus"),
                ])]),
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
    func testParseExpectationDiscriminatorElementUpdatedBare() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("change"),
            "scopes": .array([.object([
                "type": .string("elements"),
                "assertions": .array([.object(["type": .string("updated")])]),
            ])]),
        ]))
        XCTAssertEqual(result, .change(.elements(.updatedElement(.any))))
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorPresentWithElement() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("exists"),
            "element": elementPredicateValue(label: "Cart", identifier: "cart.button"),
        ]))
        XCTAssertEqual(
            result,
            .exists(ElementPredicate(label: "Cart", identifier: "cart.button"))
        )
    }

    @ButtonHeistActor
    func testParseExpectationTargetRejectsRawStringMatcherField() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("exists"),
            "target": .object([
                "label": .string("Pay"),
            ]),
        ]))) { error in
            guard let error = error as? SchemaValidationError else {
                return XCTFail("Expected SchemaValidationError, got \(error)")
            }
            XCTAssertEqual(error.field, "target.label")
            XCTAssertEqual(error.expected, "StringMatch object with mode and optional value, or array of StringMatch objects")
        }
    }

    @ButtonHeistActor
    func testParseExpectationTypedPayloadPreservesElementTraits() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("missing"),
            "element": elementTargetValue([
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
            .missing(ElementPredicate([
                .label("Spinner"),
                .traits([.button]),
                .exclude(.traits([.selected])),
            ]))
        )
    }

    @ButtonHeistActor
    func testParseExpectationTypedPayloadBadElementFieldNamesField() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("exists"),
            "element": .object([
                "checks": .array([
                    predicateCheckValue(kind: "traits", values: [.int(7)]),
                ]),
            ]),
        ]))) { error in
            guard let error = error as? SchemaValidationError else {
                XCTFail("Expected SchemaValidationError, got \(error)")
                return
            }
            XCTAssertEqual(error.field, "element.checks[0].values[0]")
            XCTAssertEqual(error.expected, "trait name")
        }
    }

    @ButtonHeistActor
    func testParseExpectationRejectsDeletedDeliveryType() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("delivery"),
        ]))) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertTrue(message.contains(#"Unknown predicate type: "delivery""#), message)
        }
    }

    @ButtonHeistActor
    func testParseExpectationRejectsExtraElementKeys() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("exists"),
            "element": .object([
                "checks": .array([
                    predicateCheckValue(kind: "label", match: stringMatchValue(mode: "exact", value: "Done")),
                ]),
                "unknown": .string("ignored before"),
            ]),
        ]))) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertEqual(message, #"Unknown element predicate field "unknown""#)
        }
    }

    @ButtonHeistActor
    func testParseExpectationElementRejectsHeistId() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("exists"),
            "element": .object([
                "heistId": .string("button_save"),
            ]),
        ]))) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                return XCTFail("Expected FenceError.invalidRequest, got \(error)")
            }
            XCTAssertEqual(message, #"Unknown element predicate field "heistId""#)
        }
    }

    @ButtonHeistActor
    func testParseExpectationTypedPayloadNonStringTypeNamesTypeField() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .int(7),
        ]))) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("string \"type\" discriminator"))
            XCTAssertTrue(message.contains("type: integer 7"))
        }
    }

    @ButtonHeistActor
    func testParseExpectationRejectsRemovedElementTransitionType() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object(["type": .string("appeared")]))) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(message.contains(#"Unknown predicate type: "appeared""#), message)
        }
    }

    @ButtonHeistActor
    func testParseExpectationRejectsCompoundType() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("compound"),
        ]))) { error in
            guard case FenceError.invalidRequest(let message) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(message.contains(#"Unknown predicate type: "compound""#), message)
            XCTAssertTrue(message.contains("change"), message)
        }
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorUnknownTypeThrows() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object(["type": .string("bogus_type")]))) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Unknown predicate type"))
        }
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
        XCTAssertFalse(query.matcher.hasPredicates)
        XCTAssertNil(query.maxScrollsPerContainer)
        XCTAssertNil(query.maxScrollsPerDiscovery)
    }

    @ButtonHeistActor
    func testUnexpectedParameterIsRejectedByCommandContract() async {
        await assertValidationError(
            command: .activate,
            arguments: ["target": targetValue(identifier: "save"), "mode": .string("tap")],
            equals: "schema validation failed for mode: observed string \"tap\"; expected valid activate parameter"
        )
    }

    @ButtonHeistActor
    func testTargetPayloadIsRejectedForCommandWithoutTargetParameter() async throws {
        await assertValidationError(
            command: .getScreen,
            arguments: ["target": targetValue(label: "Save")],
            equals: "schema validation failed for target: observed object; expected valid get_screen parameter"
        )
    }

    @ButtonHeistActor
    func testTimeoutIsRejectedWhenCommandDoesNotConsumeIt() async {
        await assertValidationError(
            command: .getInterface,
            arguments: ["timeout": .int(15)],
            equals: "schema validation failed for timeout: observed integer 15; expected valid get_interface parameter"
        )
    }

    @ButtonHeistActor
    func testGetInterfaceRejectsDiscoveryLimitOutsideRuntimeRange() async {
        await assertValidationError(
            command: .getInterface,
            arguments: ["maxScrollsPerContainer": .int(0)],
            equals: "schema validation failed for maxScrollsPerContainer: observed integer 0; expected integer between 1 and 2000"
        )
    }

    @ButtonHeistActor
    func testGetInterfaceDefaultNoSubtreeReturnsWholeHierarchy() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let interfaceFixture = selectionTestInterface()
        mockConn.autoResponse = { message in
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
        mockConn.autoResponse = { message in
            switch message {
            case .requestInterface:
                let source = self.selectionTestInterface()
                let selectedNode = source.tree[1]
                return .interface(Interface(
                    timestamp: source.timestamp,
                    tree: [selectedNode],
                    annotations: source.annotations(
                        forSubtree: selectedNode,
                        originalPath: TreePath([1]),
                        rootPath: TreePath([0])
                    )
                ))
            default:
                return .actionResult(ActionResult.success(method: .activate))
            }
        }

        let response = try await fence.execute(command: .getInterface, values: [
            "subtree": .object([
                "container": .object(["containerName": .string("semantic_actions__actions")]),
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
    func testGetInterfaceSubtreeElementRejectsHeistIdAndOrdinal() async {
        await assertOperationValidationError(
            command: .getInterface,
            arguments: [
                "subtree": .object([
                    "element": .object(["heistId": .string("button_save")]),
                    "ordinal": .int(1),
                ]),
            ],
            contains: "Unknown element target field \"heistId\""
        )
    }

    @ButtonHeistActor
    func testGetInterfaceSubtreeElementRejectsUnknownTargetField() async {
        await assertOperationValidationError(
            command: .getInterface,
            arguments: [
                "subtree": .object([
                    "element": .object([
                        "label": stringMatchValue(mode: "exact", value: "Save"),
                        "unexpectedTargetField": .string("button_save"),
                    ]),
                ]),
            ],
            contains: "unexpectedTargetField"
        )
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
    func testGetInterfaceSendsMatcherInObservationQuery() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let submit = TestHeistElementBuilder(label: "Submit", traits: [.button]).build()
        mockConn.autoResponse = { message in
            switch message {
            case .requestInterface:
                return .interface(makeReceiptTestInterface([submit]))
            default:
                return .actionResult(ActionResult.success(method: .activate))
            }
        }

        let response = try await fence.execute(
            command: .getInterface,
            values: ["label": stringMatchValue(mode: "exact", value: "Submit")]
        )

        guard let (message, _) = mockConn.sent.last,
              case .requestInterface(let query) = message else {
            XCTFail("Expected requestInterface query, got \(String(describing: mockConn.sent.last))")
            return
        }
        XCTAssertEqual(query.matcher.checks, [.label(.exact("Submit"))])

        let tree = try publicJSONProbe(response).object("interface").array("tree")
        XCTAssertEqual(tree.count, 1)
        let element = try tree[0].object("element")
        XCTAssertEqual(try element.string("label"), "Submit")
        try element.assertMissing("heistId")
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
    elementTargetValue(["heistId": .string(legacyHeistId)])
}

private func targetValue(
    label: String? = nil,
    identifier: String? = nil,
    value: String? = nil,
    traits: [String]? = nil,
    ordinal: Int? = nil
) -> HeistValue {
    var target: [String: HeistValue] = [:]
    if let label { target["label"] = stringMatchValue(mode: "exact", value: label) }
    if let identifier { target["identifier"] = stringMatchValue(mode: "exact", value: identifier) }
    if let value { target["value"] = stringMatchValue(mode: "exact", value: value) }
    if let traits { target["traits"] = .array(traits.map { .string($0) }) }
    if let ordinal { target["ordinal"] = .int(ordinal) }
    return elementTargetValue(target)
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
    return elementTargetValue(["checks": .array(checks)])
}

private func stringMatchValue(mode: String, value: String) -> HeistValue {
    .object([
        "mode": .string(mode),
        "value": .string(value),
    ])
}

private func elementTargetValue(_ fields: [String: HeistValue]) -> HeistValue {
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
