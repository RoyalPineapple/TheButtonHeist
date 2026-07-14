import Foundation

extension TraitSetMatch: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable { case include, exclude }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "trait set match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            include: try container.decodeIfPresent([HeistTrait].self, forKey: .include) ?? [],
            exclude: try container.decodeIfPresent([HeistTrait].self, forKey: .exclude) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(include.canonicalHeistTraitArray, forKey: .include)
        try container.encode(exclude.canonicalHeistTraitArray, forKey: .exclude)
    }
}

extension ActionSetMatch: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable { case include, exclude }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "action set match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            include: Set(try container.decodeIfPresent([ElementAction].self, forKey: .include) ?? []),
            exclude: Set(try container.decodeIfPresent([ElementAction].self, forKey: .exclude) ?? [])
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(include.canonicalElementActionArray, forKey: .include)
        try container.encode(exclude.canonicalElementActionArray, forKey: .exclude)
    }
}

extension ElementFrameMatch: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable { case x, y, width, height }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "frame match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decodeIfPresent(Int.self, forKey: .x),
            y: try container.decodeIfPresent(Int.self, forKey: .y),
            width: try container.decodeIfPresent(Int.self, forKey: .width),
            height: try container.decodeIfPresent(Int.self, forKey: .height)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(x, forKey: .x)
        try container.encodeIfPresent(y, forKey: .y)
        try container.encodeIfPresent(width, forKey: .width)
        try container.encodeIfPresent(height, forKey: .height)
    }
}

extension ElementPointMatch: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable { case x, y }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "activation point match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decodeIfPresent(Int.self, forKey: .x),
            y: try container.decodeIfPresent(Int.self, forKey: .y)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(x, forKey: .x)
        try container.encodeIfPresent(y, forKey: .y)
    }
}

extension CustomContentMatchCore: Codable where Text: Codable & StringMatchLeaf {
    private enum CodingKeys: String, CodingKey, CaseIterable { case label, value, isImportant }

    package init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "custom content match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: try container.decodeIfPresent(StringMatchCore<Text>.self, forKey: .label),
            value: try container.decodeIfPresent(StringMatchCore<Text>.self, forKey: .value),
            isImportant: try container.decodeIfPresent(Bool.self, forKey: .isImportant)
        )
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(isImportant, forKey: .isImportant)
    }
}

extension CustomContentMatch {
    public init(from decoder: Decoder) throws {
        core = try CustomContentMatchCore(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try core.encode(to: encoder)
    }
}

extension RotorSetMatchCore: Codable where Text: Codable & StringMatchLeaf {
    private enum CodingKeys: String, CodingKey, CaseIterable { case include, exclude }

    package init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "rotor set match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            include: try container.decodeIfPresent([StringMatchCore<Text>].self, forKey: .include) ?? [],
            exclude: try container.decodeIfPresent([StringMatchCore<Text>].self, forKey: .exclude) ?? []
        )
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(include, forKey: .include)
        try container.encode(exclude, forKey: .exclude)
    }
}

extension RotorSetMatch {
    public init(from decoder: Decoder) throws {
        core = try RotorSetMatchCore(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try core.encode(to: encoder)
    }
}

private enum PropertyChangeCodingKeys: String, CodingKey { case before, after }

extension PropertyChangeCore: Codable where Checker: Codable {
    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: PropertyChangeCodingKeys.self)
        self.init(
            before: try container.decodeIfPresent(Checker.self, forKey: .before),
            after: try container.decodeIfPresent(Checker.self, forKey: .after)
        )
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: PropertyChangeCodingKeys.self)
        try container.encodeIfPresent(before, forKey: .before)
        try container.encodeIfPresent(after, forKey: .after)
    }
}

private enum UnlabeledAssociatedValueCodingKeys: String, CodingKey { case value = "_0" }

private func decodeUnlabeledAssociatedValue<Value: Decodable, Key: CodingKey>(
    _ type: Value.Type,
    forKey key: Key,
    from container: KeyedDecodingContainer<Key>
) throws -> Value {
    let nested = try container.nestedContainer(keyedBy: UnlabeledAssociatedValueCodingKeys.self, forKey: key)
    return try nested.decode(type, forKey: .value)
}

private func encodeUnlabeledAssociatedValue<Value: Encodable, Key: CodingKey>(
    _ value: Value,
    forKey key: Key,
    to container: inout KeyedEncodingContainer<Key>
) throws {
    var nested = container.nestedContainer(keyedBy: UnlabeledAssociatedValueCodingKeys.self, forKey: key)
    try nested.encode(value, forKey: .value)
}

extension ElementPropertyChangeCore: Codable where Text: Codable & StringMatchLeaf {
    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ElementProperty.self)
        let keys = container.allKeys
        guard keys.count == 1, let key = keys.first else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected exactly one property change case"
            ))
        }
        self = try Self.decode(property: key, from: container)
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ElementProperty.self)
        switch self {
        case .value(let change):
            try encodeUnlabeledAssociatedValue(change, forKey: .value, to: &container)
        case .traits(let change):
            try encodeUnlabeledAssociatedValue(change, forKey: .traits, to: &container)
        case .hint(let change):
            try encodeUnlabeledAssociatedValue(change, forKey: .hint, to: &container)
        case .actions(let change):
            try encodeUnlabeledAssociatedValue(change, forKey: .actions, to: &container)
        case .frame(let change):
            try encodeUnlabeledAssociatedValue(change, forKey: .frame, to: &container)
        case .activationPoint(let change):
            try encodeUnlabeledAssociatedValue(change, forKey: .activationPoint, to: &container)
        case .customContent(let change):
            try encodeUnlabeledAssociatedValue(change, forKey: .customContent, to: &container)
        case .rotors(let change):
            try encodeUnlabeledAssociatedValue(change, forKey: .rotors, to: &container)
        }
    }

    private static func decode(
        property: ElementProperty,
        from container: KeyedDecodingContainer<ElementProperty>
    ) throws -> Self {
        switch property {
        case .label, .identifier:
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "\(property.rawValue) is not an update property"
            ))
        case .value:
            return .value(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<StringMatchCore<Text>>.self,
                forKey: property,
                from: container
            ))
        case .traits:
            return .traits(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<TraitSetMatch>.self,
                forKey: property,
                from: container
            ))
        case .hint:
            return .hint(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<StringMatchCore<Text>>.self,
                forKey: property,
                from: container
            ))
        case .actions:
            return .actions(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<ActionSetMatch>.self,
                forKey: property,
                from: container
            ))
        case .frame:
            return .frame(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<ElementFrameMatch>.self,
                forKey: property,
                from: container
            ))
        case .activationPoint:
            return .activationPoint(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<ElementPointMatch>.self,
                forKey: property,
                from: container
            ))
        case .customContent:
            return .customContent(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<CustomContentMatchCore<Text>>.self,
                forKey: property,
                from: container
            ))
        case .rotors:
            return .rotors(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<RotorSetMatchCore<Text>>.self,
                forKey: property,
                from: container
            ))
        }
    }
}

extension ElementPropertyChange {
    public init(from decoder: Decoder) throws {
        core = try ElementPropertyChangeCore(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try core.encode(to: encoder)
    }
}

extension ResolvedElementPropertyChange {
    public init(from decoder: Decoder) throws {
        core = try ElementPropertyChangeCore(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try core.encode(to: encoder)
    }
}

package enum ElementUpdateCodingKeys: String, CodingKey, CaseIterable {
    case type, element, target, before, after, property
}

private func unsupportedUpdateProperty(
    _ property: ElementProperty,
    in container: KeyedDecodingContainer<ElementUpdateCodingKeys>
) -> DecodingError {
    DecodingError.dataCorruptedError(
        forKey: .property,
        in: container,
        debugDescription: "\(property.rawValue) is an element identity matcher, not an update property"
    )
}

package extension ElementPropertyChange {
    static func decodeIfPresent(
        from container: KeyedDecodingContainer<ElementUpdateCodingKeys>
    ) throws -> ElementPropertyChange? {
        try decodeCoreIfPresent(from: container).map { ElementPropertyChange(core: $0) }
    }

    func encodeFields(to container: inout KeyedEncodingContainer<ElementUpdateCodingKeys>) throws {
        try core.encodeFields(to: &container)
    }

    private static func decodeCoreIfPresent(
        from container: KeyedDecodingContainer<ElementUpdateCodingKeys>
    ) throws -> ElementPropertyChangeCore<Expr<String>>? {
        let hasBefore = container.contains(.before)
        let hasAfter = container.contains(.after)
        guard let property = try container.decodeIfPresent(ElementProperty.self, forKey: .property) else {
            guard !hasBefore && !hasAfter else {
                throw DecodingError.dataCorruptedError(
                    forKey: .property,
                    in: container,
                    debugDescription: "updated predicate before/after require property"
                )
            }
            return nil
        }
        return try ElementPropertyChangeCore.decode(property: property, from: container)
    }
}

package extension ResolvedElementPropertyChange {
    static func decodeIfPresent(
        from container: KeyedDecodingContainer<ElementUpdateCodingKeys>
    ) throws -> ResolvedElementPropertyChange? {
        let hasBefore = container.contains(.before)
        let hasAfter = container.contains(.after)
        guard let property = try container.decodeIfPresent(ElementProperty.self, forKey: .property) else {
            guard !hasBefore && !hasAfter else {
                throw DecodingError.dataCorruptedError(
                    forKey: .property,
                    in: container,
                    debugDescription: "updated predicate before/after require property"
                )
            }
            return nil
        }
        return ResolvedElementPropertyChange(
            core: try ElementPropertyChangeCore<String>.decode(property: property, from: container)
        )
    }

    func encodeFields(to container: inout KeyedEncodingContainer<ElementUpdateCodingKeys>) throws {
        try core.encodeFields(to: &container)
    }
}

private extension ElementPropertyChangeCore where Text: Codable & StringMatchLeaf {
    static func decode(
        property: ElementProperty,
        from container: KeyedDecodingContainer<ElementUpdateCodingKeys>
    ) throws -> Self {
        switch property {
        case .label, .identifier:
            throw unsupportedUpdateProperty(property, in: container)
        case .value:
            return .value(try PropertyChangeCore<StringMatchCore<Text>>(from: container))
        case .traits:
            return .traits(try PropertyChangeCore<TraitSetMatch>(from: container))
        case .hint:
            return .hint(try PropertyChangeCore<StringMatchCore<Text>>(from: container))
        case .actions:
            return .actions(try PropertyChangeCore<ActionSetMatch>(from: container))
        case .frame:
            return .frame(try PropertyChangeCore<ElementFrameMatch>(from: container))
        case .activationPoint:
            return .activationPoint(try PropertyChangeCore<ElementPointMatch>(from: container))
        case .customContent:
            return .customContent(try PropertyChangeCore<CustomContentMatchCore<Text>>(from: container))
        case .rotors:
            return .rotors(try PropertyChangeCore<RotorSetMatchCore<Text>>(from: container))
        }
    }

    func encodeFields(to container: inout KeyedEncodingContainer<ElementUpdateCodingKeys>) throws {
        try container.encode(property, forKey: .property)
        switch self {
        case .value(let change): try change.encodeFields(to: &container)
        case .traits(let change): try change.encodeFields(to: &container)
        case .hint(let change): try change.encodeFields(to: &container)
        case .actions(let change): try change.encodeFields(to: &container)
        case .frame(let change): try change.encodeFields(to: &container)
        case .activationPoint(let change): try change.encodeFields(to: &container)
        case .customContent(let change): try change.encodeFields(to: &container)
        case .rotors(let change): try change.encodeFields(to: &container)
        }
    }
}

private extension PropertyChangeCore where Checker: Codable {
    init(from container: KeyedDecodingContainer<ElementUpdateCodingKeys>) throws {
        self.init(
            before: try container.decodeIfPresent(Checker.self, forKey: .before),
            after: try container.decodeIfPresent(Checker.self, forKey: .after)
        )
    }

    func encodeFields(to container: inout KeyedEncodingContainer<ElementUpdateCodingKeys>) throws {
        try container.encodeIfPresent(before, forKey: .before)
        try container.encodeIfPresent(after, forKey: .after)
    }
}
