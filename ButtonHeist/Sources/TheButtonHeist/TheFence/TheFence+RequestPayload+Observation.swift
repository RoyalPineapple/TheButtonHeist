import Foundation

import TheScore

extension TheFence {

    func decodeGetInterfaceRequest(_ request: [String: Any]) throws -> GetInterfaceRequest {
        GetInterfaceRequest(
            scope: try decodeGetInterfaceScope(request),
            detail: try request.schemaEnum("detail", as: InterfaceDetail.self) ?? .summary,
            matcher: try elementMatcher(request),
            elementIds: try request.schemaStringArray("elements")
        )
    }

    func decodeArtifactRequest(
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
}
