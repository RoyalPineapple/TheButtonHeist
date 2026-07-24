import Foundation

// MARK: - Element Predicate Core

package indirect enum ElementPredicateCheckCore<Text> {
    case label(StringMatchCore<Text>)
    case identifier(StringMatchCore<Text>)
    case value(StringMatchCore<Text>)
    case traits(Set<HeistTrait>)
    case hint(StringMatchCore<Text>)
    case actions(Set<ElementAction>)
    case customContent(CustomContentMatchCore<Text>)
    case rotors([StringMatchCore<Text>])
    case exclude(ElementPredicateCheckCore<Text>)

    package func map<NewText>(
        _ transform: (Text) throws -> NewText
    ) rethrows -> ElementPredicateCheckCore<NewText> {
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

extension ElementPredicateCheckCore: Sendable where Text: Sendable {}
extension ElementPredicateCheckCore: Equatable where Text: Equatable {}
extension ElementPredicateCheckCore: Hashable where Text: Hashable {}

package extension ElementPredicateCheckCore where Text: StringMatchLeaf {
    var invalidEmptyBroadMode: StringMatch.Mode? {
        switch self {
        case .label(let match), .identifier(let match), .value(let match), .hint(let match):
            return match.invalidEmptyBroadMode
        case .customContent(let match):
            return match.label?.invalidEmptyBroadMode ?? match.value?.invalidEmptyBroadMode
        case .rotors(let matches):
            return matches.lazy.compactMap(\.invalidEmptyBroadMode).first
        case .exclude(let check):
            return check.invalidEmptyBroadMode
        case .traits, .actions:
            return nil
        }
    }

    var hasPredicateLiteral: Bool {
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

    var invalidEmptyPayloadDescription: String? {
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

    private static func emptyStringPayloadDescription(
        _ match: StringMatchCore<Text>,
        field: String
    ) -> String? {
        match.payload?.stringMatchLiteralIsEmpty == true ? "\(field) match value must not be empty" : nil
    }
}

package struct ElementPredicateCore<Text> {
    package let checks: [ElementPredicateCheckCore<Text>]

    package init(_ checks: [ElementPredicateCheckCore<Text>] = []) {
        self.checks = checks
    }

    package func map<NewText>(
        _ transform: (Text) throws -> NewText
    ) rethrows -> ElementPredicateCore<NewText> {
        try ElementPredicateCore<NewText>(checks.map { try $0.map(transform) })
    }
}

package extension ElementPredicateCore where Text: StringMatchLeaf {
    var invalidEmptyBroadMode: StringMatch.Mode? {
        checks.lazy.compactMap(\.invalidEmptyBroadMode).first
    }
}

extension ElementPredicateCore: Sendable where Text: Sendable {}
extension ElementPredicateCore: Equatable where Text: Equatable {}
extension ElementPredicateCore: Hashable where Text: Hashable {}

package extension ElementPredicateCore where Text: StringMatchLeaf {
    var hasPredicates: Bool {
        checks.contains { $0.hasPredicateLiteral }
    }

    var invalidEmptyPayloadDescription: String? {
        if let description = checks.lazy.compactMap(\.invalidEmptyPayloadDescription).first {
            return description
        }
        return hasPredicates ? nil : AccessibilityTargetGrammarError.emptyPredicate.diagnosticDescription
    }
}

// MARK: - Authored Checks

/// One authored element check whose references resolve before evaluation.
public struct ElementPredicateCheck: Codable, Sendable, Equatable, Hashable {
    package let core: ElementPredicateCheckCore<AuthoredString>

    package init(core: ElementPredicateCheckCore<AuthoredString>) {
        self.core = core
    }

    public static func label(_ match: StringMatch) -> Self { Self(core: .label(match.core)) }
    public static func label(_ value: String) -> Self { .label(.exact(value)) }
    @_disfavoredOverload
    public static func label(_ reference: HeistReferenceName) -> Self { .label(.exact(reference)) }

    public static func identifier(_ match: StringMatch) -> Self { Self(core: .identifier(match.core)) }
    public static func identifier(_ value: String) -> Self { .identifier(.exact(value)) }
    @_disfavoredOverload
    public static func identifier(_ reference: HeistReferenceName) -> Self { .identifier(.exact(reference)) }

    public static func value(_ match: StringMatch) -> Self { Self(core: .value(match.core)) }
    public static func value(_ value: String) -> Self { .value(.exact(value)) }
    @_disfavoredOverload
    public static func value(_ reference: HeistReferenceName) -> Self { .value(.exact(reference)) }

    public static func hint(_ match: StringMatch) -> Self { Self(core: .hint(match.core)) }
    public static func hint(_ value: String) -> Self { .hint(.exact(value)) }
    @_disfavoredOverload
    public static func hint(_ reference: HeistReferenceName) -> Self { .hint(.exact(reference)) }

    public static func traits(_ traits: Set<HeistTrait>) -> Self { Self(core: .traits(traits)) }
    public static func actions(_ actions: Set<ElementAction>) -> Self { Self(core: .actions(actions)) }
    public static func customContent(_ match: CustomContentMatch) -> Self { Self(core: .customContent(match.core)) }
    public static func rotors(_ matches: [StringMatch]) -> Self { Self(core: .rotors(matches.map(\.core))) }
    public static func exclude(_ check: ElementPredicateCheck) -> Self { Self(core: .exclude(check.core)) }

    public var hasPredicateLiteral: Bool { core.hasPredicateLiteral }
    public var invalidEmptyPayloadDescription: String? { core.invalidEmptyPayloadDescription }

    public init(from decoder: Decoder) throws {
        core = try ElementPredicateCheckCore(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try core.encode(to: encoder)
    }
}

extension ElementPredicateCheck: CustomStringConvertible {
    public var description: String {
        core.map(\.description).description
    }
}

// MARK: - Resolved Element Predicate

/// A resolved element predicate. This type cannot contain references.
public struct ResolvedElementPredicate: Codable, Sendable, Equatable, Hashable {
    package let core: ElementPredicateCore<String>

    package init(core: ElementPredicateCore<String>) {
        self.core = core
    }

    package init(_ checks: [ElementPredicateCheckCore<String>]) {
        core = ElementPredicateCore(checks)
    }

    package var hasPredicates: Bool { core.hasPredicates }
    package var invalidEmptyPayloadDescription: String? { core.invalidEmptyPayloadDescription }

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

    public init(from decoder: Decoder) throws {
        core = try ElementPredicateCore(from: decoder)
        if let description = invalidEmptyPayloadDescription {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: description
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        try core.encode(to: encoder)
    }
}

extension ResolvedElementPredicate: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call(
            "predicate",
            core.checks.map { $0.map(CanonicalValueDescription.quoted).description }
        )
    }
}

// MARK: - Evaluation

package protocol ElementPredicateSubject {
    var predicateLabel: String? { get }
    var predicateIdentifier: String? { get }
    var predicateValue: String? { get }
    var predicateHint: String? { get }
    func satisfiesRequiredTraits(_ required: Set<HeistTrait>) -> Bool
    func satisfiesRequiredActions(_ required: Set<ElementAction>) -> Bool
    func containsCustomContent(matching match: CustomContentMatchCore<String>) -> Bool
    func satisfiesRequiredRotors(_ required: [StringMatchCore<String>]) -> Bool
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

    func containsCustomContent(matching match: CustomContentMatchCore<String>) -> Bool {
        predicateSubject.containsCustomContent(matching: match)
    }

    func satisfiesRequiredRotors(_ required: [StringMatchCore<String>]) -> Bool {
        predicateSubject.satisfiesRequiredRotors(required)
    }
}

package extension ResolvedElementPredicate {
    func matches(_ subject: some ElementPredicateSubject) -> Bool {
        hasPredicates && core.checks.allSatisfy { $0.matches(subject) }
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
            all.matches.filter { match in
                predicate.core.checks.allSatisfy { $0.matches(match.subject) }
            }
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
        _ check: ElementPredicateCheckCore<String>
    ) -> ElementPredicateMatchSet<Identity, Subject> {
        switch check {
        case .exclude(let excluded):
            return all.subtracting(resolve(excluded))
        case .label, .identifier, .value, .hint, .traits, .actions, .customContent, .rotors:
            return ElementPredicateMatchSet(all.matches.filter { check.matchesSubject($0.subject) })
        }
    }
}

package extension ElementPredicateCheckCore where Text == String {
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
            return ResolvedStringMatch(core: match).matches(optional: subject.predicateLabel)
        case .identifier(let match):
            return ResolvedStringMatch(core: match).matches(optional: subject.predicateIdentifier)
        case .value(let match):
            return ResolvedStringMatch(core: match).matches(optional: subject.predicateValue)
        case .hint(let match):
            return ResolvedStringMatch(core: match).matches(optional: subject.predicateHint)
        case .traits(let traits):
            return traits.isEmpty || subject.satisfiesRequiredTraits(traits)
        case .actions(let actions):
            return actions.isEmpty || subject.satisfiesRequiredActions(actions)
        case .customContent(let match):
            return !match.hasPredicateLiteral || subject.containsCustomContent(matching: match)
        case .rotors(let matches):
            return matches.isEmpty || subject.satisfiesRequiredRotors(matches)
        case .exclude:
            return false
        }
    }
}

// MARK: - Codable

extension ElementPredicateCore: Codable where Text: Codable & StringMatchLeaf {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case checks
    }

    package init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checks = try container.decodeIfPresent([ElementPredicateCheckCore<Text>].self, forKey: .checks) ?? []
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !checks.isEmpty {
            try container.encode(checks, forKey: .checks)
        }
    }
}

extension ElementPredicateCheckCore: Codable where Text: Codable & StringMatchLeaf {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, match, values, check
    }

    package enum Kind: String, Codable, CaseIterable {
        case label, identifier, value, hint
        case traits, actions, customContent, rotors
        case exclude
    }

    package init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element predicate check")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .label:
            try Self.rejectIrrelevantField(.values, in: container, forKind: .label)
            try Self.rejectIrrelevantField(.check, in: container, forKind: .label)
            self = .label(try container.decode(StringMatchCore<Text>.self, forKey: .match))
        case .identifier:
            try Self.rejectIrrelevantField(.values, in: container, forKind: .identifier)
            try Self.rejectIrrelevantField(.check, in: container, forKind: .identifier)
            self = .identifier(try container.decode(StringMatchCore<Text>.self, forKey: .match))
        case .value:
            try Self.rejectIrrelevantField(.values, in: container, forKind: .value)
            try Self.rejectIrrelevantField(.check, in: container, forKind: .value)
            self = .value(try container.decode(StringMatchCore<Text>.self, forKey: .match))
        case .hint:
            try Self.rejectIrrelevantField(.values, in: container, forKind: .hint)
            try Self.rejectIrrelevantField(.check, in: container, forKind: .hint)
            self = .hint(try container.decode(StringMatchCore<Text>.self, forKey: .match))
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
            self = .customContent(try container.decode(CustomContentMatchCore<Text>.self, forKey: .match))
        case .rotors:
            try Self.rejectIrrelevantField(.match, in: container, forKind: .rotors)
            try Self.rejectIrrelevantField(.check, in: container, forKind: .rotors)
            self = .rotors(try container.decode([StringMatchCore<Text>].self, forKey: .values))
        case .exclude:
            try Self.rejectIrrelevantField(.match, in: container, forKind: .exclude)
            try Self.rejectIrrelevantField(.values, in: container, forKind: .exclude)
            self = .exclude(try container.decode(ElementPredicateCheckCore<Text>.self, forKey: .check))
        }
        if let description = invalidEmptyPayloadDescription {
            throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: description))
        }
    }

    package func encode(to encoder: Encoder) throws {
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
}

extension ElementPredicateCheckCore: CustomStringConvertible {
    package var description: String {
        switch self {
        case .label(let match):
            return "label=\(match)"
        case .identifier(let match):
            return "identifier=\(match)"
        case .value(let match):
            return "value=\(match)"
        case .traits(let traits):
            return "traits=[\(traits.canonicalHeistTraitArray.map(\.rawValue).joined(separator: ", "))]"
        case .hint(let match):
            return "hint=\(match)"
        case .actions(let actions):
            return "actions=[\(actions.canonicalElementActionArray.map(\.description).joined(separator: ", "))]"
        case .customContent(let match):
            return "customContent=\(match)"
        case .rotors(let matches):
            return "rotors=[\(matches.map(\.description).joined(separator: ", "))]"
        case .exclude(let check):
            return "exclude(\(check))"
        }
    }
}

// MARK: - String Comparison

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
