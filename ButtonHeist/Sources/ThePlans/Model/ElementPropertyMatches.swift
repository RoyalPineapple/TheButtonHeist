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

package struct CustomContentMatchCore<Text> {
    package let label: StringMatchCore<Text>?
    package let value: StringMatchCore<Text>?
    package let isImportant: Bool?

    package init(
        label: StringMatchCore<Text>? = nil,
        value: StringMatchCore<Text>? = nil,
        isImportant: Bool? = nil
    ) {
        self.label = label
        self.value = value
        self.isImportant = isImportant
    }

    package func map<NewText>(
        _ transform: (Text) throws -> NewText
    ) rethrows -> CustomContentMatchCore<NewText> {
        try CustomContentMatchCore<NewText>(
            label: label?.map(transform),
            value: value?.map(transform),
            isImportant: isImportant
        )
    }
}

extension CustomContentMatchCore: Sendable where Text: Sendable {}
extension CustomContentMatchCore: Equatable where Text: Equatable {}
extension CustomContentMatchCore: Hashable where Text: Hashable {}

package extension CustomContentMatchCore where Text: StringMatchLeaf {
    var hasPredicateLiteral: Bool {
        label?.hasPredicateLiteral == true
            || value?.hasPredicateLiteral == true
            || isImportant != nil
    }
}

public struct CustomContentMatch: Codable, Sendable, Equatable, Hashable {
    package let core: CustomContentMatchCore<AuthoredString>

    package init(core: CustomContentMatchCore<AuthoredString>) {
        self.core = core
    }

    public init(
        label: StringMatch? = nil,
        value: StringMatch? = nil,
        isImportant: Bool? = nil
    ) {
        core = CustomContentMatchCore(
            label: label?.core,
            value: value?.core,
            isImportant: isImportant
        )
    }

    public var hasPredicateLiteral: Bool { core.hasPredicateLiteral }
    public var label: StringMatch? { core.label.map { StringMatch(core: $0) } }
    public var value: StringMatch? { core.value.map { StringMatch(core: $0) } }
    public var isImportant: Bool? { core.isImportant }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> CustomContentMatchCore<String> {
        try core.map { try $0.resolve(in: environment) }
    }
}

package struct RotorSetMatchCore<Text> {
    package let include: [StringMatchCore<Text>]
    package let exclude: [StringMatchCore<Text>]

    package init(
        include: [StringMatchCore<Text>] = [],
        exclude: [StringMatchCore<Text>] = []
    ) {
        self.include = include
        self.exclude = exclude
    }

    package func map<NewText>(
        _ transform: (Text) throws -> NewText
    ) rethrows -> RotorSetMatchCore<NewText> {
        try RotorSetMatchCore<NewText>(
            include: include.map { try $0.map(transform) },
            exclude: exclude.map { try $0.map(transform) }
        )
    }
}

extension RotorSetMatchCore: Sendable where Text: Sendable {}
extension RotorSetMatchCore: Equatable where Text: Equatable {}
extension RotorSetMatchCore: Hashable where Text: Hashable {}

public struct RotorSetMatch: Codable, Sendable, Equatable, Hashable {
    package let core: RotorSetMatchCore<AuthoredString>

    package init(core: RotorSetMatchCore<AuthoredString>) {
        self.core = core
    }

    public init(include: [StringMatch] = [], exclude: [StringMatch] = []) {
        core = RotorSetMatchCore(
            include: include.map(\.core),
            exclude: exclude.map(\.core)
        )
    }

    public var include: [StringMatch] { core.include.map { StringMatch(core: $0) } }
    public var exclude: [StringMatch] { core.exclude.map { StringMatch(core: $0) } }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> RotorSetMatchCore<String> {
        try core.map { try $0.resolve(in: environment) }
    }
}
