// MARK: - Element Property Match Payloads

public struct TraitSetMatch: Sendable, Equatable {
    public let include: Set<HeistTrait>
    public let exclude: Set<HeistTrait>

    public init(include: [HeistTrait] = [], exclude: [HeistTrait] = []) {
        self.include = include.heistTraitSet
        self.exclude = exclude.heistTraitSet
    }

    public static func includes(_ traits: HeistTrait...) -> Self {
        Self(include: traits)
    }

    public static func excludes(_ traits: HeistTrait...) -> Self {
        Self(exclude: traits)
    }
}

public struct ActionSetMatch: Sendable, Equatable {
    public let include: Set<ElementAction>
    public let exclude: Set<ElementAction>

    public init(include: Set<ElementAction> = [], exclude: Set<ElementAction> = []) {
        self.include = include
        self.exclude = exclude
    }

    public static func includes(_ actions: ElementAction...) -> Self {
        Self(include: Set(actions))
    }

    public static func excludes(_ actions: ElementAction...) -> Self {
        Self(exclude: Set(actions))
    }
}

public struct CustomContentMatch: Codable, Sendable, Equatable, Hashable {
    public let label: StringMatch?
    public let value: StringMatch?
    public let isImportant: Bool?

    public init(
        label: StringMatch? = nil,
        value: StringMatch? = nil,
        isImportant: Bool? = nil
    ) {
        self.label = label
        self.value = value
        self.isImportant = isImportant
    }

    public var hasPredicateLiteral: Bool {
        label?.hasPredicateLiteral == true
            || value?.hasPredicateLiteral == true
            || isImportant != nil
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedCustomContentMatch {
        ResolvedCustomContentMatch(
            label: try label?.resolve(in: environment),
            value: try value?.resolve(in: environment),
            isImportant: isImportant
        )
    }
}

package struct ResolvedCustomContentMatch: Codable, Sendable, Equatable, Hashable {
    package let label: ResolvedStringMatch?
    package let value: ResolvedStringMatch?
    package let isImportant: Bool?

    package init(
        label: ResolvedStringMatch? = nil,
        value: ResolvedStringMatch? = nil,
        isImportant: Bool? = nil
    ) {
        self.label = label
        self.value = value
        self.isImportant = isImportant
    }

    package var hasPredicateLiteral: Bool {
        label?.hasPredicateLiteral == true
            || value?.hasPredicateLiteral == true
            || isImportant != nil
    }
}

public struct RotorSetMatch: Codable, Sendable, Equatable, Hashable {
    public let include: [StringMatch]
    public let exclude: [StringMatch]

    public init(include: [StringMatch] = [], exclude: [StringMatch] = []) {
        self.include = include
        self.exclude = exclude
    }

    public static func includes(_ matches: StringMatch...) -> Self {
        Self(include: matches)
    }

    public static func excludes(_ matches: StringMatch...) -> Self {
        Self(exclude: matches)
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedRotorSetMatch {
        ResolvedRotorSetMatch(
            include: try include.map { try $0.resolve(in: environment) },
            exclude: try exclude.map { try $0.resolve(in: environment) }
        )
    }
}

package struct ResolvedRotorSetMatch: Codable, Sendable, Equatable, Hashable {
    package let include: [ResolvedStringMatch]
    package let exclude: [ResolvedStringMatch]

    package init(include: [ResolvedStringMatch] = [], exclude: [ResolvedStringMatch] = []) {
        self.include = include
        self.exclude = exclude
    }
}
