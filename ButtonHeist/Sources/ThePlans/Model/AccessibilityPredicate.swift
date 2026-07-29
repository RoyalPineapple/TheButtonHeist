import Foundation

/// What a caller can assert about one element.
///
/// `exists` and `missing` ask about a moment and are one leg. The other three ask
/// about a change and are two, in order.
public enum ElementAssertion: Codable, Sendable, Equatable {
    case exists(AccessibilityTarget)
    case missing(AccessibilityTarget)
    case appeared(AccessibilityTarget)
    case disappeared(AccessibilityTarget)
    case updated(AccessibilityElementTarget, ElementPropertyChange)

    package func resolve(
        in environment: HeistExecutionEnvironment
    ) throws -> ResolvedElementAssertion {
        switch self {
        case .exists(let target):
            return .exists(try target.resolve(in: environment))
        case .missing(let target):
            return .missing(try target.resolve(in: environment))
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

public struct AccessibilityPredicate: Codable, Sendable, Equatable {
    /// What a caller can ask of a run.
    ///
    /// Each case is a question about one kind of evidence. Stillness is not
    /// here: it is an observation-admission requirement, which every run holds
    /// and nobody authors.
    ///
    /// `presence` is the odd one and is not a kind of evidence: it is a search
    /// against whatever tree is current, and it is also the leg the element
    /// assertions decompose into.
    package enum Value: Sendable, Equatable {
        case presence(PresenceCondition)
        case notification(NotificationPredicate)
        case screenChanged(ScreenPredicate)
        case elementsChanged([ElementAssertion])
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

    public static var notification: Self { Self(core: .notification(NotificationPredicate())) }
    public static func notification(_ text: String) -> Self {
        Self(core: .notification(NotificationPredicate(text: .exact(text))))
    }
    @_disfavoredOverload
    public static func notification(_ text: StringMatch) -> Self {
        Self(core: .notification(NotificationPredicate(text: text)))
    }
    public static func notification(
        text: StringMatch? = nil,
        element: ElementPredicate? = nil
    ) -> Self {
        Self(core: .notification(NotificationPredicate(text: text, element: element)))
    }

    /// The screen changed, and optionally which screen it arrived at.
    ///
    /// This asks about the screen itself. Which elements left the old screen and
    /// which arrived on the new one are element questions — write those as
    /// element assertions, and the snapshots either side of the boundary answer
    /// them.
    public static var screenChanged: Self { Self(core: .screenChanged(ScreenPredicate())) }
    public static func screenChanged(_ predicate: ScreenPredicate) -> Self {
        Self(core: .screenChanged(predicate))
    }

    /// `.screenChanged("Settings")`, and everything `StringMatch` spells:
    /// `.contains`, `.prefix`, `.suffix`, or a reference. A bare string literal
    /// is an exact match, because `StringMatch` is `ExpressibleByStringLiteral`.
    public static func screenChanged(_ match: StringMatch) -> Self {
        .screenChanged(ScreenPredicate(match: match))
    }

    /// Elements changed. Naming none asks only that something did.
    public static var elementsChanged: Self { Self(core: .elementsChanged([])) }
    public static func elementsChanged(_ assertions: [ElementAssertion]) -> Self {
        Self(core: .elementsChanged(assertions))
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ObservationPredicate {
        switch core {
        case .presence(let condition):
            return try condition.resolve(in: environment).rootPredicate
        case .notification(let predicate):
            return .notification(try predicate.resolve(in: environment))
        case .screenChanged(let predicate):
            return .screenChanged(try predicate.resolve(in: environment))
        case .elementsChanged(let assertions):
            return .elementsChanged(try assertions.map {
                try $0.resolve(in: environment)
            })
        }
    }
}

package enum ResolvedElementAssertion: Sendable, Equatable {
    case exists(ResolvedAccessibilityTarget)
    case missing(ResolvedAccessibilityTarget)
    case appeared(ResolvedAccessibilityTarget)
    case disappeared(ResolvedAccessibilityTarget)
    case updated(ResolvedAccessibilityElementTarget, ResolvedElementPropertyChange)

    package var target: ResolvedAccessibilityTarget {
        switch self {
        case .exists(let target),
             .missing(let target),
             .appeared(let target),
             .disappeared(let target):
            return target
        case .updated(let target, _):
            return target.accessibilityTarget
        }
    }
}

/// The single execution-ready observation predicate currency.
package enum ObservationPredicate: Sendable, Equatable {
    case elementsChanged([ResolvedElementAssertion])
    case notification(NotificationPredicate.Execution)
    case noChange
    case screenChanged(ResolvedScreenPredicate)

    package var watchTarget: ResolvedAccessibilityTarget? {
        switch self {
        case .elementsChanged(let assertions):
            guard assertions.count == 1 else { return nil }
            switch assertions[0] {
            case .exists(let target),
                 .missing(let target),
                 .disappeared(let target):
                return target
            case .updated(let target, _):
                return target.accessibilityTarget
            case .appeared:
                return nil
            }
        case .notification, .noChange, .screenChanged:
            // A notification element is a standalone semantic subject, not an
            // accessibility target. The other cases name no element.
            return nil
        }
    }
}

private enum PresencePredicateWireType: String, CaseIterable {
    case exists
    case missing
}

private enum RootPredicateWireType: String, CaseIterable {
    case notification
    case changed
}

private enum ElementAssertionWireType: String, CaseIterable {
    case appeared
    case disappeared
    case updated
}

private enum AccessibilityChangedWireScope: String, CaseIterable { case screen, elements }

private enum AccessibilityPredicateCodingKeys: String, CodingKey, CaseIterable {
    case type, target, scope, assertions, property, before, after, match, text, element
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

extension ElementAssertion {
    public init(from decoder: Decoder) throws {
        self = try AccessibilityPredicateWireCodec.decodeElementAssertion(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try AccessibilityPredicateWireCodec.encodeElementAssertion(self, to: encoder)
    }
}

/// A branch condition is a presence question, so it shares the one presence wire
/// shape — `{"type":"exists","target":{…}}` — with every other spelling of the
/// same question. The synthesized enum coding would give `If`/`Case` predicates
/// a private shape in `.heist` plan JSON, which is a contract, not an internal.
extension PresenceCondition {
    public init(from decoder: Decoder) throws {
        self = try AccessibilityPredicateWireCodec.decodePresenceCondition(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try AccessibilityPredicateWireCodec.encodePresenceCondition(self, to: encoder)
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
        case .notification:
            try decoder.rejectUnknownKeys(
                allowed: ["type", "text", "element"],
                typeName: "notification predicate"
            )
            return .notification(NotificationPredicate(
                text: try container.decodeIfPresent(StringMatch.self, forKey: .text),
                element: try container.decodeIfPresent(ElementPredicate.self, forKey: .element)
            ))
        case .changed:
            let scopeString = try container.decode(String.self, forKey: .scope)
            guard let scope = AccessibilityChangedWireScope(rawValue: scopeString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .scope,
                    in: container,
                    debugDescription: "Unknown changed predicate scope: \"\(scopeString)\". Valid: screen, elements"
                )
            }
            switch scope {
            case .screen:
                // A screen predicate asks about the screen, so it carries a
                // match and no assertion list: elements are never named here.
                // Admitting the union of both scopes' keys and then reading one
                // accepts a document whose authored meaning it discards.
                try decoder.rejectUnknownKeys(
                    allowed: ["type", "scope", "match"],
                    typeName: "changed predicate with screen scope"
                )
                return .screenChanged(ScreenPredicate(
                    match: try container.decodeIfPresent(StringMatch.self, forKey: .match)
                ))
            case .elements:
                try decoder.rejectUnknownKeys(
                    allowed: ["type", "scope", "assertions"],
                    typeName: "changed predicate with elements scope"
                )
                var assertions = try container.nestedUnkeyedContainer(forKey: .assertions)
                return .elementsChanged(try decodeAssertions(from: &assertions) {
                    try decodeElementAssertion(from: $0)
                })
            }
        }
    }

    static func decodePresenceCondition(from decoder: Decoder) throws -> PresenceCondition {
        let container = try decoder.container(keyedBy: AccessibilityPredicateCodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let type = PresencePredicateWireType(rawValue: typeString) else {
            throw invalidType(
                typeString,
                in: container,
                context: "presence condition",
                valid: PresencePredicateWireType.allCases.map(\.rawValue)
            )
        }
        return try decodePresence(type, from: decoder, container: container)
    }

    static func encodePresenceCondition(_ condition: PresenceCondition, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AccessibilityPredicateCodingKeys.self)
        try encodePresence(condition, to: &container)
    }

    static func decodeElementAssertion(from decoder: Decoder) throws -> ElementAssertion {
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
            return .updated(
                try container.decode(AccessibilityElementTarget.self, forKey: .target),
                change
            )
        }
    }

    static func encodeRoot(_ root: AccessibilityPredicate.Value, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AccessibilityPredicateCodingKeys.self)
        switch root {
        case .presence(let condition):
            try encodePresence(condition, to: &container)
        case .notification(let notification):
            try container.encode(RootPredicateWireType.notification.rawValue, forKey: .type)
            try container.encodeIfPresent(notification.text, forKey: .text)
            try container.encodeIfPresent(notification.element, forKey: .element)
        case .screenChanged(let predicate):
            try container.encode(RootPredicateWireType.changed.rawValue, forKey: .type)
            try container.encode(AccessibilityChangedWireScope.screen.rawValue, forKey: .scope)
            try container.encodeIfPresent(predicate.match, forKey: .match)
        case .elementsChanged(let assertions):
            try container.encode(RootPredicateWireType.changed.rawValue, forKey: .type)
            try container.encode(AccessibilityChangedWireScope.elements.rawValue, forKey: .scope)
            var nested = container.nestedUnkeyedContainer(forKey: .assertions)
            try encodeAssertions(assertions, to: &nested) { assertion, encoder in
                try encodeElementAssertion(assertion, to: encoder)
            }
        }
    }

    static func encodeElementAssertion(_ assertion: ElementAssertion, to encoder: Encoder) throws {
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
    ) throws -> PresenceCondition {
        try decoder.rejectUnknownKeys(allowed: ["type", "target"], typeName: "\(type.rawValue) predicate")
        let target = try container.decode(AccessibilityTarget.self, forKey: .target)
        switch type {
        case .exists: return .exists(target)
        case .missing: return .missing(target)
        }
    }

    private static func encodePresence(
        _ condition: PresenceCondition,
        to container: inout KeyedEncodingContainer<AccessibilityPredicateCodingKeys>
    ) throws {
        switch condition {
        case .exists(let target):
            try encodePresence(.exists, target: target, to: &container)
        case .missing(let target):
            try encodePresence(.missing, target: target, to: &container)
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
    /// The predicate as you would have written it.
    ///
    /// Rendered in the DSL rather than a second vocabulary invented for reports,
    /// so a failure message names something you can paste back into a heist.
    public var description: String {
        CanonicalDSLDescription.render(self) { try $0.render(predicate: self, environment: $1) }
    }
}

extension ObservationPredicate: CustomStringConvertible {
    package var description: String {
        switch self {
        case .elementsChanged(let assertions):
            return CanonicalValueDescription.call("elementsChanged", assertions.map(\.description))
        case .notification(let notification): return notification.description
        case .noChange: return "the tree to stop changing"
        case .screenChanged(let predicate):
            return CanonicalValueDescription.call("screenChanged", [predicate.description])
        }
    }
}

extension ElementAssertion: CustomStringConvertible {
    public var description: String {
        CanonicalDSLDescription.render(self) {
            try $0.render(elementAssertion: self, environment: $1)
        }
    }
}

extension ResolvedElementAssertion: CustomStringConvertible {
    package var description: String {
        switch self {
        case .exists(let target):
            return CanonicalValueDescription.call("exists", [target.description])
        case .missing(let target):
            return CanonicalValueDescription.call("missing", [target.description])
        case .appeared(let target):
            return CanonicalValueDescription.call("appeared", [target.description])
        case .disappeared(let target):
            return CanonicalValueDescription.call("disappeared", [target.description])
        case .updated(let target, let change):
            return CanonicalValueDescription.call("updated", [target.description, change.description])
        }
    }
}
