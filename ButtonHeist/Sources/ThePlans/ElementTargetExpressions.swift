import Foundation

// MARK: - Element Target Expressions

public enum ElementTargetExpr: Codable, Sendable, Equatable, Hashable {
    case target(ElementTarget)
    case predicate(ElementPredicateTemplate, ordinal: Int? = nil)
    case ref(HeistReferenceName)
    indirect case within(container: ContainerPredicateExpr, target: ElementTargetExpr)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case ref, ordinal, container, target
    }

    public static var inlineFieldNames: [String] {
        ElementTarget.inlineFieldNames
            + ElementPredicateTemplate.CodingKeys.allCases.map(\.stringValue)
            + [CodingKeys.container.stringValue, CodingKeys.target.stringValue]
    }

    public init(_ target: ElementTarget) {
        switch target {
        case .predicate(let predicate, let ordinal):
            self = .predicate(ElementPredicateTemplate(predicate), ordinal: ordinal)
        case .within(let container, let target):
            self = .within(container: ContainerPredicateExpr(container), target: ElementTargetExpr(target))
        }
    }

    public init(ref: HeistReferenceName) throws {
        self = .ref(try ref.validated(type: "target"))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.ref) {
            try decoder.rejectUnknownKeys(allowed: Set([CodingKeys.ref.stringValue]), typeName: "element target expression")
            self = try .ref(Self.decodeReference(from: container, key: .ref))
            return
        }
        if container.contains(.container) || container.contains(.target) {
            try decoder.rejectUnknownKeys(
                allowed: Set([CodingKeys.container.stringValue, CodingKeys.target.stringValue]),
                typeName: "scoped element target expression"
            )
            guard container.contains(.container) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .container,
                    in: container,
                    debugDescription: "scoped element target expression requires container"
                )
            }
            guard container.contains(.target) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .target,
                    in: container,
                    debugDescription: "scoped element target expression requires target"
                )
            }
            self = .within(
                container: try container.decode(ContainerPredicateExpr.self, forKey: .container),
                target: try container.decode(ElementTargetExpr.self, forKey: .target)
            )
            return
        }
        try decoder.rejectUnknownKeys(
            allowed: Set(ElementTarget.inlineFieldNames + ElementPredicateTemplate.CodingKeys.allCases.map(\.stringValue)),
            typeName: "element target expression"
        )
        let predicate = try ElementPredicateTemplate.decodeAllowingAdditionalKeys(from: decoder)
        if predicate.hasPredicates {
            let ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)
            if let ordinal, ordinal < 0 {
                throw DecodingError.dataCorruptedError(
                    forKey: .ordinal,
                    in: container,
                    debugDescription: "ordinal must be non-negative"
                )
            }
            self = .predicate(predicate, ordinal: ordinal)
            return
        }
        self = .target(try ElementTarget(from: decoder))
    }

    public static func decodeInlineIfPresent(from decoder: Decoder) throws -> ElementTargetExpr? {
        struct AnyCodingKey: CodingKey {
            let stringValue: String
            let intValue: Int? = nil

            init?(stringValue: String) {
                self.stringValue = stringValue
            }

            init?(intValue: Int) {
                return nil
            }
        }

        let probe = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowed = Set(inlineFieldNames)
        guard probe.allKeys.contains(where: { allowed.contains($0.stringValue) }) else { return nil }
        return try ElementTargetExpr(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .target(let target):
            try target.encode(to: encoder)
        case .predicate(let predicate, let ordinal):
            try predicate.encode(to: encoder)
            if let ordinal {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(ordinal, forKey: .ordinal)
            }
        case .ref(let reference):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(reference, forKey: .ref)
        case .within(let containerPredicate, let target):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(containerPredicate, forKey: .container)
            try container.encode(target, forKey: .target)
        }
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> ElementTarget {
        switch self {
        case .target(let target):
            return target
        case .predicate(let predicate, let ordinal):
            return .predicate(try predicate.resolve(in: environment), ordinal: ordinal)
        case .ref(let reference):
            guard let target = environment.targets[reference] else {
                throw HeistExpressionError.unresolvedTargetReference(reference.rawValue)
            }
            return target
        case .within(let container, let target):
            return .within(
                try container.resolve(in: environment),
                try target.resolve(in: environment)
            )
        }
    }

    private static func decodeReference(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> HeistReferenceName {
        try HeistReferenceName.decode(from: container, forKey: key, type: "target")
    }
}

public extension ElementTargetExpr {
    func and(_ checks: ElementPredicateCheck<StringExpr>...) -> ElementTargetExpr {
        appending(checks)
    }

    func excluding(_ checks: ElementPredicateCheck<StringExpr>...) -> ElementTargetExpr {
        appending(checks.map(ElementPredicateCheck.exclude))
    }

    private func appending(_ checks: [ElementPredicateCheck<StringExpr>]) -> ElementTargetExpr {
        switch self {
        case .target(.predicate(let predicate, let ordinal)):
            return .predicate(ElementPredicateTemplate(predicate).appending(checks), ordinal: ordinal)
        case .predicate(let predicate, let ordinal):
            return .predicate(predicate.appending(checks), ordinal: ordinal)
        case .target(.within), .ref, .within:
            return self
        }
    }

    // Keep target-backed predicates equal to their canonical predicate-template form
    // so Swift-authored targets and decoded inline predicate targets compare as the
    // same heist intent.
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.ref(let lhsReference), .ref(let rhsReference)):
            return lhsReference == rhsReference
        case (.target(let lhsTarget), .target(let rhsTarget)):
            return lhsTarget == rhsTarget
        case (.predicate(let lhsPredicate, let lhsOrdinal), .predicate(let rhsPredicate, let rhsOrdinal)):
            return lhsPredicate == rhsPredicate && lhsOrdinal == rhsOrdinal
        case (.within(let lhsContainer, let lhsTarget), .within(let rhsContainer, let rhsTarget)):
            return lhsContainer == rhsContainer && lhsTarget == rhsTarget
        case (.target(.within(let lhsContainer, let lhsTarget)), .within(let rhsContainer, let rhsTarget)):
            return ContainerPredicateExpr(lhsContainer) == rhsContainer
                && ElementTargetExpr(lhsTarget) == rhsTarget
        case (.within(let lhsContainer, let lhsTarget), .target(.within(let rhsContainer, let rhsTarget))):
            return lhsContainer == ContainerPredicateExpr(rhsContainer)
                && lhsTarget == ElementTargetExpr(rhsTarget)
        case (.target(let target), .predicate(let predicate, let ordinal)),
             (.predicate(let predicate, let ordinal), .target(let target)):
            guard case .predicate(let targetPredicate, let targetOrdinal) = target else {
                return false
            }
            return ElementPredicateTemplate(targetPredicate) == predicate && targetOrdinal == ordinal
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .ref(let reference):
            hasher.combine("ref")
            hasher.combine(reference)
        case .target(.predicate(let predicate, let ordinal)):
            hasher.combine("predicate")
            hasher.combine(ElementPredicateTemplate(predicate))
            hasher.combine(ordinal)
        case .target(.within(let container, let target)):
            hasher.combine("within")
            hasher.combine(ContainerPredicateExpr(container))
            hasher.combine(ElementTargetExpr(target))
        case .predicate(let predicate, let ordinal):
            hasher.combine("predicate")
            hasher.combine(predicate)
            hasher.combine(ordinal)
        case .within(let container, let target):
            hasher.combine("within")
            hasher.combine(container)
            hasher.combine(target)
        }
    }
}

private extension ElementPredicateTemplate {
    func appending(_ checks: [ElementPredicateCheck<StringExpr>]) -> ElementPredicateTemplate {
        ElementPredicateTemplate(self.checks + checks)
    }
}

extension ElementTargetExpr: CustomStringConvertible {
    public var description: String {
        switch self {
        case .target(let target):
            return target.description
        case .predicate(let predicate, let ordinal):
            return ScoreDescription.call("targetExpr", [
                predicate.description,
                ScoreDescription.valueField("ordinal", ordinal),
            ].compactMap { $0 })
        case .ref(let reference):
            return ScoreDescription.call("targetRef", [ScoreDescription.quoted(reference.rawValue)])
        case .within(let container, let target):
            return ScoreDescription.call("within", [container.description, target.description])
        }
    }
}
