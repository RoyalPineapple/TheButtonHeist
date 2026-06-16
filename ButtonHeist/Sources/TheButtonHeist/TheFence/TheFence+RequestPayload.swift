import Foundation

@_spi(ButtonHeistInternals) import TheScore

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

    struct DecodedRequestDispatch {
        let runtimeActionMessages: [RuntimeActionMessage]?
        let handler: ParsedRequestHandler

        init(
            runtimeActionMessages: [RuntimeActionMessage]? = nil,
            handler: @escaping ParsedRequestHandler
        ) {
            self.runtimeActionMessages = runtimeActionMessages
            self.handler = handler
        }
    }

    struct ParsedRequest {
        let command: Command
        let requestId: String
        let arguments: CommandArgumentEnvelope
        let runtimeActionMessages: [RuntimeActionMessage]?
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
            self.runtimeActionMessages = dispatch.runtimeActionMessages
            self.handler = dispatch.handler
            self.expectationPayload = expectationPayload
        }
    }

    static func runtimeActionDispatch(_ messages: [RuntimeActionMessage]) -> DecodedRequestDispatch {
        DecodedRequestDispatch(runtimeActionMessages: messages) { fence, request in
            try await fence.handleClientActionRequest(request)
        }
    }

    static func appInteractionDispatch<C: AppInteractionCommand>(
        _: C,
        _ messages: [RuntimeActionMessage]
    ) -> DecodedRequestDispatch {
        runtimeActionDispatch(messages)
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
        let parameterKeys = command.descriptor.topLevelParameterKeys
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

}
