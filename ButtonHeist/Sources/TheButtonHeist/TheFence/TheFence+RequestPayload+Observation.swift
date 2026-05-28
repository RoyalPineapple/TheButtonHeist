import Foundation

import TheScore

extension TheFence {

    func decodeObservationDispatch(
        command: Command,
        arguments: CommandArgumentEnvelope,
        requestId: String
    ) throws -> DecodedRequestDispatch {
        switch command {
        case .getInterface:
            let request = try decodeGetInterfaceRequest(arguments)
            return DecodedRequestDispatch { fence, _ in try await fence.handleGetInterface(request) }
        case .getScreen:
            let request = try decodeScreenRequest(arguments, requestId: requestId)
            return DecodedRequestDispatch { fence, _ in try await fence.handleGetScreen(request) }
        case .stopRecording:
            let request = try decodeArtifactRequest(arguments, requestId: requestId)
            return DecodedRequestDispatch { fence, _ in try await fence.handleStopRecording(request) }
        default:
            throw FenceError.invalidRequest("Unexpected observation command: \(command.rawValue)")
        }
    }

    private func decodeGetInterfaceRequest(_ arguments: CommandArgumentEnvelope) throws -> GetInterfaceRequest {
        GetInterfaceRequest(
            detail: try arguments.schemaEnum("detail", as: InterfaceDetail.self) ?? .summary,
            query: InterfaceQuery(
                subtree: try decodeInterfaceSubtreeSelector(arguments),
                matcher: try interfaceElementMatcher(arguments)
            )
        )
    }

    private func decodeArtifactRequest(
        _ arguments: CommandArgumentEnvelope,
        requestId: String
    ) throws -> ArtifactRequest {
        ArtifactRequest(
            outputPath: try arguments.schemaString("output"),
            requestId: requestId,
            inlineData: try arguments.schemaBoolean("inlineData") ?? false,
            includeInteractionLog: try arguments.schemaBoolean("includeInteractionLog") ?? false
        )
    }

    private func decodeScreenRequest(
        _ arguments: CommandArgumentEnvelope,
        requestId: String
    ) throws -> ScreenRequest {
        let outputPath = try arguments.schemaString("output")
        let inlineData = try arguments.schemaBoolean("inlineData") ?? false
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
            includeInterface: try arguments.schemaBoolean("includeInterface") ?? false
        )
    }

    func defaultGetInterfaceParsedRequest() -> ParsedRequest {
        ParsedRequest(
            command: .getInterface,
            requestId: UUID().uuidString,
            arguments: CommandArgumentEnvelope(values: [:]),
            dispatch: DecodedRequestDispatch { fence, _ in
                try await fence.handleGetInterface(GetInterfaceRequest(
                    detail: .summary,
                    query: InterfaceQuery()
                ))
            },
            expectationPayload: ExpectationPayload(expectation: nil, timeout: nil),
            immediateResponse: nil
        )
    }

    private func decodeInterfaceSubtreeSelector(_ arguments: CommandArgumentEnvelope) throws -> SubtreeSelector? {
        guard let subtree = try arguments.schemaDictionary("subtree") else { return nil }
        try validateInterfaceSubtreeKeys(subtree)
        let ordinal = try subtree.schemaNonNegativeInteger("ordinal")

        let elementDictionary = try subtree.schemaDictionary("element")
        let containerDictionary = try subtree.schemaDictionary("container")
        guard (elementDictionary == nil) != (containerDictionary == nil) else {
            throw SchemaValidationError(
                field: "subtree",
                observed: subtree.observedDescription,
                expected: "exactly one of element or container"
            )
        }

        let selector: SubtreeSelector
        if let elementDictionary {
            try validateInterfaceSubtreeElementKeys(elementDictionary)
            let target = try subtreeElementTarget(elementDictionary, ordinal: ordinal)
            selector = .element(target)
        } else if let containerDictionary {
            try validateInterfaceSubtreeContainerKeys(containerDictionary)
            let matcher = try subtreeContainerMatcher(containerDictionary)
            selector = .container(matcher, ordinal: ordinal)
        } else {
            throw SchemaValidationError(field: "subtree", observed: subtree.observedDescription, expected: "element or container selector")
        }

        guard selector.hasPredicates else {
            throw SchemaValidationError(field: "subtree", observed: subtree.observedDescription, expected: "non-empty subtree selector")
        }
        return selector
    }

    private func validateInterfaceSubtreeKeys(_ subtree: CommandArgumentObject) throws {
        let allowedKeys: Set<String> = ["element", "container", "ordinal"]
        guard let unexpectedKey = subtree.keys.sorted().first(where: { !allowedKeys.contains($0) }) else {
            return
        }
        throw SchemaValidationError(
            field: subtree.field(unexpectedKey),
            observed: subtree.observedDescription(for: unexpectedKey) ?? "missing",
            expected: "valid get_interface subtree parameter"
        )
    }

    private func validateInterfaceSubtreeElementKeys(_ element: CommandArgumentObject) throws {
        let allowedKeys = Set(["heistId"] + ElementTargetGrammar.matcherFieldNames)
        guard let unexpectedKey = element.keys.sorted().first(where: { !allowedKeys.contains($0) }) else {
            return
        }
        throw SchemaValidationError(
            field: element.field(unexpectedKey),
            observed: element.observedDescription(for: unexpectedKey) ?? "missing",
            expected: "valid get_interface subtree element parameter"
        )
    }

    private func validateInterfaceSubtreeContainerKeys(_ container: CommandArgumentObject) throws {
        let allowedKeys: Set<String> = ["stableId", "type", "label", "value", "identifier", "isModalBoundary"]
        guard let unexpectedKey = container.keys.sorted().first(where: { !allowedKeys.contains($0) }) else {
            return
        }
        throw SchemaValidationError(
            field: container.field(unexpectedKey),
            observed: container.observedDescription(for: unexpectedKey) ?? "missing",
            expected: "valid get_interface subtree container parameter"
        )
    }

    private func subtreeElementTarget(_ element: CommandArgumentObject, ordinal: Int?) throws -> ElementTarget {
        let matcher = try interfaceElementMatcher(element)
        let matcherWasProvided = ElementTargetGrammar.matcherFieldNames
            .contains { element.keys.contains($0) }
        do {
            return try ElementTargetGrammar.validatedTarget(
                heistId: try element.schemaString("heistId"),
                matcher: matcher,
                matcherWasProvided: matcherWasProvided,
                ordinal: ordinal
            )
        } catch let error as ElementTargetGrammarError {
            throw SchemaValidationError(
                field: "subtree.element",
                observed: element.observedDescription,
                expected: subtreeElementExpectedDescription(for: error)
            )
        }
    }

    private func subtreeElementExpectedDescription(for error: ElementTargetGrammarError) -> String {
        switch error {
        case .missingTarget:
            return "heistId or non-empty matcher fields"
        case .emptyMatcher:
            return "matcher with label, identifier, value, traits, or excludeTraits"
        case .mixedHeistIdWithMatcherOrOrdinal:
            return "heistId or matcher fields with optional ordinal, not both"
        case .negativeOrdinal:
            return "integer >= 0"
        }
    }

    private func subtreeContainerMatcher(_ container: CommandArgumentObject) throws -> ContainerMatcher {
        ContainerMatcher(
            stableId: try container.schemaString("stableId"),
            type: try container.schemaEnum("type", as: ContainerTypeName.self),
            label: try container.schemaString("label"),
            value: try container.schemaString("value"),
            identifier: try container.schemaString("identifier"),
            isModalBoundary: try container.schemaBoolean("isModalBoundary")
        )
    }

    private func interfaceElementMatcher(_ arguments: some CommandArgumentReadable) throws -> ElementMatcher {
        ElementMatcher(
            label: try arguments.schemaString("label"),
            identifier: try arguments.schemaString("identifier"),
            value: try arguments.schemaString("value"),
            traits: try TheFence.parseTraitNames(try arguments.schemaStringArray("traits"), field: arguments.field("traits")),
            excludeTraits: try TheFence.parseTraitNames(
                try arguments.schemaStringArray("excludeTraits"),
                field: arguments.field("excludeTraits")
            )
        )
    }
}
