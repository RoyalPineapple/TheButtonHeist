import Foundation

public enum RootContext: Sendable {}
public enum ScreenAssertionContext: Sendable {}
public enum ElementsAssertionContext: Sendable {}

public enum ChangeDeclaration: Sendable, Equatable {
    case screen([AccessibilityPredicate<ScreenAssertionContext>] = [])
    case elements([AccessibilityPredicate<ElementsAssertionContext>] = [])
}

package indirect enum AccessibilityPredicateNode: Sendable, Equatable {
    case exists(AccessibilityTarget)
    case missing(AccessibilityTarget)
    case announcement(AnnouncementPredicate)
    case changed(AccessibilityPredicateNode)
    case noChange
    case screen([AccessibilityPredicateNode])
    case elements([AccessibilityPredicateNode])
    case appeared(AccessibilityTarget)
    case disappeared(AccessibilityTarget)
    case updated(AccessibilityTarget, AnyPropertyChangeExpr)
}

public struct AccessibilityPredicate<Context>: Sendable, Equatable {
    package let node: AccessibilityPredicateNode

    public func resolve(in environment: HeistExecutionEnvironment) throws -> Self {
        Self(node: try node.resolve(in: environment))
    }
}

public extension AccessibilityPredicate {
    static func exists(_ target: AccessibilityTarget) -> Self {
        Self(node: .exists(target))
    }

    static func missing(_ target: AccessibilityTarget) -> Self {
        Self(node: .missing(target))
    }
}

public extension AccessibilityPredicate where Context == RootContext {
    static var announcement: Self {
        .announcement(AnnouncementPredicate())
    }

    static func announcement(_ predicate: AnnouncementPredicate) -> Self {
        Self(node: .announcement(predicate))
    }

    static func announcement(_ text: String) -> Self {
        .announcement(AnnouncementPredicate(text))
    }

    static func announcement(_ match: StringMatch<String>) -> Self {
        .announcement(AnnouncementPredicate(match: match))
    }

    static func changed(_ declaration: ChangeDeclaration) -> Self {
        switch declaration {
        case .screen(let assertions):
            return Self(node: .changed(.screen(assertions.map(\.node))))
        case .elements(let assertions):
            return Self(node: .changed(.elements(assertions.map(\.node))))
        }
    }

    static var noChange: Self {
        Self(node: .noChange)
    }
}

public extension AccessibilityPredicate where Context == ElementsAssertionContext {
    static func appeared(_ target: AccessibilityTarget) -> Self {
        Self(node: .appeared(target))
    }

    static func disappeared(_ target: AccessibilityTarget) -> Self {
        Self(node: .disappeared(target))
    }

    static func updated(_ target: AccessibilityTarget, _ change: AnyPropertyChangeExpr) -> Self {
        Self(node: .updated(target, change))
    }
}

package extension AccessibilityPredicate where Context == ScreenAssertionContext {
    var rootPredicate: AccessibilityPredicate<RootContext> {
        AccessibilityPredicate<RootContext>(node: node)
    }
}

private extension AccessibilityPredicateNode {
    func resolve(in environment: HeistExecutionEnvironment) throws -> Self {
        switch self {
        case .exists(let target):
            return .exists(try target.resolve(in: environment))
        case .missing(let target):
            return .missing(try target.resolve(in: environment))
        case .announcement:
            return self
        case .changed(let predicate):
            return .changed(try predicate.resolve(in: environment))
        case .noChange:
            return .noChange
        case .screen(let assertions):
            return .screen(try assertions.map { try $0.resolve(in: environment) })
        case .elements(let assertions):
            return .elements(try assertions.map { try $0.resolve(in: environment) })
        case .appeared(let target):
            return .appeared(try target.resolve(in: environment))
        case .disappeared(let target):
            return .disappeared(try target.resolve(in: environment))
        case .updated(let target, let change):
            return .updated(
                try target.resolve(in: environment),
                AnyPropertyChangeExpr(try change.resolve(in: environment))
            )
        }
    }
}

// MARK: - Wire Contract

private enum AccessibilityPredicateWireType: String, CaseIterable {
    case exists
    case missing
    case announcement
    case changed
    case noChange = "no_change"
    case appeared
    case disappeared
    case updated
}

private enum AccessibilityChangedWireScope: String, CaseIterable {
    case screen
    case elements
}

private enum AccessibilityPredicateCodingKeys: String, CodingKey, CaseIterable {
    case type, target, scope, assertions, property, before, after, match
}

private enum AccessibilityPredicateWireContext {
    case expectation
    case screen
    case elements
}

extension AccessibilityPredicate: Codable {
    public static var wireTypeValues: [String] {
        [
            AccessibilityPredicateWireType.exists.rawValue,
            AccessibilityPredicateWireType.missing.rawValue,
            AccessibilityPredicateWireType.announcement.rawValue,
            AccessibilityPredicateWireType.changed.rawValue,
            AccessibilityPredicateWireType.noChange.rawValue,
        ]
    }

    public init(from decoder: Decoder) throws {
        self.init(node: try AccessibilityPredicateWireCodec.decode(
            from: decoder,
            context: try Self.wireContext(codingPath: decoder.codingPath)
        ))
    }

    public func encode(to encoder: Encoder) throws {
        try AccessibilityPredicateWireCodec.encode(
            node,
            to: encoder,
            context: try Self.wireContext(codingPath: encoder.codingPath)
        )
    }

    private static func wireContext(codingPath: [CodingKey]) throws -> AccessibilityPredicateWireContext {
        if Context.self == RootContext.self { return .expectation }
        if Context.self == ScreenAssertionContext.self { return .screen }
        if Context.self == ElementsAssertionContext.self { return .elements }
        throw DecodingError.dataCorrupted(.init(
            codingPath: codingPath,
            debugDescription: "Unsupported accessibility predicate context \(Context.self)"
        ))
    }
}

private enum AccessibilityPredicateWireCodec {
    static func decode(
        from decoder: Decoder,
        context: AccessibilityPredicateWireContext
    ) throws -> AccessibilityPredicateNode {
        let container = try decoder.container(keyedBy: AccessibilityPredicateCodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let type = AccessibilityPredicateWireType(rawValue: typeString), accepts(type, in: context) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Predicate type \"\(typeString)\" is not valid in \(context.description) "
                    + "context. Valid: \(validTypes(in: context).joined(separator: ", "))"
            )
        }

        switch type {
        case .exists:
            return try decodeCurrentTree(.exists, from: decoder, container: container)
        case .missing:
            return try decodeCurrentTree(.missing, from: decoder, container: container)
        case .announcement:
            try decoder.rejectUnknownKeys(allowed: ["type", "match"], typeName: "announcement predicate")
            return .announcement(AnnouncementPredicate(
                match: try container.decodeIfPresent(StringMatch<String>.self, forKey: .match)
            ))
        case .changed:
            try decoder.rejectUnknownKeys(
                allowed: ["type", "scope", "assertions"],
                typeName: "changed predicate"
            )
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
                return .changed(.screen(try decodeAssertions(from: &assertions, context: .screen)))
            case .elements:
                return .changed(.elements(try decodeAssertions(from: &assertions, context: .elements)))
            }
        case .noChange:
            try decoder.rejectUnknownKeys(allowed: ["type"], typeName: "no_change predicate")
            return .noChange
        case .appeared:
            return try decodeDelta(.appeared, from: decoder, container: container)
        case .disappeared:
            return try decodeDelta(.disappeared, from: decoder, container: container)
        case .updated:
            try decoder.rejectUnknownKeys(
                allowed: ["type", "target", "property", "before", "after"],
                typeName: "updated predicate"
            )
            let updateContainer = try decoder.container(keyedBy: ElementUpdateCodingKeys.self)
            guard let change = try AnyPropertyChangeExpr.decodeIfPresent(from: updateContainer) else {
                throw DecodingError.keyNotFound(
                    ElementUpdateCodingKeys.property,
                    .init(
                        codingPath: container.codingPath,
                        debugDescription: "updated predicate requires property change evidence"
                    )
                )
            }
            return .updated(
                try container.decode(AccessibilityTarget.self, forKey: .target),
                change
            )
        }
    }

    static func encode(
        _ node: AccessibilityPredicateNode,
        to encoder: Encoder,
        context: AccessibilityPredicateWireContext
    ) throws {
        var container = encoder.container(keyedBy: AccessibilityPredicateCodingKeys.self)
        switch node {
        case .exists(let target):
            try encodeCurrentTree(.exists, target: target, to: &container)
        case .missing(let target):
            try encodeCurrentTree(.missing, target: target, to: &container)
        case .announcement(let announcement):
            try container.encode(AccessibilityPredicateWireType.announcement.rawValue, forKey: .type)
            try container.encodeIfPresent(announcement.match, forKey: .match)
        case .changed(.screen(let assertions)):
            try container.encode(AccessibilityPredicateWireType.changed.rawValue, forKey: .type)
            try container.encode(AccessibilityChangedWireScope.screen.rawValue, forKey: .scope)
            var nested = container.nestedUnkeyedContainer(forKey: .assertions)
            try encodeAssertions(assertions, to: &nested, context: .screen)
        case .changed(.elements(let assertions)):
            try container.encode(AccessibilityPredicateWireType.changed.rawValue, forKey: .type)
            try container.encode(AccessibilityChangedWireScope.elements.rawValue, forKey: .scope)
            var nested = container.nestedUnkeyedContainer(forKey: .assertions)
            try encodeAssertions(assertions, to: &nested, context: .elements)
        case .noChange:
            try container.encode(AccessibilityPredicateWireType.noChange.rawValue, forKey: .type)
        case .appeared(let target):
            try encodeDelta(.appeared, target: target, to: &container)
        case .disappeared(let target):
            try encodeDelta(.disappeared, target: target, to: &container)
        case .updated(let target, let change):
            try container.encode(AccessibilityPredicateWireType.updated.rawValue, forKey: .type)
            try container.encode(target, forKey: .target)
            var updateContainer = encoder.container(keyedBy: ElementUpdateCodingKeys.self)
            try change.encodeFields(to: &updateContainer)
        case .changed, .screen, .elements:
            throw EncodingError.invalidValue(
                node,
                .init(
                    codingPath: encoder.codingPath,
                    debugDescription: "Invalid predicate node for \(context.description) context"
                )
            )
        }
    }

    private static func decodeCurrentTree(
        _ type: AccessibilityPredicateWireType,
        from decoder: Decoder,
        container: KeyedDecodingContainer<AccessibilityPredicateCodingKeys>
    ) throws -> AccessibilityPredicateNode {
        try decoder.rejectUnknownKeys(allowed: ["type", "target"], typeName: "\(type.rawValue) predicate")
        let target = try container.decode(AccessibilityTarget.self, forKey: .target)
        return type == .exists ? .exists(target) : .missing(target)
    }

    private static func encodeCurrentTree(
        _ type: AccessibilityPredicateWireType,
        target: AccessibilityTarget,
        to container: inout KeyedEncodingContainer<AccessibilityPredicateCodingKeys>
    ) throws {
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(target, forKey: .target)
    }

    private static func decodeDelta(
        _ type: AccessibilityPredicateWireType,
        from decoder: Decoder,
        container: KeyedDecodingContainer<AccessibilityPredicateCodingKeys>
    ) throws -> AccessibilityPredicateNode {
        try decoder.rejectUnknownKeys(allowed: ["type", "target"], typeName: "\(type.rawValue) predicate")
        let target = try container.decode(AccessibilityTarget.self, forKey: .target)
        return type == .appeared ? .appeared(target) : .disappeared(target)
    }

    private static func encodeDelta(
        _ type: AccessibilityPredicateWireType,
        target: AccessibilityTarget,
        to container: inout KeyedEncodingContainer<AccessibilityPredicateCodingKeys>
    ) throws {
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(target, forKey: .target)
    }

    private static func decodeAssertions(
        from container: inout UnkeyedDecodingContainer,
        context: AccessibilityPredicateWireContext
    ) throws -> [AccessibilityPredicateNode] {
        var assertions: [AccessibilityPredicateNode] = []
        while !container.isAtEnd {
            assertions.append(try decode(from: container.superDecoder(), context: context))
        }
        return assertions
    }

    private static func encodeAssertions(
        _ assertions: [AccessibilityPredicateNode],
        to container: inout UnkeyedEncodingContainer,
        context: AccessibilityPredicateWireContext
    ) throws {
        for assertion in assertions {
            try encode(assertion, to: container.superEncoder(), context: context)
        }
    }

    private static func accepts(
        _ type: AccessibilityPredicateWireType,
        in context: AccessibilityPredicateWireContext
    ) -> Bool {
        switch context {
        case .expectation:
            return type == .exists || type == .missing || type == .announcement
                || type == .changed || type == .noChange
        case .screen:
            return type == .exists || type == .missing
        case .elements:
            return type == .exists || type == .missing || type == .appeared || type == .disappeared || type == .updated
        }
    }

    private static func validTypes(in context: AccessibilityPredicateWireContext) -> [String] {
        AccessibilityPredicateWireType.allCases.filter { accepts($0, in: context) }.map(\.rawValue)
    }
}

private extension AccessibilityPredicateWireContext {
    var description: String {
        switch self {
        case .expectation: return "expectation"
        case .screen: return "screen assertion"
        case .elements: return "elements assertion"
        }
    }
}

extension AccessibilityPredicate: CustomStringConvertible {
    public var description: String {
        node.description
    }
}

private extension AccessibilityPredicateNode {
    var description: String {
        switch self {
        case .exists(let target): return ScoreDescription.call("exists", [target.description])
        case .missing(let target): return ScoreDescription.call("missing", [target.description])
        case .announcement(let announcement): return announcement.description
        case .changed(let predicate): return ScoreDescription.call("changed", [predicate.description])
        case .noChange: return "no_change"
        case .screen(let assertions): return ScoreDescription.call("screen", assertions.map(\.description))
        case .elements(let assertions): return ScoreDescription.call("elements", assertions.map(\.description))
        case .appeared(let target): return ScoreDescription.call("appeared", [target.description])
        case .disappeared(let target): return ScoreDescription.call("disappeared", [target.description])
        case .updated(let target, let change):
            return ScoreDescription.call("updated", [target.description, String(describing: change)])
        }
    }
}
