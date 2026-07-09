// MARK: - Element Property Match Payloads

/// Required and forbidden traits in a property's trait set.
public struct TraitSetMatch: Sendable, Equatable {
    public let include: Set<HeistTrait>
    public let exclude: Set<HeistTrait>

    public init(include: [HeistTrait] = [], exclude: [HeistTrait] = []) {
        self.include = include.heistTraitSet
        self.exclude = exclude.heistTraitSet
    }
}

/// Required and forbidden actions in an element's action list.
public struct ActionSetMatch: Sendable, Equatable {
    public let include: Set<ElementAction>
    public let exclude: Set<ElementAction>

    public init(include: Set<ElementAction> = [], exclude: Set<ElementAction> = []) {
        self.include = include
        self.exclude = exclude
    }
}

/// Integer geometry checker for a captured accessibility frame.
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

/// Integer geometry checker for a captured accessibility activation point.
public struct ElementPointMatch: Sendable, Equatable {
    public let x: Int?
    public let y: Int?

    public init(x: Int? = nil, y: Int? = nil) {
        self.x = x
        self.y = y
    }
}

/// Field-level checker for one custom-content item in the element's custom content list.
public struct CustomContentMatch<Value: StringMatchPayload>: Sendable, Equatable, Hashable where Value: Codable {
    public let label: StringMatch<Value>?
    public let value: StringMatch<Value>?
    public let isImportant: Bool?

    public init(
        label: StringMatch<Value>? = nil,
        value: StringMatch<Value>? = nil,
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

    public func map<NewValue: StringMatchPayload>(
        _ transform: (Value) throws -> NewValue
    ) rethrows -> CustomContentMatch<NewValue> where NewValue: Codable {
        try CustomContentMatch<NewValue>(
            label: label?.map(transform),
            value: value?.map(transform),
            isImportant: isImportant
        )
    }
}

/// Required and forbidden rotor names in an element's rotor list.
public struct RotorSetMatch<Value: StringMatchPayload>: Sendable, Equatable where Value: Codable {
    public let include: [StringMatch<Value>]
    public let exclude: [StringMatch<Value>]

    public init(include: [StringMatch<Value>] = [], exclude: [StringMatch<Value>] = []) {
        self.include = include
        self.exclude = exclude
    }

    public func map<NewValue: StringMatchPayload>(
        _ transform: (Value) throws -> NewValue
    ) rethrows -> RotorSetMatch<NewValue> where NewValue: Codable {
        try RotorSetMatch<NewValue>(
            include: include.map { try $0.map(transform) },
            exclude: exclude.map { try $0.map(transform) }
        )
    }
}
