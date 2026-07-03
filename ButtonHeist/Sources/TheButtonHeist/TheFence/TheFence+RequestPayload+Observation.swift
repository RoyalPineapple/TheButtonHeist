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
            detail: try arguments.value(FenceParameters.interfaceDetail) ?? .summary,
            query: InterfaceQuery(
                subtree: try decodeInterfaceSubtreeSelector(arguments),
                matcher: try interfaceElementMatcher(arguments),
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
        let hasChecks = arguments.contains(.checks)
        let hasFlatFields = InterfaceElementMatcherField.allCases.contains { arguments.contains($0.key) }
        if hasChecks, hasFlatFields {
            throw SchemaValidationError(
                field: arguments.field(.checks),
                observed: "mixed ordered checks and flat predicate fields",
                expected: "use either checks or flat predicate fields, not both"
            )
        }
        if let checksValue = arguments.value(for: .checks) {
            try Self.validateElementPredicateChecks(checksValue, field: arguments.field(.checks))
            return ElementPredicate(try arguments.decodePayload(
                checksValue,
                forKey: .checks,
                as: [ElementPredicateCheck<String>].self
            ))
        }

        var checks: [ElementPredicateCheck<String>] = []
        for field in InterfaceElementMatcherField.allCases {
            checks += try field.checks(in: arguments)
        }
        return ElementPredicate(checks)
    }
}

private enum InterfaceElementMatcherField: CaseIterable {
    case label
    case identifier
    case value
    case hint
    case traits
    case actions
    case customContent
    case rotors

    var key: FenceParameterKey {
        switch self {
        case .label:
            return .label
        case .identifier:
            return .identifier
        case .value:
            return .value
        case .hint:
            return .hint
        case .traits:
            return .traits
        case .actions:
            return .actions
        case .customContent:
            return .customContent
        case .rotors:
            return .rotors
        }
    }

    func checks(in arguments: TheFence.CommandArgumentEnvelope) throws -> [ElementPredicateCheck<String>] {
        switch self {
        case .label:
            return try arguments.schemaStringMatches(key).map(ElementPredicateCheck.label)
        case .identifier:
            return try arguments.schemaStringMatches(key).map(ElementPredicateCheck.identifier)
        case .value:
            return try arguments.schemaStringMatches(key).map(ElementPredicateCheck.value)
        case .hint:
            return try arguments.schemaStringMatches(key).map(ElementPredicateCheck.hint)
        case .traits:
            return try traitCheck(in: arguments, makeCheck: ElementPredicateCheck.traits)
        case .actions:
            return try actionCheck(in: arguments, makeCheck: ElementPredicateCheck.actions)
        case .customContent:
            return try customContentCheck(in: arguments, makeCheck: ElementPredicateCheck.customContent)
        case .rotors:
            return try rotorCheck(in: arguments, makeCheck: ElementPredicateCheck.rotors)
        }
    }

    private func traitCheck(
        in arguments: TheFence.CommandArgumentEnvelope,
        makeCheck: (Set<HeistTrait>) -> ElementPredicateCheck<String>
    ) throws -> [ElementPredicateCheck<String>] {
        guard let traits = try TheFence.parseTraitNames(
            try arguments.schemaStringArray(key),
            field: arguments.field(key)
        ), !traits.isEmpty else {
            return []
        }
        return [makeCheck(traits.heistTraitSet)]
    }

    private func actionCheck(
        in arguments: TheFence.CommandArgumentEnvelope,
        makeCheck: (Set<ElementAction>) -> ElementPredicateCheck<String>
    ) throws -> [ElementPredicateCheck<String>] {
        guard let value = arguments.value(for: key) else { return [] }
        try TheFence.validateElementActionsValue(value, field: arguments.field(key))
        let actions = try arguments.decodePayload(value, forKey: key, as: [ElementAction].self)
        return actions.isEmpty ? [] : [makeCheck(Set(actions))]
    }

    private func customContentCheck(
        in arguments: TheFence.CommandArgumentEnvelope,
        makeCheck: (CustomContentMatch<String>) -> ElementPredicateCheck<String>
    ) throws -> [ElementPredicateCheck<String>] {
        guard let value = arguments.value(for: key) else { return [] }
        try TheFence.validateCustomContentMatchObject(value, field: arguments.field(key))
        return [makeCheck(try arguments.decodePayload(value, forKey: key, as: CustomContentMatch<String>.self))]
    }

    private func rotorCheck(
        in arguments: TheFence.CommandArgumentEnvelope,
        makeCheck: ([StringMatch<String>]) -> ElementPredicateCheck<String>
    ) throws -> [ElementPredicateCheck<String>] {
        guard let value = arguments.value(for: key) else { return [] }
        try TheFence.validateStringMatchArray(value, field: arguments.field(key))
        let matches = try arguments.decodePayload(value, forKey: key, as: [StringMatch<String>].self)
        return matches.isEmpty ? [] : [makeCheck(matches)]
    }
}
