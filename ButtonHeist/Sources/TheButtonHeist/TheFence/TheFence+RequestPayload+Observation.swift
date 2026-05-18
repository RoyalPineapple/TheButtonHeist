import Foundation

import TheScore

extension TheFence {

    func decodeObservationPayload(
        command: Command,
        request: [String: Any],
        requestId: String
    ) throws -> RequestPayload {
        switch command {
        case .getInterface:
            return .getInterface(try decodeGetInterfaceRequest(request))
        case .getScreen, .stopRecording:
            return .artifact(try decodeArtifactRequest(request, requestId: requestId))
        default:
            throw FenceError.invalidRequest("Unexpected observation command: \(command.rawValue)")
        }
    }

    private func decodeGetInterfaceRequest(_ request: [String: Any]) throws -> GetInterfaceRequest {
        GetInterfaceRequest(
            scope: try decodeGetInterfaceScope(request),
            detail: try request.schemaEnum("detail", as: InterfaceDetail.self) ?? .summary,
            root: try decodeInterfaceRootSelector(request),
            matcher: try elementMatcher(request),
            elementIds: try request.schemaStringArray("elements")
        )
    }

    private func decodeArtifactRequest(
        _ request: [String: Any],
        requestId: String
    ) throws -> ArtifactRequest {
        ArtifactRequest(
            outputPath: try request.schemaString("output"),
            requestId: requestId
        )
    }

    func defaultGetInterfaceParsedRequest() -> ParsedRequest {
        ParsedRequest(
            command: .getInterface,
            requestId: UUID().uuidString,
            originalRequest: ["command": Command.getInterface.rawValue],
            payload: .getInterface(GetInterfaceRequest(
                scope: .full,
                detail: .summary,
                root: nil,
                matcher: ElementMatcher(),
                elementIds: nil
            )),
            expectationPayload: ExpectationPayload(expectation: nil, timeout: nil),
            immediateResponse: nil
        )
    }

    private func decodeGetInterfaceScope(_ request: [String: Any]) throws -> GetInterfaceScope {
        if let rawScope = try request.schemaString("scope") {
            switch rawScope {
            case GetInterfaceScope.visible.rawValue:
                return .visible
            default:
                throw SchemaValidationError(
                    field: "scope",
                    observed: rawScope as Any,
                    expected: "omitted or visible"
                )
            }
        }
        return .full
    }

    private func decodeInterfaceRootSelector(_ request: [String: Any]) throws -> InterfaceRootSelector? {
        guard let root = try request.schemaDictionary("root") else { return nil }
        try validateInterfaceRootKeys(root)
        let ordinal = try root.schemaInteger("ordinal")
        if let ordinal, ordinal < 0 {
            throw SchemaValidationError(field: "root.ordinal", observed: ordinal, expected: "integer >= 0")
        }
        let selector = InterfaceRootSelector(
            heistId: try root.schemaString("heistId"),
            stableId: try root.schemaString("stableId"),
            type: try root.schemaEnum("type", as: InterfaceRootContainerType.self),
            matcher: try elementMatcher(root),
            modal: try root.schemaBoolean("modal"),
            ordinal: ordinal
        )
        guard selector.hasPredicates else {
            throw SchemaValidationError(field: "root", observed: root, expected: "non-empty root projection selector")
        }
        return selector
    }

    private func validateInterfaceRootKeys(_ root: [String: Any]) throws {
        let allowedKeys: Set<String> = [
            "heistId", "stableId", "type", "label", "value", "identifier",
            "traits", "excludeTraits", "modal", "ordinal",
        ]
        guard let unexpectedKey = root.keys.sorted().first(where: { !allowedKeys.contains($0) }) else {
            return
        }
        throw SchemaValidationError(
            field: "root.\(unexpectedKey)",
            observed: root[unexpectedKey],
            expected: "valid get_interface root parameter"
        )
    }
}
