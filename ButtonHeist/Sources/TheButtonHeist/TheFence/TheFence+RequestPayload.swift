import Foundation

import TheScore

extension TheFence {

    struct MissingElementTarget: Error {
        let command: String
    }

    typealias ParsedRequestHandler = @ButtonHeistActor (TheFence, ParsedRequest) async throws -> FenceResponse

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
        let policy: BatchExecutionPolicy
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

    struct DecodedRequestDispatch {
        let executableMessages: [ClientMessage]?
        let handler: ParsedRequestHandler

        init(
            executableMessages: [ClientMessage]? = nil,
            handler: @escaping ParsedRequestHandler
        ) {
            self.executableMessages = executableMessages
            self.handler = handler
        }
    }

    struct ParsedRequest {
        let command: Command
        let requestId: String
        let arguments: CommandArgumentEnvelope
        let executableMessages: [ClientMessage]?
        let handler: ParsedRequestHandler
        let expectationPayload: ExpectationPayload
        /// Non-nil when the command short-circuits before dispatch (help/quit).
        let immediateResponse: FenceResponse?

        init(
            command: Command,
            requestId: String,
            arguments: CommandArgumentEnvelope,
            dispatch: DecodedRequestDispatch,
            expectationPayload: ExpectationPayload,
            immediateResponse: FenceResponse?
        ) {
            self.command = command
            self.requestId = requestId
            self.arguments = arguments
            self.executableMessages = dispatch.executableMessages
            self.handler = dispatch.handler
            self.expectationPayload = expectationPayload
            self.immediateResponse = immediateResponse
        }
    }

    static func clientActionDispatch(_ messages: [ClientMessage]) -> DecodedRequestDispatch {
        DecodedRequestDispatch(executableMessages: messages) { fence, request in
            try await fence.handleClientActionRequest(request)
        }
    }

    static func emptyDispatch(command: Command) -> DecodedRequestDispatch {
        DecodedRequestDispatch { _, _ in
            .error("Unexpected command in dispatch: \(command.rawValue)")
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

    func parseRequest(command: Command, arguments: CommandArgumentEnvelope) throws -> ParsedRequest {
        guard command.descriptor.isPublicRequestContract else {
            throw SchemaValidationError(
                field: "command",
                observed: "string \"\(command.rawValue)\"",
                expected: "public Button Heist command"
            )
        }
        try validateRequestKeys(command: command, arguments: arguments)
        try validateTypedElementTarget(command: command, arguments: arguments)
        if let immediate = handleImmediateCommand(command) {
            return ParsedRequest(
                command: command,
                requestId: "",
                arguments: arguments,
                dispatch: Self.emptyDispatch(command: command),
                expectationPayload: ExpectationPayload(expectation: nil, timeout: nil),
                immediateResponse: immediate
            )
        }
        let requestId = arguments.string("requestId") ?? UUID().uuidString
        let expectationPayload = try ExpectationPayload(arguments: arguments)
        let dispatch: DecodedRequestDispatch
        if command.requestPayloadKind == .waitForChange {
            let target = WaitForChangeTarget(
                expect: expectationPayload.expectation,
                timeout: expectationPayload.timeout
            )
            dispatch = Self.clientActionDispatch([.waitForChange(target)])
        } else {
            dispatch = try decodeRequestDispatch(command: command, arguments: arguments, requestId: requestId)
        }

        return ParsedRequest(
            command: command,
            requestId: requestId,
            arguments: arguments,
            dispatch: dispatch,
            expectationPayload: expectationPayload,
            immediateResponse: nil
        )
    }

    func parseRequest(operation: NormalizedOperation) throws -> ParsedRequest {
        return try parseRequest(
            command: operation.command,
            arguments: operation.arguments
        )
    }

    private func validateTypedElementTarget(command: Command, arguments: CommandArgumentEnvelope) throws {
        guard let elementTarget = arguments.elementTarget else { return }
        guard !command.descriptor.elementTargetParameterKeys.isEmpty else {
            throw SchemaValidationError(
                field: "target",
                observed: elementTarget.description,
                expected: "\(command.rawValue) command without element target"
            )
        }
    }

    private func validateRequestKeys(command: Command, arguments: CommandArgumentEnvelope) throws {
        let metadataKeys = Set(["requestId"])
        var parameterKeys = Set(command.parameters.map(\.key))
        if arguments.isPlaybackStep {
            parameterKeys.subtract(command.descriptor.elementTargetParameterKeys)
        }
        let allowedKeys = metadataKeys.union(parameterKeys)
        guard let unexpectedKey = arguments.keys.sorted().first(where: { !allowedKeys.contains($0) }) else {
            return
        }
        throw SchemaValidationError(
            field: unexpectedKey,
            observed: arguments.observedDescription(for: unexpectedKey) ?? "missing",
            expected: arguments.isPlaybackStep
                ? "valid \(command.rawValue) playback argument"
                : "valid \(command.rawValue) parameter"
        )
    }

    func decodeRequestDispatch(
        command: Command,
        arguments: CommandArgumentEnvelope,
        requestId: String
    ) throws -> DecodedRequestDispatch {
        switch command.requestPayloadKind {
        case .none:
            if command == .dismissKeyboard {
                return Self.clientActionDispatch([.resignFirstResponder])
            }
            if command == .getPasteboard {
                return Self.clientActionDispatch([.getPasteboard])
            }
            return try decodeControlDispatch(command)
        case .observation:
            return try decodeObservationDispatch(
                command: command,
                arguments: arguments,
                requestId: requestId
            )
        case .waitForChange:
            throw FenceError.invalidRequest("wait_for_change payload is decoded through expectation parsing")
        case .gesture:
            return try decodeGestureAction(command: command, request: arguments)
        case .elementAction:
            return try decodeElementActionDispatch(command: command, arguments: arguments)
        case .session:
            return try decodeSessionDispatch(command: command, arguments: arguments)
        }
    }

    private func decodeControlDispatch(_ command: Command) throws -> DecodedRequestDispatch {
        switch command {
        case .ping:
            return DecodedRequestDispatch { fence, _ in try await fence.handlePing() }
        case .listDevices:
            return DecodedRequestDispatch { fence, _ in try await fence.handleListDevices() }
        case .getSessionState:
            return DecodedRequestDispatch { fence, _ in .sessionState(payload: fence.currentSessionState()) }
        case .listTargets:
            return DecodedRequestDispatch { fence, _ in fence.handleListTargets() }
        case .getSessionLog:
            return DecodedRequestDispatch { fence, _ in try fence.handleGetSessionLog() }
        default:
            throw FenceError.invalidRequest("Unexpected no-payload command: \(command.rawValue)")
        }
    }
}
