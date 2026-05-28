import Foundation

import TheScore

extension TheFence {

    struct MissingElementTarget: Error {
        let command: String
    }

    enum RequestPayload {
        case none
        case clientAction([ClientMessage])
        case getInterface(GetInterfaceRequest)
        case screen(ScreenRequest)
        case artifact(ArtifactRequest)
        case startRecording(RecordingConfig)
        case connect(ConnectRequest)
        case runBatch(RunBatchRequest)
        case archiveSession(ArchiveSessionRequest)
        case startHeist(StartHeistRequest)
        case stopHeist(StopHeistRequest)
        case playHeist(PlayHeistRequest)
    }

    struct GetInterfaceRequest {
        let detail: InterfaceDetail
        let query: InterfaceQuery
    }

    struct ScreenRequest {
        let outputPath: String?
        let requestId: String
        let inlineData: Bool
        let includeInterface: Bool
    }

    struct ArtifactRequest {
        let outputPath: String?
        let requestId: String
        let inlineData: Bool
        let includeInteractionLog: Bool
    }

    struct CountArgument {
        let value: Int?
        let observed: String?
    }

    struct ConnectRequest {
        let targetName: String?
        let device: String?
        let token: String?
    }

    struct RunBatchRequest {
        let steps: [RunBatchPreparedStep]
        let policy: BatchPolicy
    }

    struct RunBatchPreparedStep {
        let originalIndex: Int
        let command: Command
        let typedStep: TheScore.BatchStep

        init(
            originalIndex: Int,
            command: Command,
            typedStep: TheScore.BatchStep
        ) {
            self.originalIndex = originalIndex
            self.command = command
            self.typedStep = typedStep
        }

        var commandName: String { command.rawValue }
    }

    struct DecodedRequestPayload {
        let payload: RequestPayload

        init(payload: RequestPayload) {
            self.payload = payload
        }
    }

    struct ParsedRequest {
        let command: Command
        let requestId: String
        let payload: RequestPayload
        let expectationPayload: ExpectationPayload
        /// Non-nil when the command short-circuits before dispatch (help/quit).
        let immediateResponse: FenceResponse?

        init(
            command: Command,
            requestId: String,
            payload: RequestPayload,
            expectationPayload: ExpectationPayload,
            immediateResponse: FenceResponse?
        ) {
            self.command = command
            self.requestId = requestId
            self.payload = payload
            self.expectationPayload = expectationPayload
            self.immediateResponse = immediateResponse
        }

        var executableMessages: [ClientMessage]? {
            guard case .clientAction(let messages) = payload else { return nil }
            return messages
        }
    }

    struct ClientMessageExecutionPlan {
        let messages: [ClientMessage]
        let timeout: TimeInterval
        let recordsCompletion: Bool
    }

    struct RoutedCommandRequest {
        private let arguments: CommandArgumentEnvelope
        let expectationPayload: ExpectationPayload?

        init(arguments: CommandArgumentEnvelope, expectationPayload: ExpectationPayload? = nil) {
            self.arguments = arguments
            self.expectationPayload = expectationPayload
        }

        func string(_ key: String) -> String? { arguments.string(key) }

        func argumentEnvelopeForRequestDecoding() -> CommandArgumentEnvelope {
            arguments
        }

    }

    struct ArchiveSessionRequest {
        let deleteSource: Bool
    }

    struct StartHeistRequest {
        let app: String
        let identifier: String
    }

    struct StopHeistRequest {
        let outputPath: String
    }

    struct PlayHeistRequest {
        let inputPath: String
    }

    /// Parse and validate a raw request dictionary into typed fields.
    /// Returns an ImmediateResponse-bearing `ParsedRequest` for help/quit
    /// so the caller short-circuits without logging or dispatching.
    func parseRequest(_ request: [String: Any]) throws -> ParsedRequest {
        let requestEnvelope = try CommandArgumentEnvelope(arguments: request, droppingCommandKey: false)
        let commandString = try requestEnvelope.requiredSchemaString("command")
        guard let command = Command(rawValue: commandString) else {
            return ParsedRequest(
                command: .help,
                requestId: "",
                payload: .none,
                expectationPayload: ExpectationPayload(expectation: nil, timeout: nil),
                immediateResponse: .error("Unknown command: \(commandString). Use 'help' for available commands.")
            )
        }
        return try parseRequest(command: command, arguments: requestEnvelope.dropping("command"))
    }

    func parseRequest(command: Command, arguments: CommandArgumentEnvelope) throws -> ParsedRequest {
        guard command.descriptor.isPublicRequestContract else {
            throw SchemaValidationError(
                field: "command",
                observed: command.rawValue as Any,
                expected: "public Button Heist command"
            )
        }
        return try parseRequest(
            command: command,
            arguments: arguments,
            expectationPayload: nil
        )
    }

    private func parseRequest(
        command: Command,
        arguments: CommandArgumentEnvelope,
        expectationPayload typedExpectationPayload: ExpectationPayload?
    ) throws -> ParsedRequest {
        try validateRequestKeys(command: command, arguments: arguments)
        if let immediate = handleImmediateCommand(command) {
            return ParsedRequest(
                command: command,
                requestId: "",
                payload: .none,
                expectationPayload: ExpectationPayload(expectation: nil, timeout: nil),
                immediateResponse: immediate
            )
        }
        let requestId = arguments.string("requestId") ?? UUID().uuidString
        let expectationPayload = try typedExpectationPayload ?? parseExpectationPayload(arguments)
        let decodedPayload: DecodedRequestPayload
        if command.requestPayloadKind == .waitForChange {
            let target = WaitForChangeTarget(
                expect: expectationPayload.expectation,
                timeout: expectationPayload.timeout
            )
            decodedPayload = DecodedRequestPayload(
                payload: .clientAction([.waitForChange(target)])
            )
        } else {
            decodedPayload = try decodeRequestPayload(command: command, arguments: arguments, requestId: requestId)
        }

        return ParsedRequest(
            command: command,
            requestId: requestId,
            payload: decodedPayload.payload,
            expectationPayload: expectationPayload,
            immediateResponse: nil
        )
    }

    func parseRequest(operation: NormalizedOperation) throws -> ParsedRequest {
        let request = operation.request
        return try parseRequest(
            command: operation.command,
            arguments: request.argumentEnvelopeForRequestDecoding(),
            expectationPayload: request.expectationPayload
        )
    }

    private func validateRequestKeys(command: Command, arguments: CommandArgumentEnvelope) throws {
        let metadataKeys = Set(["requestId"])
        let parameterKeys = Set(command.parameters.map(\.key))
        let allowedKeys = metadataKeys.union(parameterKeys)
        guard let unexpectedKey = arguments.keys.sorted().first(where: { !allowedKeys.contains($0) }) else {
            return
        }
        throw SchemaValidationError(
            field: unexpectedKey,
            observed: arguments.observedValue(for: unexpectedKey),
            expected: "valid \(command.rawValue) parameter"
        )
    }

    func parsePlaybackOperation(_ operation: PlaybackOperation) throws -> ParsedRequest {
        try parseRequest(operation: operation.normalizedOperation())
    }

    func decodeRequestPayload(
        command: Command,
        arguments: CommandArgumentEnvelope,
        requestId: String
    ) throws -> DecodedRequestPayload {
        switch command.requestPayloadKind {
        case .none:
            if command == .dismissKeyboard {
                return DecodedRequestPayload(payload: .clientAction([.resignFirstResponder]))
            }
            if command == .getPasteboard {
                return DecodedRequestPayload(payload: .clientAction([.getPasteboard]))
            }
            return DecodedRequestPayload(payload: .none)
        case .observation:
            return DecodedRequestPayload(payload: try decodeObservationPayload(
                command: command,
                arguments: arguments,
                requestId: requestId
            ))
        case .waitForChange:
            throw FenceError.invalidRequest("wait_for_change payload is decoded through expectation parsing")
        case .gesture:
            return try decodeGestureRequestPayload(command: command, arguments: arguments)
        case .elementAction:
            return try decodeElementActionPayload(command: command, arguments: arguments)
        case .session:
            return DecodedRequestPayload(payload: try decodeSessionPayload(command: command, arguments: arguments))
        }
    }
}
