import Foundation

/// The canonical authored element predicate.
public struct ElementPredicate: Codable, Sendable, Equatable, Hashable {
    package let core: ElementPredicateCore<AuthoredString>

    package init(core: ElementPredicateCore<AuthoredString>) {
        self.core = core
    }

    public init(_ checks: [ElementPredicateCheck] = []) {
        core = ElementPredicateCore(checks.map(\.core))
    }

    public init(
        label: StringMatch? = nil,
        identifier: StringMatch? = nil,
        value: StringMatch? = nil,
        traits: [HeistTrait] = [],
        hint: StringMatch? = nil,
        actions: [ElementAction] = [],
        customContent: CustomContentMatch? = nil,
        rotors: [StringMatch] = []
    ) {
        core = ElementPredicateCore(Self.checks(
            label: label,
            identifier: identifier,
            value: value,
            traits: traits,
            hint: hint,
            actions: actions,
            customContent: customContent,
            rotors: rotors
        ))
    }

    public init(
        _ checks: [ElementPredicateCheck],
        traits: [HeistTrait] = [],
        actions: [ElementAction] = []
    ) {
        core = ElementPredicateCore(
            checks.map(\.core) + Self.setChecks(traits: traits, actions: actions)
        )
    }

    public var checks: [ElementPredicateCheck] {
        core.checks.map { ElementPredicateCheck(core: $0) }
    }

    public var hasPredicates: Bool { core.hasPredicates }
    public var invalidEmptyPayloadDescription: String? { core.invalidEmptyPayloadDescription }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedElementPredicate {
        let resolved = ResolvedElementPredicate(core: try core.map { try $0.resolve(in: environment) })
        if let mode = resolved.core.invalidEmptyBroadMode {
            throw HeistExpressionError.invalidStringMatch(mode: mode.rawValue)
        }
        if let description = resolved.invalidEmptyPayloadDescription {
            throw InvalidResolvedPredicateError(reason: description)
        }
        return resolved
    }

    private static func checks(
        label: StringMatch?,
        identifier: StringMatch?,
        value: StringMatch?,
        traits: [HeistTrait],
        hint: StringMatch?,
        actions: [ElementAction],
        customContent: CustomContentMatch?,
        rotors: [StringMatch]
    ) -> [ElementPredicateCheckCore<AuthoredString>] {
        [
            label.map { .label($0.core) },
            identifier.map { .identifier($0.core) },
            value.map { .value($0.core) },
            hint.map { .hint($0.core) },
            customContent.map { .customContent($0.core) },
            rotors.isEmpty ? nil : .rotors(rotors.map(\.core)),
        ].compactMap { $0 } + setChecks(traits: traits, actions: actions)
    }

    private static func setChecks(
        traits: [HeistTrait],
        actions: [ElementAction]
    ) -> [ElementPredicateCheckCore<AuthoredString>] {
        [
            traits.isEmpty ? nil : .traits(traits.heistTraitSet),
            actions.isEmpty ? nil : .actions(Set(actions)),
        ].compactMap { $0 }
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case checks
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element predicate template")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(container: container, requiresNonEmpty: true)
    }

    static func decodeAllowingAdditionalKeys(from decoder: Decoder) throws -> ElementPredicate {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        return try ElementPredicate(container: container, requiresNonEmpty: container.contains(.checks))
    }

    init(container: KeyedDecodingContainer<CodingKeys>, requiresNonEmpty: Bool) throws {
        core = ElementPredicateCore(
            try container.decodeIfPresent([ElementPredicateCheckCore<AuthoredString>].self, forKey: .checks) ?? []
        )
        if requiresNonEmpty, let description = invalidEmptyPayloadDescription {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath + [CodingKeys.checks],
                debugDescription: description
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !core.checks.isEmpty {
            try container.encode(core.checks, forKey: .checks)
        }
    }
}

extension ElementPredicate: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call(
            "predicate",
            core.checks.map { $0.map(\.description).description }
        )
    }
}
