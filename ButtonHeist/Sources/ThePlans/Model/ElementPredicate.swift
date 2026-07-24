import Foundation

private enum ElementPredicateCheckCodingKeys: String, CodingKey, CaseIterable {
    case kind, match, values, check
}

private func rejectIrrelevantElementPredicateFields(
    for kind: ElementPredicateCheck.Kind,
    in container: KeyedDecodingContainer<ElementPredicateCheckCodingKeys>
) throws {
    let allowed: Set<ElementPredicateCheckCodingKeys>
    switch kind {
    case .label, .identifier, .value, .hint, .customContent:
        allowed = [.kind, .match]
    case .traits, .actions, .rotors:
        allowed = [.kind, .values]
    case .exclude:
        allowed = [.kind, .check]
    }
    for key in container.allKeys where !allowed.contains(key) {
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "\(key.stringValue) is not valid for \(kind.rawValue) element predicate checks"
        )
    }
}

/// One authored element check whose references resolve before evaluation.
public indirect enum ElementPredicateCheck: Codable, Sendable, Equatable, Hashable {
    case label(StringMatch)
    case identifier(StringMatch)
    case value(StringMatch)
    case traits(Set<HeistTrait>)
    case hint(StringMatch)
    case actions(Set<ElementAction>)
    case customContent(CustomContentMatch)
    case rotors([StringMatch])
    case exclude(ElementPredicateCheck)

    package enum Kind: String, Codable, CaseIterable {
        case label, identifier, value, hint
        case traits, actions, customContent, rotors
        case exclude
    }

    public static func label(_ value: String) -> Self { .label(.exact(value)) }
    @_disfavoredOverload
    public static func label(_ reference: HeistReferenceName) -> Self { .label(.exact(reference)) }
    public static func identifier(_ value: String) -> Self { .identifier(.exact(value)) }
    @_disfavoredOverload
    public static func identifier(_ reference: HeistReferenceName) -> Self { .identifier(.exact(reference)) }
    public static func value(_ value: String) -> Self { .value(.exact(value)) }
    @_disfavoredOverload
    public static func value(_ reference: HeistReferenceName) -> Self { .value(.exact(reference)) }
    public static func hint(_ value: String) -> Self { .hint(.exact(value)) }
    @_disfavoredOverload
    public static func hint(_ reference: HeistReferenceName) -> Self { .hint(.exact(reference)) }

    public var hasPredicateLiteral: Bool {
        switch self {
        case .label(let match), .identifier(let match), .value(let match), .hint(let match):
            return match.hasPredicateLiteral
        case .traits(let traits):
            return !traits.isEmpty
        case .actions(let actions):
            return !actions.isEmpty
        case .customContent(let match):
            return match.hasPredicateLiteral
        case .rotors(let matches):
            return matches.contains { $0.hasPredicateLiteral }
        case .exclude(let check):
            return check.hasPredicateLiteral
        }
    }

    public var invalidEmptyPayloadDescription: String? {
        switch self {
        case .label(let match):
            return Self.emptyStringPayloadDescription(match, field: "label")
        case .identifier(let match):
            return Self.emptyStringPayloadDescription(match, field: "identifier")
        case .value(let match):
            return Self.emptyStringPayloadDescription(match, field: "value")
        case .hint(let match):
            return Self.emptyStringPayloadDescription(match, field: "hint")
        case .traits(let traits):
            return traits.isEmpty ? "traits check must not be empty" : nil
        case .actions(let actions):
            return actions.isEmpty ? "actions check must not be empty" : nil
        case .customContent(let match):
            if let description = match.label.flatMap({
                Self.emptyStringPayloadDescription($0, field: "customContent label")
            }) {
                return description
            }
            if let description = match.value.flatMap({
                Self.emptyStringPayloadDescription($0, field: "customContent value")
            }) {
                return description
            }
            return match.hasPredicateLiteral ? nil : "customContent match must include label, value, or isImportant"
        case .rotors(let matches):
            if matches.isEmpty {
                return "rotors check must not be empty"
            }
            return matches.lazy.compactMap { Self.emptyStringPayloadDescription($0, field: "rotor") }.first
        case .exclude(let check):
            if let description = check.invalidEmptyPayloadDescription {
                return "excluded \(description)"
            }
            return check.hasPredicateLiteral ? nil : "exclude check must not be empty"
        }
    }

    package var invalidEmptyBroadMode: StringMatch.Mode? {
        switch self {
        case .label(let match), .identifier(let match), .value(let match), .hint(let match):
            return match.hasInvalidEmptyBroadLiteral ? match.mode : nil
        case .customContent(let match):
            return [match.label, match.value].compactMap { $0 }
                .first(where: \.hasInvalidEmptyBroadLiteral)?.mode
        case .rotors(let matches):
            return matches.first(where: \.hasInvalidEmptyBroadLiteral)?.mode
        case .exclude(let check):
            return check.invalidEmptyBroadMode
        case .traits, .actions:
            return nil
        }
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedElementPredicateCheck {
        switch self {
        case .label(let match): return .label(try match.resolve(in: environment))
        case .identifier(let match): return .identifier(try match.resolve(in: environment))
        case .value(let match): return .value(try match.resolve(in: environment))
        case .traits(let traits): return .traits(traits)
        case .hint(let match): return .hint(try match.resolve(in: environment))
        case .actions(let actions): return .actions(actions)
        case .customContent(let match): return .customContent(try match.resolve(in: environment))
        case .rotors(let matches): return .rotors(try matches.map { try $0.resolve(in: environment) })
        case .exclude(let check): return .exclude(try check.resolve(in: environment))
        }
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: ElementPredicateCheckCodingKeys.self, typeName: "element predicate check")
        let container = try decoder.container(keyedBy: ElementPredicateCheckCodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        try rejectIrrelevantElementPredicateFields(for: kind, in: container)
        switch kind {
        case .label: self = .label(try container.decode(StringMatch.self, forKey: .match))
        case .identifier: self = .identifier(try container.decode(StringMatch.self, forKey: .match))
        case .value: self = .value(try container.decode(StringMatch.self, forKey: .match))
        case .hint: self = .hint(try container.decode(StringMatch.self, forKey: .match))
        case .traits: self = .traits(try container.decode([HeistTrait].self, forKey: .values).heistTraitSet)
        case .actions: self = .actions(Set(try container.decode([ElementAction].self, forKey: .values)))
        case .customContent: self = .customContent(try container.decode(CustomContentMatch.self, forKey: .match))
        case .rotors: self = .rotors(try container.decode([StringMatch].self, forKey: .values))
        case .exclude: self = .exclude(try container.decode(ElementPredicateCheck.self, forKey: .check))
        }
        if let description = invalidEmptyPayloadDescription {
            throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: description))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ElementPredicateCheckCodingKeys.self)
        switch self {
        case .label(let match):
            try container.encode(Kind.label, forKey: .kind)
            try container.encode(match, forKey: .match)
        case .identifier(let match):
            try container.encode(Kind.identifier, forKey: .kind)
            try container.encode(match, forKey: .match)
        case .value(let match):
            try container.encode(Kind.value, forKey: .kind)
            try container.encode(match, forKey: .match)
        case .hint(let match):
            try container.encode(Kind.hint, forKey: .kind)
            try container.encode(match, forKey: .match)
        case .traits(let traits):
            try container.encode(Kind.traits, forKey: .kind)
            try container.encode(traits.canonicalHeistTraitArray, forKey: .values)
        case .actions(let actions):
            try container.encode(Kind.actions, forKey: .kind)
            try container.encode(actions.canonicalElementActionArray, forKey: .values)
        case .customContent(let match):
            try container.encode(Kind.customContent, forKey: .kind)
            try container.encode(match, forKey: .match)
        case .rotors(let matches):
            try container.encode(Kind.rotors, forKey: .kind)
            try container.encode(matches, forKey: .values)
        case .exclude(let check):
            try container.encode(Kind.exclude, forKey: .kind)
            try container.encode(check, forKey: .check)
        }
    }

    private static func emptyStringPayloadDescription(_ match: StringMatch, field: String) -> String? {
        match.value?.literalIsEmpty == true ? "\(field) match value must not be empty" : nil
    }

}

extension ElementPredicateCheck: CustomStringConvertible {
    public var description: String {
        switch self {
        case .label(let match): return "label=\(match)"
        case .identifier(let match): return "identifier=\(match)"
        case .value(let match): return "value=\(match)"
        case .traits(let traits):
            return "traits=[\(traits.canonicalHeistTraitArray.map(\.rawValue).joined(separator: ", "))]"
        case .hint(let match): return "hint=\(match)"
        case .actions(let actions):
            return "actions=[\(actions.canonicalElementActionArray.map(\.description).joined(separator: ", "))]"
        case .customContent(let match): return "customContent=\(match)"
        case .rotors(let matches):
            return "rotors=[\(matches.map(\.description).joined(separator: ", "))]"
        case .exclude(let check): return "exclude(\(check))"
        }
    }
}

/// The canonical authored element predicate.
public struct ElementPredicate: Codable, Sendable, Equatable, Hashable {
    public let checks: [ElementPredicateCheck]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case checks
    }

    public init(_ checks: [ElementPredicateCheck] = []) {
        self.checks = checks
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
        checks = [
            label.map(ElementPredicateCheck.label),
            identifier.map(ElementPredicateCheck.identifier),
            value.map(ElementPredicateCheck.value),
            hint.map(ElementPredicateCheck.hint),
            customContent.map(ElementPredicateCheck.customContent),
            rotors.isEmpty ? nil : .rotors(rotors),
            traits.isEmpty ? nil : .traits(traits.heistTraitSet),
            actions.isEmpty ? nil : .actions(Set(actions)),
        ].compactMap { $0 }
    }

    public init(
        _ checks: [ElementPredicateCheck],
        traits: [HeistTrait] = [],
        actions: [ElementAction] = []
    ) {
        self.checks = checks + [
            traits.isEmpty ? nil : .traits(traits.heistTraitSet),
            actions.isEmpty ? nil : .actions(Set(actions)),
        ].compactMap { $0 }
    }

    public var hasPredicates: Bool { checks.contains { $0.hasPredicateLiteral } }

    public var invalidEmptyPayloadDescription: String? {
        if let description = checks.lazy.compactMap(\.invalidEmptyPayloadDescription).first {
            return description
        }
        return hasPredicates ? nil : AccessibilityTargetGrammarError.emptyPredicate.diagnosticDescription
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedElementPredicate {
        let resolved = ResolvedElementPredicate(try checks.map { try $0.resolve(in: environment) })
        if let mode = resolved.invalidEmptyBroadMode {
            throw HeistExpressionError.invalidStringMatch(mode: mode.rawValue)
        }
        if let description = resolved.invalidEmptyPayloadDescription {
            throw InvalidResolvedPredicateError(reason: description)
        }
        return resolved
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
        checks = try container.decodeIfPresent([ElementPredicateCheck].self, forKey: .checks) ?? []
        if requiresNonEmpty, let description = invalidEmptyPayloadDescription {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath + [CodingKeys.checks],
                debugDescription: description
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !checks.isEmpty {
            try container.encode(checks, forKey: .checks)
        }
    }
}

extension ElementPredicate: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("predicate", checks.map(\.description))
    }
}

package indirect enum ResolvedElementPredicateCheck: Codable, Sendable, Equatable, Hashable {
    case label(ResolvedStringMatch)
    case identifier(ResolvedStringMatch)
    case value(ResolvedStringMatch)
    case traits(Set<HeistTrait>)
    case hint(ResolvedStringMatch)
    case actions(Set<ElementAction>)
    case customContent(ResolvedCustomContentMatch)
    case rotors([ResolvedStringMatch])
    case exclude(ResolvedElementPredicateCheck)

    package var hasPredicateLiteral: Bool {
        switch self {
        case .label(let match), .identifier(let match), .value(let match), .hint(let match):
            return match.hasPredicateLiteral
        case .traits(let traits): return !traits.isEmpty
        case .actions(let actions): return !actions.isEmpty
        case .customContent(let match): return match.hasPredicateLiteral
        case .rotors(let matches): return matches.contains { $0.hasPredicateLiteral }
        case .exclude(let check): return check.hasPredicateLiteral
        }
    }

    package var invalidEmptyBroadMode: StringMatch.Mode? {
        switch self {
        case .label(let match), .identifier(let match), .value(let match), .hint(let match):
            return match.invalidEmptyBroadMode
        case .customContent(let match):
            return [match.label, match.value].compactMap { $0 }
                .compactMap(\.invalidEmptyBroadMode).first
        case .rotors(let matches):
            return matches.lazy.compactMap(\.invalidEmptyBroadMode).first
        case .exclude(let check):
            return check.invalidEmptyBroadMode
        case .traits, .actions:
            return nil
        }
    }

    package var invalidEmptyPayloadDescription: String? {
        switch self {
        case .label(let match):
            return Self.emptyStringPayloadDescription(match, field: "label")
        case .identifier(let match):
            return Self.emptyStringPayloadDescription(match, field: "identifier")
        case .value(let match):
            return Self.emptyStringPayloadDescription(match, field: "value")
        case .hint(let match):
            return Self.emptyStringPayloadDescription(match, field: "hint")
        case .traits(let traits):
            return traits.isEmpty ? "traits check must not be empty" : nil
        case .actions(let actions):
            return actions.isEmpty ? "actions check must not be empty" : nil
        case .customContent(let match):
            if let description = match.label.flatMap({
                Self.emptyStringPayloadDescription($0, field: "customContent label")
            }) {
                return description
            }
            if let description = match.value.flatMap({
                Self.emptyStringPayloadDescription($0, field: "customContent value")
            }) {
                return description
            }
            return match.hasPredicateLiteral ? nil : "customContent match must include label, value, or isImportant"
        case .rotors(let matches):
            if matches.isEmpty {
                return "rotors check must not be empty"
            }
            return matches.lazy.compactMap { Self.emptyStringPayloadDescription($0, field: "rotor") }.first
        case .exclude(let check):
            if let description = check.invalidEmptyPayloadDescription {
                return "excluded \(description)"
            }
            return check.hasPredicateLiteral ? nil : "exclude check must not be empty"
        }
    }

    package func matches(_ subject: some ElementPredicateSubject) -> Bool {
        switch self {
        case .exclude(let check):
            return !check.matches(subject)
        case .label, .identifier, .value, .hint, .traits, .actions, .customContent, .rotors:
            return matchesSubject(subject)
        }
    }

    fileprivate func matchesSubject(_ subject: some ElementPredicateSubject) -> Bool {
        switch self {
        case .label(let match): return match.matches(optional: subject.predicateLabel)
        case .identifier(let match): return match.matches(optional: subject.predicateIdentifier)
        case .value(let match): return match.matches(optional: subject.predicateValue)
        case .hint(let match): return match.matches(optional: subject.predicateHint)
        case .traits(let traits): return traits.isEmpty || subject.satisfiesRequiredTraits(traits)
        case .actions(let actions): return actions.isEmpty || subject.satisfiesRequiredActions(actions)
        case .customContent(let match):
            return !match.hasPredicateLiteral || subject.containsCustomContent(matching: match)
        case .rotors(let matches): return matches.isEmpty || subject.satisfiesRequiredRotors(matches)
        case .exclude: return false
        }
    }

    package init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: ElementPredicateCheckCodingKeys.self, typeName: "element predicate check")
        let container = try decoder.container(keyedBy: ElementPredicateCheckCodingKeys.self)
        let kind = try container.decode(ElementPredicateCheck.Kind.self, forKey: .kind)
        try rejectIrrelevantElementPredicateFields(for: kind, in: container)
        switch kind {
        case .label: self = .label(try container.decode(ResolvedStringMatch.self, forKey: .match))
        case .identifier: self = .identifier(try container.decode(ResolvedStringMatch.self, forKey: .match))
        case .value: self = .value(try container.decode(ResolvedStringMatch.self, forKey: .match))
        case .hint: self = .hint(try container.decode(ResolvedStringMatch.self, forKey: .match))
        case .traits: self = .traits(try container.decode([HeistTrait].self, forKey: .values).heistTraitSet)
        case .actions: self = .actions(Set(try container.decode([ElementAction].self, forKey: .values)))
        case .customContent:
            self = .customContent(try container.decode(ResolvedCustomContentMatch.self, forKey: .match))
        case .rotors: self = .rotors(try container.decode([ResolvedStringMatch].self, forKey: .values))
        case .exclude: self = .exclude(try container.decode(ResolvedElementPredicateCheck.self, forKey: .check))
        }
        if let description = invalidEmptyPayloadDescription {
            throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: description))
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ElementPredicateCheckCodingKeys.self)
        switch self {
        case .label(let match):
            try container.encode(ElementPredicateCheck.Kind.label, forKey: .kind)
            try container.encode(match, forKey: .match)
        case .identifier(let match):
            try container.encode(ElementPredicateCheck.Kind.identifier, forKey: .kind)
            try container.encode(match, forKey: .match)
        case .value(let match):
            try container.encode(ElementPredicateCheck.Kind.value, forKey: .kind)
            try container.encode(match, forKey: .match)
        case .hint(let match):
            try container.encode(ElementPredicateCheck.Kind.hint, forKey: .kind)
            try container.encode(match, forKey: .match)
        case .traits(let traits):
            try container.encode(ElementPredicateCheck.Kind.traits, forKey: .kind)
            try container.encode(traits.canonicalHeistTraitArray, forKey: .values)
        case .actions(let actions):
            try container.encode(ElementPredicateCheck.Kind.actions, forKey: .kind)
            try container.encode(actions.canonicalElementActionArray, forKey: .values)
        case .customContent(let match):
            try container.encode(ElementPredicateCheck.Kind.customContent, forKey: .kind)
            try container.encode(match, forKey: .match)
        case .rotors(let matches):
            try container.encode(ElementPredicateCheck.Kind.rotors, forKey: .kind)
            try container.encode(matches, forKey: .values)
        case .exclude(let check):
            try container.encode(ElementPredicateCheck.Kind.exclude, forKey: .kind)
            try container.encode(check, forKey: .check)
        }
    }

    private static func emptyStringPayloadDescription(_ match: ResolvedStringMatch, field: String) -> String? {
        match.value?.isEmpty == true ? "\(field) match value must not be empty" : nil
    }
}

extension ResolvedElementPredicateCheck: CustomStringConvertible {
    package var description: String {
        switch self {
        case .label(let match): return "label=\(match)"
        case .identifier(let match): return "identifier=\(match)"
        case .value(let match): return "value=\(match)"
        case .traits(let traits):
            return "traits=[\(traits.canonicalHeistTraitArray.map(\.rawValue).joined(separator: ", "))]"
        case .hint(let match): return "hint=\(match)"
        case .actions(let actions):
            return "actions=[\(actions.canonicalElementActionArray.map(\.description).joined(separator: ", "))]"
        case .customContent(let match): return "customContent=\(match)"
        case .rotors(let matches):
            return "rotors=[\(matches.map(\.description).joined(separator: ", "))]"
        case .exclude(let check): return "exclude(\(check))"
        }
    }
}

/// A resolved element predicate. This type cannot contain references.
package struct ResolvedElementPredicate: Codable, Sendable, Equatable, Hashable {
    package let checks: [ResolvedElementPredicateCheck]

    package init(_ checks: [ResolvedElementPredicateCheck] = []) {
        self.checks = checks
    }

    package var hasPredicates: Bool { checks.contains { $0.hasPredicateLiteral } }
    package var invalidEmptyBroadMode: StringMatch.Mode? {
        checks.lazy.compactMap(\.invalidEmptyBroadMode).first
    }
    package var invalidEmptyPayloadDescription: String? {
        if let description = checks.lazy.compactMap(\.invalidEmptyPayloadDescription).first {
            return description
        }
        return hasPredicates ? nil : AccessibilityTargetGrammarError.emptyPredicate.diagnosticDescription
    }

    package static func label(_ label: String) -> Self {
        Self([.label(.exact(label))])
    }

    package static func identifier(_ identifier: String) -> Self {
        Self([.identifier(.exact(identifier))])
    }

    package static func value(_ value: String) -> Self {
        Self([.value(.exact(value))])
    }

    package static func hint(_ hint: String) -> Self {
        Self([.hint(.exact(hint))])
    }

    package static func traits(_ traits: [HeistTrait]) -> Self {
        Self([.traits(traits.heistTraitSet)])
    }

    package static func actions(_ actions: [ElementAction]) -> Self {
        Self([.actions(Set(actions))])
    }

    package init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: ElementPredicate.CodingKeys.self, typeName: "element predicate")
        let container = try decoder.container(keyedBy: ElementPredicate.CodingKeys.self)
        checks = try container.decodeIfPresent([ResolvedElementPredicateCheck].self, forKey: .checks) ?? []
        if let description = invalidEmptyPayloadDescription {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: description))
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ElementPredicate.CodingKeys.self)
        if !checks.isEmpty {
            try container.encode(checks, forKey: .checks)
        }
    }
}

extension ResolvedElementPredicate: CustomStringConvertible {
    package var description: String {
        CanonicalValueDescription.call("predicate", checks.map(\.description))
    }
}

package protocol ElementPredicateSubject {
    var predicateLabel: String? { get }
    var predicateIdentifier: String? { get }
    var predicateValue: String? { get }
    var predicateHint: String? { get }
    func satisfiesRequiredTraits(_ required: Set<HeistTrait>) -> Bool
    func satisfiesRequiredActions(_ required: Set<ElementAction>) -> Bool
    func containsCustomContent(matching match: ResolvedCustomContentMatch) -> Bool
    func satisfiesRequiredRotors(_ required: [ResolvedStringMatch]) -> Bool
}

package protocol ElementPredicateSubjectBacked: ElementPredicateSubject {
    associatedtype BackingSubject: ElementPredicateSubject
    var predicateSubject: BackingSubject { get }
}

package extension ElementPredicateSubjectBacked {
    var predicateLabel: String? { predicateSubject.predicateLabel }
    var predicateIdentifier: String? { predicateSubject.predicateIdentifier }
    var predicateValue: String? { predicateSubject.predicateValue }
    var predicateHint: String? { predicateSubject.predicateHint }

    func satisfiesRequiredTraits(_ required: Set<HeistTrait>) -> Bool {
        predicateSubject.satisfiesRequiredTraits(required)
    }

    func satisfiesRequiredActions(_ required: Set<ElementAction>) -> Bool {
        predicateSubject.satisfiesRequiredActions(required)
    }

    func containsCustomContent(matching match: ResolvedCustomContentMatch) -> Bool {
        predicateSubject.containsCustomContent(matching: match)
    }

    func satisfiesRequiredRotors(_ required: [ResolvedStringMatch]) -> Bool {
        predicateSubject.satisfiesRequiredRotors(required)
    }
}

package extension ResolvedElementPredicate {
    func matches(_ subject: some ElementPredicateSubject) -> Bool {
        hasPredicates && checks.allSatisfy { $0.matches(subject) }
    }
}

package struct ElementPredicateMatch<Identity: Hashable, Subject: ElementPredicateSubject> {
    package let identity: Identity
    package let traversalOrder: Int
    package let subject: Subject

    package init(identity: Identity, traversalOrder: Int, subject: Subject) {
        self.identity = identity
        self.traversalOrder = traversalOrder
        self.subject = subject
    }
}

package struct ElementPredicateMatchSet<Identity: Hashable, Subject: ElementPredicateSubject> {
    package static var empty: ElementPredicateMatchSet<Identity, Subject> {
        ElementPredicateMatchSet([])
    }

    package let matches: [ElementPredicateMatch<Identity, Subject>]
    private let identities: Set<Identity>

    package init(_ matches: [ElementPredicateMatch<Identity, Subject>]) {
        var identities = Set<Identity>()
        let uniqueMatches = matches.filter { identities.insert($0.identity).inserted }
        self.matches = uniqueMatches.sorted { $0.traversalOrder < $1.traversalOrder }
        self.identities = identities
    }

    package var isEmpty: Bool { matches.isEmpty }
    package var count: Int { matches.count }
    package var subjects: [Subject] { matches.map(\.subject) }

    package func intersection(
        _ other: ElementPredicateMatchSet<Identity, Subject>
    ) -> ElementPredicateMatchSet<Identity, Subject> {
        ElementPredicateMatchSet(matches.filter { other.identities.contains($0.identity) })
    }

    package func subtracting(
        _ other: ElementPredicateMatchSet<Identity, Subject>
    ) -> ElementPredicateMatchSet<Identity, Subject> {
        ElementPredicateMatchSet(matches.filter { !other.identities.contains($0.identity) })
    }
}

package struct ElementPredicateGraph<Identity: Hashable, Subject: ElementPredicateSubject> {
    private let all: ElementPredicateMatchSet<Identity, Subject>

    package init(matches: [ElementPredicateMatch<Identity, Subject>]) {
        all = ElementPredicateMatchSet(matches)
    }

    package init<Subjects: Sequence>(
        subjects: Subjects,
        identity: KeyPath<Subject, Identity>
    ) where Subjects.Element == Subject {
        self.init(matches: subjects.enumerated().map { offset, subject in
            ElementPredicateMatch(identity: subject[keyPath: identity], traversalOrder: offset, subject: subject)
        })
    }

    package init<Subjects: Sequence>(
        subjects: Subjects,
        identity: KeyPath<Subject, Identity>,
        traversalOrder: KeyPath<Subject, Int>
    ) where Subjects.Element == Subject {
        self.init(matches: subjects.map { subject in
            ElementPredicateMatch(
                identity: subject[keyPath: identity],
                traversalOrder: subject[keyPath: traversalOrder],
                subject: subject
            )
        })
    }

    package func resolve(_ predicate: ResolvedElementPredicate) -> ElementPredicateMatchSet<Identity, Subject> {
        guard predicate.hasPredicates else { return .empty }
        return ElementPredicateMatchSet(
            all.matches.filter { match in predicate.checks.allSatisfy { $0.matches(match.subject) } }
        )
    }

    package func resolve(_ target: ResolvedAccessibilityTarget) -> ElementPredicateMatchSet<Identity, Subject> {
        guard case .predicate(let predicate, let ordinal) = target else { return .empty }
        let predicateMatches = resolve(predicate)
        guard let ordinal else { return predicateMatches }
        guard predicateMatches.matches.indices.contains(ordinal) else { return .empty }
        return ElementPredicateMatchSet([predicateMatches.matches[ordinal]])
    }

    package func resolve(
        _ check: ResolvedElementPredicateCheck
    ) -> ElementPredicateMatchSet<Identity, Subject> {
        switch check {
        case .exclude(let excluded):
            return all.subtracting(resolve(excluded))
        case .label, .identifier, .value, .hint, .traits, .actions, .customContent, .rotors:
            return ElementPredicateMatchSet(all.matches.filter { check.matchesSubject($0.subject) })
        }
    }
}

public extension ElementPredicate {
    static func stringEquals(_ candidate: String, _ pattern: String) -> Bool {
        normalizeTypography(candidate)
            .localizedCaseInsensitiveCompare(normalizeTypography(pattern)) == .orderedSame
    }

    static func stringContains(_ candidate: String, _ pattern: String) -> Bool {
        normalizeTypography(candidate)
            .localizedCaseInsensitiveContains(normalizeTypography(pattern))
    }

    static func stringHasPrefix(_ candidate: String, _ pattern: String) -> Bool {
        normalizeTypography(candidate)
            .range(of: normalizeTypography(pattern), options: [.anchored, .caseInsensitive]) != nil
    }

    static func stringHasSuffix(_ candidate: String, _ pattern: String) -> Bool {
        normalizeTypography(candidate)
            .range(of: normalizeTypography(pattern), options: [.anchored, .backwards, .caseInsensitive]) != nil
    }

    static func normalizeTypography(_ string: String) -> String {
        guard string.unicodeScalars.contains(where: { typographicAsciiFold[$0] != nil }) else {
            return string
        }
        var result = ""
        result.reserveCapacity(string.count)
        for scalar in string.unicodeScalars {
            if let replacement = typographicAsciiFold[scalar] {
                result.append(replacement)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static let typographicAsciiFold: [Unicode.Scalar: String] = [
        "\u{2018}": "'", "\u{2019}": "'", "\u{201A}": "'", "\u{201B}": "'", "\u{2032}": "'",
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{201F}": "\"", "\u{2033}": "\"",
        "\u{2010}": "-", "\u{2011}": "-", "\u{2012}": "-", "\u{2013}": "-", "\u{2014}": "-",
        "\u{2015}": "-", "\u{2212}": "-", "\u{2026}": "...", "\u{00A0}": " ",
        "\u{2007}": " ", "\u{202F}": " ",
    ]
}
