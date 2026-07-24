import Foundation

public enum ChangeDeclaration: Sendable, Equatable {
    case screen([ScreenAssertion] = [])
    case elements([ElementAssertion] = [])

    public enum ScreenAssertion: Codable, Sendable, Equatable {
        case exists(AccessibilityTarget)
        case missing(AccessibilityTarget)

        package static func presence(_ presence: AccessibilityPredicate.Presence) -> Self {
            switch presence {
            case .exists(let target): return .exists(target)
            case .missing(let target): return .missing(target)
            }
        }

        package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedScreenAssertion {
            switch self {
            case .exists(let target): return .exists(try target.resolve(in: environment))
            case .missing(let target): return .missing(try target.resolve(in: environment))
            }
        }

        package var rootPredicate: AccessibilityPredicate {
            switch self {
            case .exists(let target): return .exists(target)
            case .missing(let target): return .missing(target)
            }
        }
    }

    public enum ElementAssertion: Codable, Sendable, Equatable {
        case exists(AccessibilityTarget)
        case missing(AccessibilityTarget)
        case appeared(AccessibilityTarget)
        case disappeared(AccessibilityTarget)
        case updated(AccessibilityTarget, ElementPropertyChange)

        package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedElementAssertion {
            switch self {
            case .exists(let target): return .exists(try target.resolve(in: environment))
            case .missing(let target): return .missing(try target.resolve(in: environment))
            case .appeared(let target): return .appeared(try target.resolve(in: environment))
            case .disappeared(let target): return .disappeared(try target.resolve(in: environment))
            case .updated(let target, let change):
                return .updated(
                    try target.resolve(in: environment),
                    try change.resolve(in: environment)
                )
            }
        }
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedChangeDeclaration {
        switch self {
        case .screen(let assertions):
            return .screen(try assertions.map { try $0.resolve(in: environment) })
        case .elements(let assertions):
            return .elements(try assertions.map { try $0.resolve(in: environment) })
        }
    }
}

public struct AccessibilityPredicate: Codable, Sendable, Equatable {
    package enum Presence: Sendable, Equatable {
        case exists(AccessibilityTarget)
        case missing(AccessibilityTarget)
    }

    package enum Value: Sendable, Equatable {
        case presence(Presence)
        case announcement(AnnouncementPredicate)
        case changed(ChangeDeclaration)
        case noChange
    }

    package let core: Value

    package init(core: Value) {
        self.core = core
    }

    public static func exists(_ target: AccessibilityTarget) -> Self {
        Self(core: .presence(.exists(target)))
    }

    public static func missing(_ target: AccessibilityTarget) -> Self {
        Self(core: .presence(.missing(target)))
    }

    public static var announcement: Self { Self(core: .announcement(AnnouncementPredicate())) }
    public static func announcement(_ predicate: AnnouncementPredicate) -> Self {
        Self(core: .announcement(predicate))
    }
    public static func announcement(_ text: String) -> Self { .announcement(AnnouncementPredicate(text)) }
    public static func announcement(_ match: StringMatch) -> Self {
        .announcement(AnnouncementPredicate(match: match))
    }
    public static func changed(_ declaration: ChangeDeclaration) -> Self {
        Self(core: .changed(declaration))
    }
    public static var noChange: Self { Self(core: .noChange) }

    package var requiresChangeBaseline: Bool {
        switch core {
        case .changed, .noChange: true
        case .presence, .announcement: false
        }
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedAccessibilityPredicate {
        switch core {
        case .presence(.exists(let target)): return .exists(try target.resolve(in: environment))
        case .presence(.missing(let target)): return .missing(try target.resolve(in: environment))
        case .announcement(let predicate): return .announcement(try predicate.resolve(in: environment))
        case .changed(let declaration): return .changed(try declaration.resolve(in: environment))
        case .noChange: return .noChange
        }
    }
}

package enum ResolvedChangeDeclaration: Sendable, Equatable {
    case screen([ResolvedScreenAssertion])
    case elements([ResolvedElementAssertion])
}

package enum ResolvedScreenAssertion: Sendable, Equatable {
    case exists(ResolvedAccessibilityTarget)
    case missing(ResolvedAccessibilityTarget)

    package var rootPredicate: ResolvedAccessibilityPredicate {
        switch self {
        case .exists(let target): return .exists(target)
        case .missing(let target): return .missing(target)
        }
    }
}

package enum ResolvedElementAssertion: Sendable, Equatable {
    case exists(ResolvedAccessibilityTarget)
    case missing(ResolvedAccessibilityTarget)
    case appeared(ResolvedAccessibilityTarget)
    case disappeared(ResolvedAccessibilityTarget)
    case updated(ResolvedAccessibilityTarget, ResolvedElementPropertyChange)

    package var target: ResolvedAccessibilityTarget {
        switch self {
        case .exists(let target), .missing(let target), .appeared(let target), .disappeared(let target):
            return target
        case .updated(let target, _):
            return target
        }
    }
}

package enum ResolvedAccessibilityPredicate: Sendable, Equatable {
    case exists(ResolvedAccessibilityTarget)
    case missing(ResolvedAccessibilityTarget)
    case announcement(ResolvedAnnouncementPredicate)
    case changed(ResolvedChangeDeclaration)
    case noChange

    package var requiresChangeBaseline: Bool {
        switch self {
        case .changed, .noChange: true
        case .exists, .missing, .announcement: false
        }
    }

    package var singularTarget: ResolvedAccessibilityTarget? {
        switch self {
        case .exists(let target), .missing(let target):
            return target
        case .changed(.screen(let assertions)):
            guard assertions.count == 1 else { return nil }
            switch assertions[0] {
            case .exists(let target), .missing(let target): return target
            }
        case .changed(.elements(let assertions)):
            guard assertions.count == 1 else { return nil }
            return assertions[0].target
        case .announcement, .noChange:
            return nil
        }
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
        self = try AccessibilityPredicateWireCodec.decodeScreenAssertion(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try AccessibilityPredicateWireCodec.encodeScreenAssertion(self, to: encoder)
    }
}

extension ChangeDeclaration.ElementAssertion {
    public init(from decoder: Decoder) throws {
        self = try AccessibilityPredicateWireCodec.decodeElementAssertion(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try AccessibilityPredicateWireCodec.encodeElementAssertion(self, to: encoder)
    }
}

private enum AccessibilityPredicateWireCodec {
    static func decodeRoot(from decoder: Decoder) throws -> AccessibilityPredicate.Value {
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

    static func decodeScreenAssertion(from decoder: Decoder) throws -> ChangeDeclaration.ScreenAssertion {
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
        switch try decodePresence(type, from: decoder, container: container) {
        case .exists(let target): return .exists(target)
        case .missing(let target): return .missing(target)
        }
    }

    static func decodeElementAssertion(from decoder: Decoder) throws -> ChangeDeclaration.ElementAssertion {
        let container = try decoder.container(keyedBy: AccessibilityPredicateCodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        if let presenceType = PresencePredicateWireType(rawValue: typeString) {
            switch try decodePresence(presenceType, from: decoder, container: container) {
            case .exists(let target): return .exists(target)
            case .missing(let target): return .missing(target)
            }
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

    static func encodeRoot(_ root: AccessibilityPredicate.Value, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AccessibilityPredicateCodingKeys.self)
        switch root {
        case .presence(.exists(let target)):
            try encodePresence(.exists, target: target, to: &container)
        case .presence(.missing(let target)):
            try encodePresence(.missing, target: target, to: &container)
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

    static func encodeScreenAssertion(_ assertion: ChangeDeclaration.ScreenAssertion, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AccessibilityPredicateCodingKeys.self)
        switch assertion {
        case .exists(let target): try encodePresence(.exists, target: target, to: &container)
        case .missing(let target): try encodePresence(.missing, target: target, to: &container)
        }
    }

    static func encodeElementAssertion(_ assertion: ChangeDeclaration.ElementAssertion, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AccessibilityPredicateCodingKeys.self)
        switch assertion {
        case .exists(let target):
            try encodePresence(.exists, target: target, to: &container)
        case .missing(let target):
            try encodePresence(.missing, target: target, to: &container)
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
    ) throws -> AccessibilityPredicate.Presence {
        try decoder.rejectUnknownKeys(allowed: ["type", "target"], typeName: "\(type.rawValue) predicate")
        let target = try container.decode(AccessibilityTarget.self, forKey: .target)
        switch type {
        case .exists: return .exists(target)
        case .missing: return .missing(target)
        }
    }

    private static func encodePresence(
        _ type: PresencePredicateWireType,
        target: AccessibilityTarget,
        to container: inout KeyedEncodingContainer<AccessibilityPredicateCodingKeys>
    ) throws {
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(target, forKey: .target)
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
    public var description: String {
        switch core {
        case .presence(.exists(let target)):
            return CanonicalValueDescription.call("exists", [target.description])
        case .presence(.missing(let target)):
            return CanonicalValueDescription.call("missing", [target.description])
        case .announcement(let announcement): return announcement.description
        case .changed(let declaration):
            return CanonicalValueDescription.call("changed", [declaration.description])
        case .noChange: return "no_change"
        }
    }
}

extension ResolvedAccessibilityPredicate: CustomStringConvertible {
    package var description: String {
        switch self {
        case .exists(let target): return CanonicalValueDescription.call("exists", [target.description])
        case .missing(let target): return CanonicalValueDescription.call("missing", [target.description])
        case .announcement(let announcement): return announcement.description
        case .changed(let declaration):
            return CanonicalValueDescription.call("changed", [declaration.description])
        case .noChange: return "no_change"
        }
    }
}

extension ChangeDeclaration: CustomStringConvertible {
    public var description: String {
        switch self {
        case .screen(let assertions):
            return CanonicalValueDescription.call("screen", assertions.map(\.description))
        case .elements(let assertions):
            return CanonicalValueDescription.call("elements", assertions.map(\.description))
        }
    }
}

extension ResolvedChangeDeclaration: CustomStringConvertible {
    package var description: String {
        switch self {
        case .screen(let assertions):
            return CanonicalValueDescription.call("screen", assertions.map(\.description))
        case .elements(let assertions):
            return CanonicalValueDescription.call("elements", assertions.map(\.description))
        }
    }
}

extension ChangeDeclaration.ScreenAssertion: CustomStringConvertible {
    public var description: String {
        switch self {
        case .exists(let target): return CanonicalValueDescription.call("exists", [target.description])
        case .missing(let target): return CanonicalValueDescription.call("missing", [target.description])
        }
    }
}

extension ResolvedScreenAssertion: CustomStringConvertible {
    package var description: String {
        switch self {
        case .exists(let target): return CanonicalValueDescription.call("exists", [target.description])
        case .missing(let target): return CanonicalValueDescription.call("missing", [target.description])
        }
    }
}

extension ChangeDeclaration.ElementAssertion: CustomStringConvertible {
    public var description: String {
        switch self {
        case .exists(let target): return CanonicalValueDescription.call("exists", [target.description])
        case .missing(let target): return CanonicalValueDescription.call("missing", [target.description])
        case .appeared(let target): return CanonicalValueDescription.call("appeared", [target.description])
        case .disappeared(let target): return CanonicalValueDescription.call("disappeared", [target.description])
        case .updated(let target, let change):
            return CanonicalValueDescription.call("updated", [target.description, change.description])
        }
    }
}

extension ResolvedElementAssertion: CustomStringConvertible {
    package var description: String {
        switch self {
        case .exists(let target): return CanonicalValueDescription.call("exists", [target.description])
        case .missing(let target): return CanonicalValueDescription.call("missing", [target.description])
        case .appeared(let target): return CanonicalValueDescription.call("appeared", [target.description])
        case .disappeared(let target): return CanonicalValueDescription.call("disappeared", [target.description])
        case .updated(let target, let change):
            return CanonicalValueDescription.call("updated", [target.description, change.description])
        }
    }
}
