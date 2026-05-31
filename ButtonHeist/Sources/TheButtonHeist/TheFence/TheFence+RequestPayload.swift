import Foundation

import TheScore

extension TheFence {

    typealias RequestDecoder = @ButtonHeistActor @Sendable (
        TheFence,
        CommandArgumentEnvelope,
        String,
        ExpectationPayload
    ) throws -> DecodedRequestDispatch

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

        init(
            command: Command,
            requestId: String,
            arguments: CommandArgumentEnvelope,
            dispatch: DecodedRequestDispatch,
            expectationPayload: ExpectationPayload
        ) {
            self.command = command
            self.requestId = requestId
            self.arguments = arguments
            self.executableMessages = dispatch.executableMessages
            self.handler = dispatch.handler
            self.expectationPayload = expectationPayload
        }
    }

    static func clientActionDispatch(_ messages: [ClientMessage]) -> DecodedRequestDispatch {
        DecodedRequestDispatch(executableMessages: messages) { fence, request in
            try await fence.handleClientActionRequest(request)
        }
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
        let requestId = arguments.string("requestId") ?? UUID().uuidString
        let expectationPayload = try ExpectationPayload(arguments: arguments)
        let dispatch = try command.descriptor.requestDecoder(self, arguments, requestId, expectationPayload)

        return ParsedRequest(
            command: command,
            requestId: requestId,
            arguments: arguments,
            dispatch: dispatch,
            expectationPayload: expectationPayload
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
        let parameterKeys = Set(command.descriptor.parameters.map(\.key))
        let allowedKeys = metadataKeys.union(parameterKeys)
        guard let unexpectedKey = arguments.keys.sorted().first(where: { !allowedKeys.contains($0) }) else {
            return
        }
        throw SchemaValidationError(
            field: unexpectedKey,
            observed: arguments.observedDescription(for: unexpectedKey) ?? "missing",
            expected: "valid \(command.rawValue) parameter"
        )
    }

    static func decodePingRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        DecodedRequestDispatch { fence, _ in try await fence.handlePing() }
    }

    static func decodeListDevicesRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        DecodedRequestDispatch { fence, _ in try await fence.handleListDevices() }
    }

    static func decodeGetSessionStateRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        DecodedRequestDispatch { fence, _ in .sessionState(payload: fence.currentSessionState()) }
    }

    static func decodeListTargetsRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        DecodedRequestDispatch { fence, _ in fence.handleListTargets() }
    }

    static func decodeGetPasteboardRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        clientActionDispatch([.getPasteboard])
    }

    static func decodeDismissKeyboardRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        clientActionDispatch([.resignFirstResponder])
    }

}
