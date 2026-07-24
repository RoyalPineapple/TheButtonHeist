import Foundation

/// An authored accessibility target. References and predicate expressions are
/// resolved exactly once into `ResolvedAccessibilityTarget` before execution.
public indirect enum AccessibilityTarget: Codable, Sendable, Equatable, Hashable {
    case predicate(ElementPredicate, ordinal: Int? = nil)
    case container(ContainerPredicate, ordinal: Int? = nil)
    case ref(HeistReferenceName)
    case within(container: ContainerPredicate, target: AccessibilityTarget)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case ref, ordinal, container, target
    }

    public static var inlineFieldNames: [String] {
        ElementPredicate.CodingKeys.allCases.map(\.stringValue)
            + CodingKeys.allCases.map(\.stringValue)
    }

    public init(ref: HeistReferenceName) {
        self = .ref(ref)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.ref) {
            try decoder.rejectUnknownKeys(allowed: [CodingKeys.ref.stringValue], typeName: "accessibility target")
            self = .ref(try HeistReferenceName.decode(from: container, forKey: .ref, type: "target"))
            return
        }
        if container.contains(.container) || container.contains(.target) {
            guard container.contains(.container) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .target,
                    in: container,
                    debugDescription: "scoped accessibility target requires container"
                )
            }
            if !container.contains(.target) {
                try decoder.rejectUnknownKeys(
                    allowed: [CodingKeys.container.stringValue, CodingKeys.ordinal.stringValue],
                    typeName: "container accessibility target"
                )
                self = .container(
                    try container.decode(ContainerPredicate.self, forKey: .container),
                    ordinal: try Self.decodeOrdinal(from: container)
                )
                return
            }
            try decoder.rejectUnknownKeys(
                allowed: [CodingKeys.container.stringValue, CodingKeys.target.stringValue],
                typeName: "scoped accessibility target"
            )
            self = .within(
                container: try container.decode(ContainerPredicate.self, forKey: .container),
                target: try container.decode(AccessibilityTarget.self, forKey: .target)
            )
            return
        }

        try decoder.rejectUnknownKeys(
            allowed: Set(ElementPredicate.CodingKeys.allCases.map(\.stringValue) + [CodingKeys.ordinal.stringValue]),
            typeName: "accessibility target"
        )
        let predicate = try ElementPredicate.decodeAllowingAdditionalKeys(from: decoder)
        guard predicate.hasPredicates else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: AccessibilityTargetGrammarError.emptyPredicate.diagnosticDescription
            ))
        }
        self = .predicate(predicate, ordinal: try Self.decodeOrdinal(from: container))
    }

    public static func decodeInlineIfPresent(from decoder: Decoder) throws -> AccessibilityTarget? {
        struct AnyCodingKey: CodingKey {
            let stringValue: String
            let intValue: Int? = nil
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }

        let probe = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowed = Set(inlineFieldNames)
        guard probe.allKeys.contains(where: { allowed.contains($0.stringValue) }) else { return nil }
        return try AccessibilityTarget(from: decoder)
    }

    public static func decodeInline(from decoder: Decoder) throws -> AccessibilityTarget {
        try AccessibilityTarget(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .predicate(let predicate, let ordinal):
            try predicate.encode(to: encoder)
            if let ordinal {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(ordinal, forKey: .ordinal)
            }
        case .container(let predicate, let ordinal):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(predicate, forKey: .container)
            try container.encodeIfPresent(ordinal, forKey: .ordinal)
        case .ref(let reference):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(reference, forKey: .ref)
        case .within(let containerPredicate, let target):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(containerPredicate, forKey: .container)
            try container.encode(target, forKey: .target)
        }
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedAccessibilityTarget {
        switch self {
        case .predicate(let predicate, let ordinal):
            return .predicate(
                try predicate.resolve(in: environment),
                ordinal: try Self.validatedOrdinal(ordinal)
            )
        case .container(let predicate, let ordinal):
            return .container(
                try predicate.resolve(in: environment),
                ordinal: try Self.validatedOrdinal(ordinal)
            )
        case .ref(let reference):
            guard let target = environment.targets[reference] else {
                throw HeistExpressionError.unresolvedTargetReference(reference.rawValue)
            }
            return target
        case .within(let container, let target):
            return .within(
                container: try container.resolve(in: environment),
                target: try target.resolve(in: environment)
            )
        }
    }

    public func and(_ checks: ElementPredicateCheck...) -> AccessibilityTarget {
        appending(checks)
    }

    public func excluding(_ checks: ElementPredicateCheck...) -> AccessibilityTarget {
        appending(checks.map { .exclude($0) })
    }

    private func appending(_ checks: [ElementPredicateCheck]) -> AccessibilityTarget {
        guard case .predicate(let predicate, let ordinal) = self else { return self }
        return .predicate(
            ElementPredicate(core: ElementPredicateCore(predicate.core.checks + checks.map(\.core))),
            ordinal: ordinal
        )
    }

    private static func decodeOrdinal(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Int? {
        let ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)
        do {
            return try validatedOrdinal(ordinal)
        } catch let error as AccessibilityTargetGrammarError {
            throw DecodingError.dataCorruptedError(
                forKey: .ordinal,
                in: container,
                debugDescription: error.diagnosticDescription
            )
        }
    }

    private static func validatedOrdinal(_ ordinal: Int?) throws -> Int? {
        if let ordinal, ordinal < 0 {
            throw AccessibilityTargetGrammarError.negativeOrdinal(ordinal)
        }
        return ordinal
    }
}

extension AccessibilityTarget: CustomStringConvertible {
    public var description: String {
        switch self {
        case .predicate(let predicate, let ordinal):
            return CanonicalValueDescription.call("target", [
                predicate.description,
                CanonicalValueDescription.valueField("ordinal", ordinal),
            ].compactMap { $0 })
        case .container(let predicate, let ordinal):
            return CanonicalValueDescription.call("container", [
                predicate.description,
                CanonicalValueDescription.valueField("ordinal", ordinal),
            ].compactMap { $0 })
        case .ref(let reference):
            return CanonicalValueDescription.call("ref", [reference.description])
        case .within(let container, let target):
            return CanonicalValueDescription.call("within", [container.description, target.description])
        }
    }
}

/// The execution-phase target currency. There is deliberately no reference
/// case and no expression-bearing predicate payload.
public indirect enum ResolvedAccessibilityTarget: Codable, Sendable, Equatable, Hashable {
    case predicate(ResolvedElementPredicate, ordinal: Int? = nil)
    case container(ResolvedContainerPredicate, ordinal: Int? = nil)
    case within(container: ResolvedContainerPredicate, target: ResolvedAccessibilityTarget)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case ordinal, container, target
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.container) || container.contains(.target) {
            guard container.contains(.container) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .target,
                    in: container,
                    debugDescription: "scoped resolved accessibility target requires container"
                )
            }
            if container.contains(.target) {
                try decoder.rejectUnknownKeys(
                    allowed: [CodingKeys.container.stringValue, CodingKeys.target.stringValue],
                    typeName: "scoped resolved accessibility target"
                )
                self = .within(
                    container: try container.decode(ResolvedContainerPredicate.self, forKey: .container),
                    target: try container.decode(ResolvedAccessibilityTarget.self, forKey: .target)
                )
            } else {
                try decoder.rejectUnknownKeys(
                    allowed: [CodingKeys.container.stringValue, CodingKeys.ordinal.stringValue],
                    typeName: "resolved container accessibility target"
                )
                self = .container(
                    try container.decode(ResolvedContainerPredicate.self, forKey: .container),
                    ordinal: try Self.decodeOrdinal(from: container)
                )
            }
            return
        }

        try decoder.rejectUnknownKeys(
            allowed: Set([ElementPredicateCodingKeys.checks.stringValue, CodingKeys.ordinal.stringValue]),
            typeName: "resolved accessibility target"
        )
        let predicateContainer = try decoder.container(keyedBy: ElementPredicateCodingKeys.self)
        let predicate = ResolvedElementPredicate(core: ElementPredicateCore(
            try predicateContainer.decodeIfPresent(
                [ElementPredicateCheckCore<String>].self,
                forKey: .checks
            ) ?? []
        ))
        guard predicate.hasPredicates else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: AccessibilityTargetGrammarError.emptyPredicate.diagnosticDescription
            ))
        }
        self = .predicate(predicate, ordinal: try Self.decodeOrdinal(from: container))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .predicate(let predicate, let ordinal):
            try predicate.encode(to: encoder)
            if let ordinal {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(ordinal, forKey: .ordinal)
            }
        case .container(let predicate, let ordinal):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(predicate, forKey: .container)
            try container.encodeIfPresent(ordinal, forKey: .ordinal)
        case .within(let containerPredicate, let target):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(containerPredicate, forKey: .container)
            try container.encode(target, forKey: .target)
        }
    }

    private static func decodeOrdinal(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Int? {
        let ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)
        if let ordinal, ordinal < 0 {
            throw DecodingError.dataCorruptedError(
                forKey: .ordinal,
                in: container,
                debugDescription: AccessibilityTargetGrammarError.negativeOrdinal(ordinal).diagnosticDescription
            )
        }
        return ordinal
    }
}

extension ResolvedAccessibilityTarget: CustomStringConvertible {
    public var description: String {
        switch self {
        case .predicate(let predicate, let ordinal):
            return CanonicalValueDescription.call("target", [
                predicate.description,
                CanonicalValueDescription.valueField("ordinal", ordinal),
            ].compactMap { $0 })
        case .container(let predicate, let ordinal):
            return CanonicalValueDescription.call("container", [
                predicate.description,
                CanonicalValueDescription.valueField("ordinal", ordinal),
            ].compactMap { $0 })
        case .within(let container, let target):
            return CanonicalValueDescription.call("within", [container.description, target.description])
        }
    }
}

private enum ElementPredicateCodingKeys: String, CodingKey {
    case checks
}
