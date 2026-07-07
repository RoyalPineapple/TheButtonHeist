import Foundation
import ThePlans

import TheScore

extension TheFence {

    struct GetInterfaceRequest {
        let detail: InterfaceDetail
        let query: InterfaceQuery
    }

    struct ScreenRequest {
        let destination: ScreenshotDestination
        let mode: ScreenCaptureMode
        let requestId: String
    }

    package enum ScreenshotDestination: Sendable, Equatable {
        case artifact(outputPath: String?)
        case inlineData
    }

    static func decodeGetInterfaceRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = try fence.makeGetInterfaceRequest(arguments)
        return DecodedRequestDispatch { fence in try await fence.handleGetInterface(request) }
    }

    static func decodeGetScreenRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = try fence.makeScreenRequest(arguments, requestId: requestId)
        return DecodedRequestDispatch { fence in try await fence.handleGetScreen(request) }
    }

    private func makeGetInterfaceRequest(_ arguments: CommandArgumentEnvelope) throws -> GetInterfaceRequest {
        let subtree = try decodeInterfaceSubtreeSelector(arguments)
        let matcher = try interfaceElementMatcher(arguments)
        if subtree != nil, matcher.hasPredicates {
            throw SchemaValidationError(
                field: arguments.field(.subtree),
                observed: "subtree with element matcher",
                expected: "use subtree or element matcher fields, not both"
            )
        }
        return GetInterfaceRequest(
            detail: try arguments.value(FenceParameters.interfaceDetail) ?? .summary,
            query: InterfaceQuery(
                subtree: subtree,
                matcher: matcher,
                maxScrollsPerContainer: try interfaceDiscoveryLimit(arguments, .maxScrollsPerContainer),
                maxScrollsPerDiscovery: try interfaceDiscoveryLimit(arguments, .maxScrollsPerDiscovery)
            )
        )
    }

    private func interfaceDiscoveryLimit(
        _ arguments: CommandArgumentEnvelope,
        _ key: FenceParameterKey
    ) throws -> Int? {
        let parameter: FenceParameter<Int>
        if key == .maxScrollsPerContainer {
            parameter = FenceParameters.maxScrollsPerContainer
        } else if key == .maxScrollsPerDiscovery {
            parameter = FenceParameters.maxScrollsPerDiscovery
        } else {
            preconditionFailure("Unsupported interface discovery limit parameter \(key.rawValue)")
        }
        guard let value = try arguments.value(parameter) else { return nil }
        guard (1...2_000).contains(value) else {
            throw SchemaValidationError(
                field: arguments.field(key),
                observed: value,
                expected: "integer between 1 and 2000"
            )
        }
        return value
    }

    private func makeScreenRequest(
        _ arguments: CommandArgumentEnvelope,
        requestId: String
    ) throws -> ScreenRequest {
        return ScreenRequest(
            destination: try screenshotDestination(arguments),
            mode: try arguments.value(FenceParameters.screenMode) ?? .raw,
            requestId: requestId
        )
    }

    private func screenshotDestination(_ arguments: CommandArgumentEnvelope) throws -> ScreenshotDestination {
        let outputPath = try arguments.value(FenceParameters.output)
        let inlineData = try arguments.value(FenceParameters.inlineData) ?? false
        switch (inlineData, outputPath) {
        case (true, nil):
            return .inlineData
        case (false, let outputPath):
            return .artifact(outputPath: outputPath)
        case (true, .some):
            throw SchemaValidationError(
                field: "inlineData/output",
                observed: "inlineData=true with output",
                expected: "choose output for an artifact path or inlineData=true for inline PNG data, not both"
            )
        }
    }

    private func decodeInterfaceSubtreeSelector(_ arguments: CommandArgumentEnvelope) throws -> SubtreeSelector? {
        guard let subtree = arguments.value(for: .subtree) else { return nil }
        guard case .object = subtree else {
            throw SchemaValidationError(
                field: arguments.field(.subtree),
                observed: subtree.schemaObservedDescription,
                expected: "object"
            )
        }
        try validateSubtreeElementStringMatchObjects(subtree, field: arguments.field(.subtree))
        let selector = try arguments.decodePayload(subtree, forKey: .subtree, as: SubtreeSelector.self)
        guard selector.hasPredicates else {
            throw SchemaValidationError(
                field: arguments.field(.subtree),
                observed: subtree.schemaObservedDescription,
                expected: "non-empty subtree selector"
            )
        }
        return selector
    }

    private func validateSubtreeElementStringMatchObjects(_ value: HeistValue, field: String) throws {
        guard case .object(let subtree) = value,
              let element = subtree["element"],
              case .object(let object) = element
        else {
            return
        }
        try Self.validateElementPredicatePayloadStringMatches(.object(object), field: "\(field).element")
    }

    private func interfaceElementMatcher(_ arguments: CommandArgumentEnvelope) throws -> ElementPredicate {
        if let checksValue = arguments.value(for: .checks) {
            try Self.validateElementPredicateChecks(checksValue, field: arguments.field(.checks))
            return ElementPredicate(try arguments.decodePayload(
                checksValue,
                forKey: .checks,
                as: [ElementPredicateCheck<String>].self
            ))
        }
        return ElementPredicate()
    }
}
