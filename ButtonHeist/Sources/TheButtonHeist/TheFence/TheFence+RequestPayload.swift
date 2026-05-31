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

}
