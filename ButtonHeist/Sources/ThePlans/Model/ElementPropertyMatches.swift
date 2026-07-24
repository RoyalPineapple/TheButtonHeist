// MARK: - Element Property Match Payloads

public struct TraitSetMatch: Sendable, Equatable {
    public let include: Set<HeistTrait>
    public let exclude: Set<HeistTrait>

    public init(include: [HeistTrait] = [], exclude: [HeistTrait] = []) {
        self.include = include.heistTraitSet
        self.exclude = exclude.heistTraitSet
    }
}

public struct ActionSetMatch: Sendable, Equatable {
    public let include: Set<ElementAction>
    public let exclude: Set<ElementAction>

    public init(include: Set<ElementAction> = [], exclude: Set<ElementAction> = []) {
        self.include = include
        self.exclude = exclude
    }
}

public struct ElementFrameMatch: Sendable, Equatable {
    public let x: Int?
    public let y: Int?
    public let width: Int?
    public let height: Int?

    public init(x: Int? = nil, y: Int? = nil, width: Int? = nil, height: Int? = nil) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct ElementPointMatch: Sendable, Equatable {
    public let x: Int?
    public let y: Int?

    public init(x: Int? = nil, y: Int? = nil) {
        self.x = x
        self.y = y
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
