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
        case .getScreen:
            return .screen(try decodeScreenRequest(request, requestId: requestId))
        case .stopRecording:
            return .artifact(try decodeArtifactRequest(request, requestId: requestId))
        default:
            throw FenceError.invalidRequest("Unexpected observation command: \(command.rawValue)")
        }
    }

    private func decodeGetInterfaceRequest(_ request: [String: Any]) throws -> GetInterfaceRequest {
        GetInterfaceRequest(
            detail: try request.schemaEnum("detail", as: InterfaceDetail.self) ?? .summary,
            query: InterfaceQuery(
                subtree: try decodeInterfaceSubtreeSelector(request),
                matcher: try elementMatcher(request),
                elementIds: try request.schemaStringArray("elements")
            )
        )
    }

    private func decodeArtifactRequest(
        _ request: [String: Any],
        requestId: String
    ) throws -> ArtifactRequest {
        ArtifactRequest(
            outputPath: try request.schemaString("output"),
            requestId: requestId,
            inlineData: try request.schemaBoolean("inlineData") ?? false,
            includeInteractionLog: try request.schemaBoolean("includeInteractionLog") ?? false
        )
    }

    private func decodeScreenRequest(
        _ request: [String: Any],
        requestId: String
    ) throws -> ScreenRequest {
        let outputPath = try request.schemaString("output")
        let inlineData = try request.schemaBoolean("inlineData") ?? false
        if inlineData, outputPath != nil {
            throw SchemaValidationError(
                field: "inlineData/output",
                observed: "inlineData=true with output",
                expected: "choose output for an artifact path or inlineData=true for inline PNG data, not both"
            )
        }
        return ScreenRequest(
            outputPath: outputPath,
            requestId: requestId,
            inlineData: inlineData,
            includeInterface: try request.schemaBoolean("includeInterface") ?? false
        )
    }

    func defaultGetInterfaceParsedRequest() -> ParsedRequest {
        ParsedRequest(
            command: .getInterface,
            requestId: UUID().uuidString,
            payload: .getInterface(GetInterfaceRequest(
                detail: .summary,
                query: InterfaceQuery()
            )),
            expectationPayload: ExpectationPayload(expectation: nil, timeout: nil),
            immediateResponse: nil
        )
    }

    private func decodeInterfaceSubtreeSelector(_ request: [String: Any]) throws -> SubtreeSelector? {
        guard let subtree = try request.schemaDictionary("subtree") else { return nil }
        try validateInterfaceSubtreeKeys(subtree)
        let ordinal = try subtree.schemaInteger("ordinal")
        if let ordinal, ordinal < 0 {
            throw SchemaValidationError(field: "subtree.ordinal", observed: ordinal, expected: "integer >= 0")
        }

        let elementDictionary = try subtree.schemaDictionary("element")
        let containerDictionary = try subtree.schemaDictionary("container")
        guard (elementDictionary == nil) != (containerDictionary == nil) else {
            throw SchemaValidationError(
                field: "subtree",
                observed: subtree,
                expected: "exactly one of element or container"
            )
        }

        let selector: SubtreeSelector
        if let elementDictionary {
            try validateInterfaceSubtreeElementKeys(elementDictionary)
            let matcher = try subtreeElementMatcher(elementDictionary)
            selector = .element(matcher, ordinal: ordinal)
        } else if let containerDictionary {
            try validateInterfaceSubtreeContainerKeys(containerDictionary)
            let matcher = try subtreeContainerMatcher(containerDictionary)
            selector = .container(matcher, ordinal: ordinal)
        } else {
            throw SchemaValidationError(field: "subtree", observed: subtree, expected: "element or container selector")
        }

        guard selector.hasPredicates else {
            throw SchemaValidationError(field: "subtree", observed: subtree, expected: "non-empty subtree selector")
        }
        return selector
    }

    private func validateInterfaceSubtreeKeys(_ subtree: [String: Any]) throws {
        let allowedKeys: Set<String> = ["element", "container", "ordinal"]
        guard let unexpectedKey = subtree.keys.sorted().first(where: { !allowedKeys.contains($0) }) else {
            return
        }
        throw SchemaValidationError(
            field: "subtree.\(unexpectedKey)",
            observed: subtree[unexpectedKey],
            expected: "valid get_interface subtree parameter"
        )
    }

    private func validateInterfaceSubtreeElementKeys(_ element: [String: Any]) throws {
        let allowedKeys: Set<String> = ["heistId", "label", "value", "identifier", "traits", "excludeTraits"]
        guard let unexpectedKey = element.keys.sorted().first(where: { !allowedKeys.contains($0) }) else {
            return
        }
        throw SchemaValidationError(
            field: "subtree.element.\(unexpectedKey)",
            observed: element[unexpectedKey],
            expected: "valid get_interface subtree element parameter"
        )
    }

    private func validateInterfaceSubtreeContainerKeys(_ container: [String: Any]) throws {
        let allowedKeys: Set<String> = ["stableId", "type", "label", "value", "identifier", "isModalBoundary"]
        guard let unexpectedKey = container.keys.sorted().first(where: { !allowedKeys.contains($0) }) else {
            return
        }
        throw SchemaValidationError(
            field: "subtree.container.\(unexpectedKey)",
            observed: container[unexpectedKey],
            expected: "valid get_interface subtree container parameter"
        )
    }

    private func subtreeElementMatcher(_ element: [String: Any]) throws -> ElementMatcher {
        let matcher = try elementMatcher(element)
        return ElementMatcher(
            heistId: try element.schemaString("heistId"),
            label: matcher.label,
            identifier: matcher.identifier,
            value: matcher.value,
            traits: matcher.traits,
            excludeTraits: matcher.excludeTraits
        )
    }

    private func subtreeContainerMatcher(_ container: [String: Any]) throws -> ContainerMatcher {
        ContainerMatcher(
            stableId: try container.schemaString("stableId"),
            type: try container.schemaEnum("type", as: ContainerTypeName.self),
            label: try container.schemaString("label"),
            value: try container.schemaString("value"),
            identifier: try container.schemaString("identifier"),
            isModalBoundary: try container.schemaBoolean("isModalBoundary")
        )
    }
}
