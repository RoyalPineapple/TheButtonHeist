import Foundation

import TheScore

extension TheFence {

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

    static func decodeGetInterfaceRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = try fence.makeGetInterfaceRequest(arguments)
        return DecodedRequestDispatch { fence, _ in try await fence.handleGetInterface(request) }
    }

    static func decodeGetScreenRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = try fence.makeScreenRequest(arguments, requestId: requestId)
        return DecodedRequestDispatch { fence, _ in try await fence.handleGetScreen(request) }
    }

    private func makeGetInterfaceRequest(_ arguments: CommandArgumentEnvelope) throws -> GetInterfaceRequest {
        GetInterfaceRequest(
            detail: try arguments.schemaEnum("detail", as: InterfaceDetail.self) ?? .summary,
            query: InterfaceQuery(
                subtree: try decodeInterfaceSubtreeSelector(arguments),
                matcher: try interfaceElementMatcher(arguments)
            )
        )
    }

    private func makeScreenRequest(
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

    private func decodeInterfaceSubtreeSelector(_ arguments: CommandArgumentEnvelope) throws -> SubtreeSelector? {
        guard let subtree = arguments.argumentValues["subtree"] else { return nil }
        guard case .object = subtree else {
            throw SchemaValidationError(
                field: arguments.field("subtree"),
                observed: subtree.schemaObservedDescription,
                expected: "object"
            )
        }
        do {
            let data = try JSONEncoder().encode(subtree)
            let selector = try JSONDecoder().decode(SubtreeSelector.self, from: data)
            guard selector.hasPredicates else {
                throw SchemaValidationError(
                    field: arguments.field("subtree"),
                    observed: subtree.schemaObservedDescription,
                    expected: "non-empty subtree selector"
                )
            }
            return selector
        } catch let error as SchemaValidationError {
            throw error
        } catch let error as DecodingError {
            let context = decodingContext(from: error)
            throw SchemaValidationError(
                field: subtreeField(arguments, codingPath: context.codingPath),
                observed: subtree.schemaObservedDescription,
                expected: context.debugDescription
            )
        } catch {
            throw SchemaValidationError(
                field: arguments.field("subtree"),
                observed: subtree.schemaObservedDescription,
                expected: "valid get_interface subtree parameter"
            )
        }
    }

    private func decodingContext(from error: DecodingError) -> DecodingError.Context {
        switch error {
        case .typeMismatch(_, let context),
             .valueNotFound(_, let context),
             .keyNotFound(_, let context),
             .dataCorrupted(let context):
            return context
        @unknown default:
            return DecodingError.Context(codingPath: [], debugDescription: error.localizedDescription)
        }
    }

    private func subtreeField(_ arguments: CommandArgumentEnvelope, codingPath: [CodingKey]) -> String {
        let suffix = codingPath.map(\.stringValue).filter { !$0.isEmpty }.joined(separator: ".")
        guard !suffix.isEmpty else { return arguments.field("subtree") }
        return "\(arguments.field("subtree")).\(suffix)"
    }

    private func interfaceElementMatcher(_ arguments: CommandArgumentEnvelope) throws -> ElementPredicate {
        ElementPredicate(
            label: try arguments.schemaString("label").map(StringMatch.exact),
            identifier: try arguments.schemaString("identifier").map(StringMatch.exact),
            value: try arguments.schemaString("value").map(StringMatch.exact),
            traits: try TheFence.parseTraitNames(try arguments.schemaStringArray("traits"), field: arguments.field("traits")) ?? [],
            excludeTraits: try TheFence.parseTraitNames(
                try arguments.schemaStringArray("excludeTraits"),
                field: arguments.field("excludeTraits")
            ) ?? []
        )
    }
}
