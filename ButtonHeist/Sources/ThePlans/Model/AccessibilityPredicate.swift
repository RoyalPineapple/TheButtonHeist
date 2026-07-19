import Foundation

package protocol AccessibilityPredicatePhase: Sendable {
    associatedtype Target: Sendable & Equatable
    associatedtype Announcement: Sendable & Equatable
    associatedtype Change: Sendable & Equatable
}

package enum AuthoredAccessibilityPredicatePhase: AccessibilityPredicatePhase {
    package typealias Target = AccessibilityTarget
    package typealias Announcement = AnnouncementPredicate
    package typealias Change = ElementPropertyChange
}

package enum ResolvedAccessibilityPredicatePhase: AccessibilityPredicatePhase {
    package typealias Target = ResolvedAccessibilityTarget
    package typealias Announcement = ResolvedAnnouncementPredicate
    package typealias Change = ResolvedElementPropertyChange
}

package enum PresencePredicateCore<Phase: AccessibilityPredicatePhase>: Sendable, Equatable {
    case exists(Phase.Target)
    case missing(Phase.Target)
}

package enum ScreenAssertionCore<Phase: AccessibilityPredicatePhase>: Sendable, Equatable {
    case presence(PresencePredicateCore<Phase>)
}

package enum ElementAssertionCore<Phase: AccessibilityPredicatePhase>: Sendable, Equatable {
    case presence(PresencePredicateCore<Phase>)
    case appeared(Phase.Target)
    case disappeared(Phase.Target)
    case updated(Phase.Target, Phase.Change)
}

package enum ChangeDeclarationCore<Phase: AccessibilityPredicatePhase>: Sendable, Equatable {
    case screen([ScreenAssertionCore<Phase>])
    case elements([ElementAssertionCore<Phase>])
}

package enum AccessibilityPredicateCore<Phase: AccessibilityPredicatePhase>: Sendable, Equatable {
    case presence(PresencePredicateCore<Phase>)
    case announcement(Phase.Announcement)
    case changed(ChangeDeclarationCore<Phase>)
    case noChange
}

package extension AccessibilityPredicateCore {
    var requiresChangeBaseline: Bool {
        switch self {
        case .changed, .noChange:
            true
        case .presence, .announcement:
            false
        }
    }
}

package extension PresencePredicateCore where Phase == AuthoredAccessibilityPredicatePhase {
    func resolve(
        in environment: HeistExecutionEnvironment
    ) throws -> PresencePredicateCore<ResolvedAccessibilityPredicatePhase> {
        switch self {
        case .exists(let target):
            return .exists(try target.resolve(in: environment))
        case .missing(let target):
            return .missing(try target.resolve(in: environment))
        }
    }
}

package extension ScreenAssertionCore where Phase == AuthoredAccessibilityPredicatePhase {
    func resolve(
        in environment: HeistExecutionEnvironment
    ) throws -> ScreenAssertionCore<ResolvedAccessibilityPredicatePhase> {
        switch self {
        case .presence(let presence):
            return .presence(try presence.resolve(in: environment))
        }
    }
}

package extension ScreenAssertionCore {
    var rootCore: AccessibilityPredicateCore<Phase> {
        switch self {
        case .presence(let presence): return .presence(presence)
        }
    }
}

package extension ElementAssertionCore where Phase == AuthoredAccessibilityPredicatePhase {
    func resolve(
        in environment: HeistExecutionEnvironment
    ) throws -> ElementAssertionCore<ResolvedAccessibilityPredicatePhase> {
        switch self {
        case .presence(let presence):
            return .presence(try presence.resolve(in: environment))
        case .appeared(let target):
            return .appeared(try target.resolve(in: environment))
        case .disappeared(let target):
            return .disappeared(try target.resolve(in: environment))
        case .updated(let target, let change):
            return .updated(
                try target.resolve(in: environment),
                try change.resolve(in: environment)
            )
        }
    }
}

package extension ChangeDeclarationCore where Phase == AuthoredAccessibilityPredicatePhase {
    func resolve(
        in environment: HeistExecutionEnvironment
    ) throws -> ChangeDeclarationCore<ResolvedAccessibilityPredicatePhase> {
        switch self {
        case .screen(let assertions):
            return .screen(try assertions.map { try $0.resolve(in: environment) })
        case .elements(let assertions):
            return .elements(try assertions.map { try $0.resolve(in: environment) })
        }
    }
}

package extension AccessibilityPredicateCore where Phase == AuthoredAccessibilityPredicatePhase {
    func resolve(
        in environment: HeistExecutionEnvironment
    ) throws -> AccessibilityPredicateCore<ResolvedAccessibilityPredicatePhase> {
        switch self {
        case .presence(let presence):
            return .presence(try presence.resolve(in: environment))
        case .announcement(let predicate):
            return .announcement(try predicate.resolve(in: environment))
        case .changed(let declaration):
            return .changed(try declaration.resolve(in: environment))
        case .noChange:
            return .noChange
        }
    }
}

public enum ChangeDeclaration: Sendable, Equatable {
    case screen([ScreenAssertion] = [])
    case elements([ElementAssertion] = [])

    public struct ScreenAssertion: Codable, Sendable, Equatable {
        package let core: ScreenAssertionCore<AuthoredAccessibilityPredicatePhase>

        package init(core: ScreenAssertionCore<AuthoredAccessibilityPredicatePhase>) {
            self.core = core
        }

        public static func exists(_ target: AccessibilityTarget) -> Self {
            Self(core: .presence(.exists(target)))
        }

        public static func missing(_ target: AccessibilityTarget) -> Self {
            Self(core: .presence(.missing(target)))
        }

        package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedScreenAssertion {
            ResolvedScreenAssertion(core: try core.resolve(in: environment))
        }

        package var rootPredicate: AccessibilityPredicate {
            AccessibilityPredicate(core: core.rootCore)
        }
    }

    public struct ElementAssertion: Codable, Sendable, Equatable {
        package let core: ElementAssertionCore<AuthoredAccessibilityPredicatePhase>

        package init(core: ElementAssertionCore<AuthoredAccessibilityPredicatePhase>) {
            self.core = core
        }

        public static func exists(_ target: AccessibilityTarget) -> Self {
            Self(core: .presence(.exists(target)))
        }

        public static func missing(_ target: AccessibilityTarget) -> Self {
            Self(core: .presence(.missing(target)))
        }

        public static func appeared(_ target: AccessibilityTarget) -> Self {
            Self(core: .appeared(target))
        }

        public static func disappeared(_ target: AccessibilityTarget) -> Self {
            Self(core: .disappeared(target))
        }

        public static func updated(_ target: AccessibilityTarget, _ change: ElementPropertyChange) -> Self {
            Self(core: .updated(target, change))
        }

        package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedElementAssertion {
            ResolvedElementAssertion(core: try core.resolve(in: environment))
        }
    }

    package var core: ChangeDeclarationCore<AuthoredAccessibilityPredicatePhase> {
        switch self {
        case .screen(let assertions):
            return .screen(assertions.map(\.core))
        case .elements(let assertions):
            return .elements(assertions.map(\.core))
        }
    }
}

public struct AccessibilityPredicate: Codable, Sendable, Equatable {
    package let core: AccessibilityPredicateCore<AuthoredAccessibilityPredicatePhase>

    package init(core: AccessibilityPredicateCore<AuthoredAccessibilityPredicatePhase>) {
        self.core = core
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedAccessibilityPredicate {
        ResolvedAccessibilityPredicate(core: try core.resolve(in: environment))
    }

    public static func exists(_ target: AccessibilityTarget) -> Self { Self(core: .presence(.exists(target))) }
    public static func missing(_ target: AccessibilityTarget) -> Self { Self(core: .presence(.missing(target))) }
    public static var announcement: Self { .announcement(AnnouncementPredicate()) }
    public static func announcement(_ predicate: AnnouncementPredicate) -> Self {
        Self(core: .announcement(predicate))
    }
    public static func announcement(_ text: String) -> Self { .announcement(AnnouncementPredicate(text)) }
    public static func announcement(_ match: StringMatch) -> Self {
        .announcement(AnnouncementPredicate(match: match))
    }

    public static func changed(_ declaration: ChangeDeclaration) -> Self {
        Self(core: .changed(declaration.core))
    }

    public static var noChange: Self { Self(core: .noChange) }

    package var requiresChangeBaseline: Bool { core.requiresChangeBaseline }
}

package struct ResolvedAccessibilityPredicate: Sendable, Equatable {
    package let core: AccessibilityPredicateCore<ResolvedAccessibilityPredicatePhase>

    package init(core: AccessibilityPredicateCore<ResolvedAccessibilityPredicatePhase>) {
        self.core = core
    }

    package var requiresChangeBaseline: Bool { core.requiresChangeBaseline }
}

package struct ResolvedScreenAssertion: Sendable, Equatable {
    package let core: ScreenAssertionCore<ResolvedAccessibilityPredicatePhase>

    package init(core: ScreenAssertionCore<ResolvedAccessibilityPredicatePhase>) {
        self.core = core
    }

    package var rootPredicate: ResolvedAccessibilityPredicate {
        ResolvedAccessibilityPredicate(core: core.rootCore)
    }
}

package struct ResolvedElementAssertion: Sendable, Equatable {
    package let core: ElementAssertionCore<ResolvedAccessibilityPredicatePhase>

    package init(core: ElementAssertionCore<ResolvedAccessibilityPredicatePhase>) {
        self.core = core
    }
}

private enum PresencePredicateWireType: String, CaseIterable {
    case exists
    case missing
}

private enum RootPredicateWireType: String, CaseIterable {
    case announcement
    case changed
    case noChange = "no_change"
}

private enum ElementAssertionWireType: String, CaseIterable {
    case appeared
    case disappeared
    case updated
}

private enum AccessibilityChangedWireScope: String, CaseIterable { case screen, elements }

private enum AccessibilityPredicateCodingKeys: String, CodingKey, CaseIterable {
    case type, target, scope, assertions, property, before, after, match
}

extension AccessibilityPredicate {
    public static var wireTypeValues: [String] {
        PresencePredicateWireType.allCases.map(\.rawValue) + RootPredicateWireType.allCases.map(\.rawValue)
    }

    public init(from decoder: Decoder) throws {
        core = try AccessibilityPredicateWireCodec.decodeRoot(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try AccessibilityPredicateWireCodec.encodeRoot(core, to: encoder)
    }
}

extension ChangeDeclaration.ScreenAssertion {
    public init(from decoder: Decoder) throws {
        core = try AccessibilityPredicateWireCodec.decodeScreenAssertion(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try AccessibilityPredicateWireCodec.encodeScreenAssertion(core, to: encoder)
    }
}

extension ChangeDeclaration.ElementAssertion {
    public init(from decoder: Decoder) throws {
        core = try AccessibilityPredicateWireCodec.decodeElementAssertion(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try AccessibilityPredicateWireCodec.encodeElementAssertion(core, to: encoder)
    }
}

private enum AccessibilityPredicateWireCodec {
    typealias Presence = PresencePredicateCore<AuthoredAccessibilityPredicatePhase>
    typealias Root = AccessibilityPredicateCore<AuthoredAccessibilityPredicatePhase>
    typealias Screen = ScreenAssertionCore<AuthoredAccessibilityPredicatePhase>
    typealias Element = ElementAssertionCore<AuthoredAccessibilityPredicatePhase>

    static func decodeRoot(from decoder: Decoder) throws -> Root {
        let container = try decoder.container(keyedBy: AccessibilityPredicateCodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        if let presenceType = PresencePredicateWireType(rawValue: typeString) {
            return .presence(try decodePresence(presenceType, from: decoder, container: container))
        }
        guard let type = RootPredicateWireType(rawValue: typeString) else {
            throw invalidType(
                typeString,
                in: container,
                context: "expectation",
                valid: AccessibilityPredicate.wireTypeValues
            )
        }
        switch type {
        case .announcement:
            try decoder.rejectUnknownKeys(allowed: ["type", "match"], typeName: "announcement predicate")
            return .announcement(AnnouncementPredicate(
                match: try container.decodeIfPresent(StringMatch.self, forKey: .match)
            ))
        case .changed:
            try decoder.rejectUnknownKeys(allowed: ["type", "scope", "assertions"], typeName: "changed predicate")
            let scopeString = try container.decode(String.self, forKey: .scope)
            guard let scope = AccessibilityChangedWireScope(rawValue: scopeString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .scope,
                    in: container,
                    debugDescription: "Unknown changed predicate scope: \"\(scopeString)\". Valid: screen, elements"
                )
            }
            var assertions = try container.nestedUnkeyedContainer(forKey: .assertions)
            switch scope {
            case .screen:
                return .changed(.screen(try decodeAssertions(from: &assertions) {
                    try decodeScreenAssertion(from: $0)
                }))
            case .elements:
                return .changed(.elements(try decodeAssertions(from: &assertions) {
                    try decodeElementAssertion(from: $0)
                }))
            }
        case .noChange:
            try decoder.rejectUnknownKeys(allowed: ["type"], typeName: "no_change predicate")
            return .noChange
        }
    }

    static func decodeScreenAssertion(from decoder: Decoder) throws -> Screen {
        let container = try decoder.container(keyedBy: AccessibilityPredicateCodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let type = PresencePredicateWireType(rawValue: typeString) else {
            throw invalidType(
                typeString,
                in: container,
                context: "screen assertion",
                valid: PresencePredicateWireType.allCases.map(\.rawValue)
            )
        }
        return .presence(try decodePresence(type, from: decoder, container: container))
    }

    static func decodeElementAssertion(from decoder: Decoder) throws -> Element {
        let container = try decoder.container(keyedBy: AccessibilityPredicateCodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        if let presenceType = PresencePredicateWireType(rawValue: typeString) {
            return .presence(try decodePresence(presenceType, from: decoder, container: container))
        }
        guard let type = ElementAssertionWireType(rawValue: typeString) else {
            let valid = PresencePredicateWireType.allCases.map(\.rawValue)
                + ElementAssertionWireType.allCases.map(\.rawValue)
            throw invalidType(typeString, in: container, context: "elements assertion", valid: valid)
        }
        switch type {
        case .appeared:
            return .appeared(try decodeDeltaTarget(type, from: decoder, container: container))
        case .disappeared:
            return .disappeared(try decodeDeltaTarget(type, from: decoder, container: container))
        case .updated:
            try decoder.rejectUnknownKeys(
                allowed: ["type", "target", "property", "before", "after"],
                typeName: "updated predicate"
            )
            let updateContainer = try decoder.container(keyedBy: ElementUpdateCodingKeys.self)
            guard let change = try ElementPropertyChange.decodeIfPresent(from: updateContainer) else {
                throw DecodingError.keyNotFound(
                    ElementUpdateCodingKeys.property,
                    .init(
                        codingPath: container.codingPath,
                        debugDescription: "updated predicate requires property change evidence"
                    )
                )
            }
            return .updated(try container.decode(AccessibilityTarget.self, forKey: .target), change)
        }
    }

    static func encodeRoot(_ root: Root, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AccessibilityPredicateCodingKeys.self)
        switch root {
        case .presence(let presence):
            try encodePresence(presence, to: &container)
        case .announcement(let announcement):
            try container.encode(RootPredicateWireType.announcement.rawValue, forKey: .type)
            try container.encodeIfPresent(announcement.match, forKey: .match)
        case .changed(.screen(let assertions)):
            try container.encode(RootPredicateWireType.changed.rawValue, forKey: .type)
            try container.encode(AccessibilityChangedWireScope.screen.rawValue, forKey: .scope)
            var nested = container.nestedUnkeyedContainer(forKey: .assertions)
            try encodeAssertions(assertions, to: &nested) { assertion, encoder in
                try encodeScreenAssertion(assertion, to: encoder)
            }
        case .changed(.elements(let assertions)):
            try container.encode(RootPredicateWireType.changed.rawValue, forKey: .type)
            try container.encode(AccessibilityChangedWireScope.elements.rawValue, forKey: .scope)
            var nested = container.nestedUnkeyedContainer(forKey: .assertions)
            try encodeAssertions(assertions, to: &nested) { assertion, encoder in
                try encodeElementAssertion(assertion, to: encoder)
            }
        case .noChange:
            try container.encode(RootPredicateWireType.noChange.rawValue, forKey: .type)
        }
    }

    static func encodeScreenAssertion(_ assertion: Screen, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AccessibilityPredicateCodingKeys.self)
        switch assertion {
        case .presence(let presence):
            try encodePresence(presence, to: &container)
        }
    }

    static func encodeElementAssertion(_ assertion: Element, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AccessibilityPredicateCodingKeys.self)
        switch assertion {
        case .presence(let presence):
            try encodePresence(presence, to: &container)
        case .appeared(let target):
            try encodeDelta(.appeared, target: target, to: &container)
        case .disappeared(let target):
            try encodeDelta(.disappeared, target: target, to: &container)
        case .updated(let target, let change):
            try container.encode(ElementAssertionWireType.updated.rawValue, forKey: .type)
            try container.encode(target, forKey: .target)
            var updateContainer = encoder.container(keyedBy: ElementUpdateCodingKeys.self)
            try change.encodeFields(to: &updateContainer)
        }
    }

    private static func decodePresence(
        _ type: PresencePredicateWireType,
        from decoder: Decoder,
        container: KeyedDecodingContainer<AccessibilityPredicateCodingKeys>
    ) throws -> Presence {
        try decoder.rejectUnknownKeys(allowed: ["type", "target"], typeName: "\(type.rawValue) predicate")
        let target = try container.decode(AccessibilityTarget.self, forKey: .target)
        switch type {
        case .exists: return .exists(target)
        case .missing: return .missing(target)
        }
    }

    private static func encodePresence(
        _ presence: Presence,
        to container: inout KeyedEncodingContainer<AccessibilityPredicateCodingKeys>
    ) throws {
        switch presence {
        case .exists(let target):
            try container.encode(PresencePredicateWireType.exists.rawValue, forKey: .type)
            try container.encode(target, forKey: .target)
        case .missing(let target):
            try container.encode(PresencePredicateWireType.missing.rawValue, forKey: .type)
            try container.encode(target, forKey: .target)
        }
    }

    private static func decodeDeltaTarget(
        _ type: ElementAssertionWireType,
        from decoder: Decoder,
        container: KeyedDecodingContainer<AccessibilityPredicateCodingKeys>
    ) throws -> AccessibilityTarget {
        try decoder.rejectUnknownKeys(allowed: ["type", "target"], typeName: "\(type.rawValue) predicate")
        return try container.decode(AccessibilityTarget.self, forKey: .target)
    }

    private static func encodeDelta(
        _ type: ElementAssertionWireType,
        target: AccessibilityTarget,
        to container: inout KeyedEncodingContainer<AccessibilityPredicateCodingKeys>
    ) throws {
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(target, forKey: .target)
    }

    private static func decodeAssertions<Assertion>(
        from container: inout UnkeyedDecodingContainer,
        decode: (Decoder) throws -> Assertion
    ) throws -> [Assertion] {
        var assertions: [Assertion] = []
        while !container.isAtEnd {
            assertions.append(try decode(container.superDecoder()))
        }
        return assertions
    }

    private static func encodeAssertions<Assertion>(
        _ assertions: [Assertion],
        to container: inout UnkeyedEncodingContainer,
        encode: (Assertion, Encoder) throws -> Void
    ) throws {
        for assertion in assertions {
            try encode(assertion, container.superEncoder())
        }
    }

    private static func invalidType(
        _ type: String,
        in container: KeyedDecodingContainer<AccessibilityPredicateCodingKeys>,
        context: String,
        valid: [String]
    ) -> DecodingError {
        DecodingError.dataCorruptedError(
            forKey: .type,
            in: container,
            debugDescription: "Predicate type \"\(type)\" is not valid in \(context) context. "
                + "Valid: \(valid.joined(separator: ", "))"
        )
    }
}

extension AccessibilityPredicate: CustomStringConvertible {
    public var description: String { describe(core) }
}

extension ResolvedAccessibilityPredicate: CustomStringConvertible {
    package var description: String { describe(core) }
}

extension ChangeDeclaration.ScreenAssertion: CustomStringConvertible {
    public var description: String { describe(core) }
}

extension ChangeDeclaration.ElementAssertion: CustomStringConvertible {
    public var description: String { describe(core) }
}

private func describe<Phase: AccessibilityPredicatePhase>(
    _ presence: PresencePredicateCore<Phase>
) -> String {
    switch presence {
    case .exists(let target): return CanonicalValueDescription.call("exists", [String(describing: target)])
    case .missing(let target): return CanonicalValueDescription.call("missing", [String(describing: target)])
    }
}

private func describe<Phase: AccessibilityPredicatePhase>(
    _ assertion: ScreenAssertionCore<Phase>
) -> String {
    switch assertion {
    case .presence(let presence): return describe(presence)
    }
}

private func describe<Phase: AccessibilityPredicatePhase>(
    _ assertion: ElementAssertionCore<Phase>
) -> String {
    switch assertion {
    case .presence(let presence): return describe(presence)
    case .appeared(let target): return CanonicalValueDescription.call("appeared", [String(describing: target)])
    case .disappeared(let target): return CanonicalValueDescription.call("disappeared", [String(describing: target)])
    case .updated(let target, let change):
        return CanonicalValueDescription.call("updated", [String(describing: target), String(describing: change)])
    }
}

private func describe<Phase: AccessibilityPredicatePhase>(
    _ declaration: ChangeDeclarationCore<Phase>
) -> String {
    switch declaration {
    case .screen(let assertions): return CanonicalValueDescription.call("screen", assertions.map { describe($0) })
    case .elements(let assertions): return CanonicalValueDescription.call("elements", assertions.map { describe($0) })
    }
}

private func describe<Phase: AccessibilityPredicatePhase>(
    _ predicate: AccessibilityPredicateCore<Phase>
) -> String {
    switch predicate {
    case .presence(let presence): return describe(presence)
    case .announcement(let announcement): return String(describing: announcement)
    case .changed(let declaration): return CanonicalValueDescription.call("changed", [describe(declaration)])
    case .noChange: return "no_change"
    }
}
