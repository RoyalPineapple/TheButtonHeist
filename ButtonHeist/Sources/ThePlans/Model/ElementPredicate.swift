import Foundation

// MARK: - String Matching

public protocol StringMatchPayload: Codable, Sendable, Equatable, Hashable {
    /// Literal emptiness when it is knowable without resolving runtime refs.
    var stringMatchLiteralIsEmpty: Bool? { get }
}

extension String: StringMatchPayload {
    public var stringMatchLiteralIsEmpty: Bool? { isEmpty }
}

/// Shared representation for predicate string comparison.
///
/// Literal Swift values create exact matches. Public JSON boundaries spell the
/// selected mode explicitly through their request schema.
public enum StringMatch<Value: StringMatchPayload>: Sendable, Equatable, Hashable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// Exact string match. This is the default for string literals.
        case exact
        /// Explicit substring match. Authors opt into this broad match mode.
        case contains
        /// Explicit prefix match.
        case prefix
        /// Explicit suffix match.
        case suffix
        /// Match an empty string.
        case isEmpty
    }

    case exact(Value)
    case contains(Value)
    case prefix(Value)
    case suffix(Value)
    case isEmpty

    public init(_ value: Value) {
        self = .exact(value)
    }

    public init(mode: Mode, value: Value) {
        switch mode {
        case .exact:
            self = .exact(value)
        case .contains:
            self = .contains(value)
        case .prefix:
            self = .prefix(value)
        case .suffix:
            self = .suffix(value)
        case .isEmpty:
            self = .isEmpty
        }
    }

    public var mode: Mode {
        switch self {
        case .exact:
            return .exact
        case .contains:
            return .contains
        case .prefix:
            return .prefix
        case .suffix:
            return .suffix
        case .isEmpty:
            return .isEmpty
        }
    }

    public var value: Value {
        guard let value = valueIfPresent else {
            preconditionFailure("isEmpty string match has no value")
        }
        return value
    }

    public var valueIfPresent: Value? {
        switch self {
        case .exact(let value), .contains(let value), .prefix(let value), .suffix(let value):
            return value
        case .isEmpty:
            return nil
        }
    }

    public var isExact: Bool {
        mode == .exact
    }

    public var hasInvalidEmptyBroadLiteral: Bool {
        switch self {
        case .contains(let value), .prefix(let value), .suffix(let value):
            return value.stringMatchLiteralIsEmpty == true
        case .exact, .isEmpty:
            return false
        }
    }

    public var hasPredicateLiteral: Bool {
        valueIfPresent?.stringMatchLiteralIsEmpty != true
    }

    public func map<NewValue: StringMatchPayload>(
        _ transform: (Value) throws -> NewValue
    ) rethrows -> StringMatch<NewValue> {
        switch self {
        case .exact(let value):
            return try .exact(transform(value))
        case .contains(let value):
            return try .contains(transform(value))
        case .prefix(let value):
            return try .prefix(transform(value))
        case .suffix(let value):
            return try .suffix(transform(value))
        case .isEmpty:
            return .isEmpty
        }
    }
}

extension StringMatch: ExpressibleByUnicodeScalarLiteral
where Value: ExpressibleByStringLiteral, Value.StringLiteralType == String {
    public init(unicodeScalarLiteral value: String) {
        self = .exact(Value(stringLiteral: value))
    }
}

extension StringMatch: ExpressibleByExtendedGraphemeClusterLiteral
where Value: ExpressibleByStringLiteral, Value.StringLiteralType == String {
    public init(extendedGraphemeClusterLiteral value: String) {
        self = .exact(Value(stringLiteral: value))
    }
}

extension StringMatch: ExpressibleByStringLiteral where Value: ExpressibleByStringLiteral, Value.StringLiteralType == String {
    public init(stringLiteral value: String) {
        self = .exact(Value(stringLiteral: value))
    }
}

extension StringMatch: Codable where Value: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case mode, value
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "string match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decode(Mode.self, forKey: .mode)
        if mode == .isEmpty {
            if container.contains(.value) {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "isEmpty string match must not include value"
                )
            }
            self = .isEmpty
            return
        }
        let value = try container.decode(Value.self, forKey: .value)
        self = StringMatch(mode: mode, value: value)
        if hasInvalidEmptyBroadLiteral {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "\(mode.rawValue) string match value must not be empty"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if case .isEmpty = self {
            try container.encode(mode, forKey: .mode)
            return
        }
        try container.encode(mode, forKey: .mode)
        try container.encode(value, forKey: .value)
    }
}

extension StringMatch: CustomStringConvertible {
    public var description: String {
        switch self {
        case .exact(let value):
            return String(describing: value)
        case .contains(let value):
            return "contains(\(value))"
        case .prefix(let value):
            return "prefix(\(value))"
        case .suffix(let value):
            return "suffix(\(value))"
        case .isEmpty:
            return "isEmpty"
        }
    }
}

public extension StringMatch where Value == String {
    func matches(optional candidate: String?) -> Bool {
        if case .isEmpty = self {
            return (candidate ?? "").isEmpty
        }
        guard let candidate else { return false }
        return matches(candidate)
    }

    func matches(_ candidate: String) -> Bool {
        switch self {
        case .exact(let pattern):
            guard !pattern.isEmpty else { return false }
            return ElementPredicate.stringEquals(candidate, pattern)
        case .contains(let pattern):
            guard !pattern.isEmpty else { return false }
            return ElementPredicate.stringContains(candidate, pattern)
        case .prefix(let pattern):
            guard !pattern.isEmpty else { return false }
            return ElementPredicate.stringHasPrefix(candidate, pattern)
        case .suffix(let pattern):
            guard !pattern.isEmpty else { return false }
            return ElementPredicate.stringHasSuffix(candidate, pattern)
        case .isEmpty:
            return candidate.isEmpty
        }
    }

}

public extension StringMatch where Value: Codable {
    static func decodeOneOrMany<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> [Self] {
        guard container.contains(key) else { return [] }
        let decoder = try container.superDecoder(forKey: key)
        if (try? decoder.unkeyedContainer()) != nil {
            return try [Self](from: decoder)
        }
        return [try Self(from: decoder)]
    }

    static func encodeOneOrMany<Key: CodingKey>(
        _ matches: [Self],
        to container: inout KeyedEncodingContainer<Key>,
        forKey key: Key
    ) throws {
        switch matches.count {
        case 0:
            break
        case 1:
            try container.encode(matches[0], forKey: key)
        default:
            try container.encode(matches, forKey: key)
        }
    }
}

public enum ElementPredicateCheck<Text: StringMatchPayload>: Sendable, Equatable, Hashable {
    case label(StringMatch<Text>)
    case identifier(StringMatch<Text>)
    case value(StringMatch<Text>)
    case traits(Set<HeistTrait>)
    case hint(StringMatch<Text>)
    case actions(Set<ElementAction>)
    case customContent(CustomContentMatch<Text>)
    case rotors([StringMatch<Text>])
    indirect case exclude(ElementPredicateCheck<Text>)

    public var hasPredicateLiteral: Bool {
        switch self {
        case .label(let match), .identifier(let match), .value(let match):
            return match.hasPredicateLiteral
        case .traits(let traits):
            return !traits.isEmpty
        case .hint(let match):
            return match.hasPredicateLiteral
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
            if actions.isEmpty {
                return "actions check must not be empty"
            }
            return actions.invalidElementActionPayloadDescription
        case .customContent(let match):
            if let description = match.label.flatMap({ Self.emptyStringPayloadDescription($0, field: "customContent label") }) {
                return description
            }
            if let description = match.value.flatMap({ Self.emptyStringPayloadDescription($0, field: "customContent value") }) {
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

    private static func emptyStringPayloadDescription(_ match: StringMatch<Text>, field: String) -> String? {
        match.valueIfPresent?.stringMatchLiteralIsEmpty == true ? "\(field) match value must not be empty" : nil
    }

    public func map<NewText: StringMatchPayload>(
        _ transform: (Text) throws -> NewText
    ) rethrows -> ElementPredicateCheck<NewText> {
        switch self {
        case .label(let match):
            return try .label(match.map(transform))
        case .identifier(let match):
            return try .identifier(match.map(transform))
        case .value(let match):
            return try .value(match.map(transform))
        case .traits(let traits):
            return .traits(traits)
        case .hint(let match):
            return try .hint(match.map(transform))
        case .actions(let actions):
            return .actions(actions)
        case .customContent(let match):
            return try .customContent(match.map(transform))
        case .rotors(let matches):
            return try .rotors(matches.map { try $0.map(transform) })
        case .exclude(let check):
            return try .exclude(check.map(transform))
        }
    }
}

// MARK: - Element Predicate

/// The canonical predicate for matching a single accessibility element.
///
/// Predicates are ordered check chains. Matching is equivalent to `&&` over the
/// checks; diagnostics can use the same order to explain where a candidate first
/// failed.
public struct ElementPredicate: Sendable, Equatable, Hashable {
    /// Ordered checks against one accessibility element. All checks must pass.
    public let checks: [ElementPredicateCheck<String>]

    public init(_ checks: [ElementPredicateCheck<String>] = []) {
        self.checks = checks
    }

    public init(
        label: StringMatch<String>? = nil,
        identifier: StringMatch<String>? = nil,
        value: StringMatch<String>? = nil,
        traits: [HeistTrait] = [],
        hint: StringMatch<String>? = nil,
        actions: [ElementAction] = [],
        customContent: CustomContentMatch<String>? = nil,
        rotors: [StringMatch<String>] = []
    ) {
        self.init(Self.checks(
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
        _ checks: [ElementPredicateCheck<String>],
        traits: [HeistTrait] = [],
        actions: [ElementAction] = []
    ) {
        self.init(checks + Self.setChecks(
            traits: traits,
            actions: actions
        ))
    }

    /// Whether any predicate is set. Empty string and empty trait collection
    /// checks are treated as unset: they match nothing rather than everything.
    public var hasPredicates: Bool {
        checks.contains { $0.hasPredicateLiteral }
    }

    /// Returns `self` when at least one predicate field is set, else `nil`.
    public var nonEmpty: Self? { hasPredicates ? self : nil }

    public var invalidEmptyPayloadDescription: String? {
        if let description = checks.lazy.compactMap(\.invalidEmptyPayloadDescription).first {
            return description
        }
        return hasPredicates ? nil : AccessibilityTargetGrammarError.emptyPredicate.diagnosticDescription
    }

    private static func checks(
        label: StringMatch<String>?,
        identifier: StringMatch<String>?,
        value: StringMatch<String>?,
        traits: [HeistTrait],
        hint: StringMatch<String>?,
        actions: [ElementAction],
        customContent: CustomContentMatch<String>?,
        rotors: [StringMatch<String>]
    ) -> [ElementPredicateCheck<String>] {
        var checks: [ElementPredicateCheck<String>] = []
        if let label { checks.append(.label(label)) }
        if let identifier { checks.append(.identifier(identifier)) }
        if let value { checks.append(.value(value)) }
        if let hint { checks.append(.hint(hint)) }
        if let customContent { checks.append(.customContent(customContent)) }
        if !rotors.isEmpty { checks.append(.rotors(rotors)) }
        checks += setChecks(
            traits: traits,
            actions: actions
        )
        return checks
    }

    private static func setChecks(
        traits: [HeistTrait],
        actions: [ElementAction]
    ) -> [ElementPredicateCheck<String>] {
        var checks: [ElementPredicateCheck<String>] = []
        let traits = traits.heistTraitSet
        if !traits.isEmpty { checks.append(.traits(traits)) }
        let actions = Set(actions)
        if !actions.isEmpty { checks.append(.actions(actions)) }
        return checks
    }
}

// MARK: - Convenience Constructors

public extension ElementPredicate {
    /// Match by exact label.
    static func label(_ label: String) -> ElementPredicate {
        ElementPredicate(label: StringMatch(label))
    }

    /// Match by label alone.
    static func label(_ label: StringMatch<String>) -> ElementPredicate {
        ElementPredicate(label: label)
    }

    /// Match by exact accessibility identifier.
    static func identifier(_ identifier: String) -> ElementPredicate {
        ElementPredicate(identifier: StringMatch(identifier))
    }

    /// Match by accessibility identifier alone.
    static func identifier(_ identifier: StringMatch<String>) -> ElementPredicate {
        ElementPredicate(identifier: identifier)
    }

    /// Match by exact value.
    static func value(_ value: String) -> ElementPredicate {
        ElementPredicate(value: StringMatch(value))
    }

    /// Match by value alone.
    static func value(_ value: StringMatch<String>) -> ElementPredicate {
        ElementPredicate(value: value)
    }

    /// Match by hint alone.
    static func hint(_ hint: String) -> ElementPredicate {
        ElementPredicate(hint: StringMatch(hint))
    }

    /// Match by hint alone.
    static func hint(_ hint: StringMatch<String>) -> ElementPredicate {
        ElementPredicate(hint: hint)
    }

    /// Match elements that include every listed trait.
    static func traits(_ traits: [HeistTrait]) -> ElementPredicate {
        ElementPredicate(traits: traits)
    }

    /// Match elements that include every listed action.
    static func actions(_ actions: [ElementAction]) -> ElementPredicate {
        ElementPredicate(actions: actions)
    }

    /// Match elements that include at least one custom-content item satisfying the checker.
    static func customContent(_ match: CustomContentMatch<String>) -> ElementPredicate {
        ElementPredicate(customContent: match)
    }

    /// Match elements that include every listed rotor name.
    static func rotors(_ rotors: [StringMatch<String>]) -> ElementPredicate {
        ElementPredicate(rotors: rotors)
    }

    /// Exclude elements that satisfy a single predicate check.
    static func exclude(_ check: ElementPredicateCheck<String>) -> ElementPredicate {
        ElementPredicate([.exclude(check)])
    }

    /// Match by an ordered list of property checks. Repeating a property means
    /// every check against that property must pass.
    static func element(
        _ checks: ElementPredicateCheck<String>...,
        traits: [HeistTrait] = [],
        actions: [ElementAction] = []
    ) -> ElementPredicate {
        ElementPredicate(
            checks,
            traits: traits,
            actions: actions
        )
    }
}

// MARK: - Evaluation

/// A value that an `ElementPredicate` can be evaluated against. The string
/// fields are read directly; trait inclusion/exclusion is delegated so each
/// subject keeps its own trait representation (client `Set<HeistTrait>` vs
/// server UIKit bitmask) while the predicate walk lives in one place.
package protocol ElementPredicateSubject {
    var predicateLabel: String? { get }
    var predicateIdentifier: String? { get }
    var predicateValue: String? { get }
    var predicateHint: String? { get }
    /// True when every required trait is present (and known) on the subject.
    func satisfiesRequiredTraits(_ required: Set<HeistTrait>) -> Bool
    /// True when every required action is present on the subject.
    func satisfiesRequiredActions(_ required: Set<ElementAction>) -> Bool
    /// True when the subject has at least one custom-content item satisfying the checker.
    func containsCustomContent(matching match: CustomContentMatch<String>) -> Bool
    /// True when every required rotor match is present on the subject.
    func satisfiesRequiredRotors(_ required: [StringMatch<String>]) -> Bool
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

    func containsCustomContent(matching match: CustomContentMatch<String>) -> Bool {
        predicateSubject.containsCustomContent(matching: match)
    }

    func satisfiesRequiredRotors(_ required: [StringMatch<String>]) -> Bool {
        predicateSubject.satisfiesRequiredRotors(required)
    }
}

package extension ElementPredicate {
    /// The single source of truth for predicate evaluation.
    func matches(_ subject: some ElementPredicateSubject) -> Bool {
        ElementPredicateGraph(matches: [
            ElementPredicateMatch(identity: 0, traversalOrder: 0, subject: subject),
        ])
            .resolve(self)
            .count == 1
    }

}

// MARK: - Predicate Match Graph

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
        var uniqueMatches: [ElementPredicateMatch<Identity, Subject>] = []
        uniqueMatches.reserveCapacity(matches.count)

        for match in matches where identities.insert(match.identity).inserted {
            uniqueMatches.append(match)
        }

        self.matches = uniqueMatches.sorted { $0.traversalOrder < $1.traversalOrder }
        self.identities = identities
    }

    package var isEmpty: Bool {
        matches.isEmpty
    }

    package var count: Int {
        matches.count
    }

    package var subjects: [Subject] {
        matches.map(\.subject)
    }

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
            ElementPredicateMatch(
                identity: subject[keyPath: identity],
                traversalOrder: offset,
                subject: subject
            )
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

    package func resolve(_ predicate: ElementPredicate) -> ElementPredicateMatchSet<Identity, Subject> {
        guard predicate.hasPredicates else { return .empty }
        return predicate.checks.reduce(all) { narrowed, check in
            narrowed.intersection(resolve(check))
        }
    }

    package func resolve(_ target: AccessibilityTarget) -> ElementPredicateMatchSet<Identity, Subject> {
        switch target {
        case .predicate(let predicate, let ordinal):
            guard let predicate = try? predicate.resolve(in: .empty) else { return .empty }
            let predicateMatches = resolve(predicate)
            guard let ordinal else { return predicateMatches }
            guard predicateMatches.matches.indices.contains(ordinal) else { return .empty }
            return ElementPredicateMatchSet([predicateMatches.matches[ordinal]])
        case .container, .ref, .within:
            return .empty
        }
    }

    package func resolve(_ check: ElementPredicateCheck<String>) -> ElementPredicateMatchSet<Identity, Subject> {
        switch check {
        case .exclude(let excluded):
            return all.subtracting(resolve(excluded))
        case .label, .identifier, .value, .hint, .traits, .actions, .customContent, .rotors:
            return ElementPredicateMatchSet(all.matches.filter { check.matchesSubject($0.subject) })
        }
    }
}

// MARK: - Codable

extension ElementPredicate: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case checks
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decodeIfPresent([ElementPredicateCheck<String>].self, forKey: .checks) ?? [])
        if let description = invalidEmptyPayloadDescription {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath + [CodingKeys.checks],
                debugDescription: description
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !checks.isEmpty { try container.encode(checks, forKey: .checks) }
    }

}

extension ElementPredicate: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("predicate", checks.compactMap(ScoreDescription.predicateCheckField))
    }
}

extension ElementPredicateCheck: Codable where Text: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, match, values, check
    }

    package enum Kind: String, Codable, CaseIterable {
        case label, identifier, value, hint
        case traits, actions, customContent, rotors
        case exclude
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element predicate check")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .label:
            try Self.rejectIrrelevantField(.values, in: container, forKind: .label)
            try Self.rejectIrrelevantField(.check, in: container, forKind: .label)
            self = .label(try container.decode(StringMatch<Text>.self, forKey: .match))
        case .identifier:
            try Self.rejectIrrelevantField(.values, in: container, forKind: .identifier)
            try Self.rejectIrrelevantField(.check, in: container, forKind: .identifier)
            self = .identifier(try container.decode(StringMatch<Text>.self, forKey: .match))
        case .value:
            try Self.rejectIrrelevantField(.values, in: container, forKind: .value)
            try Self.rejectIrrelevantField(.check, in: container, forKind: .value)
            self = .value(try container.decode(StringMatch<Text>.self, forKey: .match))
        case .hint:
            try Self.rejectIrrelevantField(.values, in: container, forKind: .hint)
            try Self.rejectIrrelevantField(.check, in: container, forKind: .hint)
            self = .hint(try container.decode(StringMatch<Text>.self, forKey: .match))
        case .traits:
            try Self.rejectIrrelevantField(.match, in: container, forKind: .traits)
            try Self.rejectIrrelevantField(.check, in: container, forKind: .traits)
            self = .traits(try container.decode([HeistTrait].self, forKey: .values).heistTraitSet)
        case .actions:
            try Self.rejectIrrelevantField(.match, in: container, forKind: .actions)
            try Self.rejectIrrelevantField(.check, in: container, forKind: .actions)
            self = .actions(Set(try container.decode([ElementAction].self, forKey: .values)))
        case .customContent:
            try Self.rejectIrrelevantField(.values, in: container, forKind: .customContent)
            try Self.rejectIrrelevantField(.check, in: container, forKind: .customContent)
            self = .customContent(try container.decode(CustomContentMatch<Text>.self, forKey: .match))
        case .rotors:
            try Self.rejectIrrelevantField(.match, in: container, forKind: .rotors)
            try Self.rejectIrrelevantField(.check, in: container, forKind: .rotors)
            self = .rotors(try container.decode([StringMatch<Text>].self, forKey: .values))
        case .exclude:
            try Self.rejectIrrelevantField(.match, in: container, forKind: .exclude)
            try Self.rejectIrrelevantField(.values, in: container, forKind: .exclude)
            self = .exclude(try container.decode(ElementPredicateCheck<Text>.self, forKey: .check))
        }
        if let description = invalidEmptyPayloadDescription {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: description
            ))
        }
    }

    private static func rejectIrrelevantField(
        _ key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>,
        forKind kind: Kind
    ) throws {
        guard container.contains(key) else { return }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "\(key.stringValue) is not valid for \(kind.rawValue) element predicate checks"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
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
}

package extension ElementPredicateCheck where Text == String {
    func matches(_ subject: some ElementPredicateSubject) -> Bool {
        switch self {
        case .exclude(let check):
            return !check.matches(subject)
        case .label, .identifier, .value, .hint, .traits, .actions, .customContent, .rotors:
            return matchesSubject(subject)
        }
    }

    fileprivate func matchesSubject(_ subject: some ElementPredicateSubject) -> Bool {
        switch self {
        case .label(let match):
            return match.matches(optional: subject.predicateLabel)
        case .identifier(let match):
            return match.matches(optional: subject.predicateIdentifier)
        case .value(let match):
            return match.matches(optional: subject.predicateValue)
        case .hint(let match):
            return match.matches(optional: subject.predicateHint)
        case .traits(let traits):
            return traits.isEmpty || subject.satisfiesRequiredTraits(traits)
        case .actions(let actions):
            return actions.isEmpty || subject.satisfiesRequiredActions(actions)
        case .customContent(let match):
            return !match.hasPredicateLiteral || subject.containsCustomContent(matching: match)
        case .rotors(let matches):
            return matches.isEmpty || subject.satisfiesRequiredRotors(matches)
        case .exclude:
            preconditionFailure("ElementPredicateGraph resolves exclude checks as set subtraction")
        }
    }
}

// MARK: - String Comparison (canonical, shared by client and server)

public extension ElementPredicate {
    /// Case-insensitive equality with typography folding. The canonical
    /// exact-or-miss comparison shared by client-side and server-side matching.
    static func stringEquals(_ candidate: String, _ pattern: String) -> Bool {
        normalizeTypography(candidate)
            .localizedCaseInsensitiveCompare(normalizeTypography(pattern)) == .orderedSame
    }

    /// Case-insensitive substring with typography folding. Used by explicit
    /// `.contains` predicates and by diagnostic near-miss search.
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

    /// Fold typographic punctuation that has an ASCII equivalent.
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
        // Single quotes / apostrophes
        "\u{2018}": "'",
        "\u{2019}": "'",
        "\u{201A}": "'",
        "\u{201B}": "'",
        "\u{2032}": "'",
        // Double quotes
        "\u{201C}": "\"",
        "\u{201D}": "\"",
        "\u{201E}": "\"",
        "\u{201F}": "\"",
        "\u{2033}": "\"",
        // Dashes / hyphens
        "\u{2010}": "-",
        "\u{2011}": "-",
        "\u{2012}": "-",
        "\u{2013}": "-",
        "\u{2014}": "-",
        "\u{2015}": "-",
        "\u{2212}": "-",
        // Ellipsis
        "\u{2026}": "...",
        // Non-breaking / typographic spaces
        "\u{00A0}": " ",
        "\u{2007}": " ",
        "\u{202F}": " ",
    ]
}
