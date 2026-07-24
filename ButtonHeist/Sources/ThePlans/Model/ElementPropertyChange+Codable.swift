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

private enum CustomContentMatchCodingKeys: String, CodingKey, CaseIterable {
    case label, value, isImportant
}

extension CustomContentMatch {
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CustomContentMatchCodingKeys.self, typeName: "custom content match")
        let container = try decoder.container(keyedBy: CustomContentMatchCodingKeys.self)
        self.init(
            label: try container.decodeIfPresent(StringMatch.self, forKey: .label),
            value: try container.decodeIfPresent(StringMatch.self, forKey: .value),
            isImportant: try container.decodeIfPresent(Bool.self, forKey: .isImportant)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CustomContentMatchCodingKeys.self)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(isImportant, forKey: .isImportant)
    }
}

extension ResolvedCustomContentMatch {
    package init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CustomContentMatchCodingKeys.self, typeName: "custom content match")
        let container = try decoder.container(keyedBy: CustomContentMatchCodingKeys.self)
        self.init(
            label: try container.decodeIfPresent(ResolvedStringMatch.self, forKey: .label),
            value: try container.decodeIfPresent(ResolvedStringMatch.self, forKey: .value),
            isImportant: try container.decodeIfPresent(Bool.self, forKey: .isImportant)
        )
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CustomContentMatchCodingKeys.self)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(isImportant, forKey: .isImportant)
    }
}

private enum RotorSetMatchCodingKeys: String, CodingKey, CaseIterable {
    case include, exclude
}

extension RotorSetMatch {
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: RotorSetMatchCodingKeys.self, typeName: "rotor set match")
        let container = try decoder.container(keyedBy: RotorSetMatchCodingKeys.self)
        self.init(
            include: try container.decodeIfPresent([StringMatch].self, forKey: .include) ?? [],
            exclude: try container.decodeIfPresent([StringMatch].self, forKey: .exclude) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RotorSetMatchCodingKeys.self)
        try container.encode(include, forKey: .include)
        try container.encode(exclude, forKey: .exclude)
    }
}

extension ResolvedRotorSetMatch {
    package init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: RotorSetMatchCodingKeys.self, typeName: "rotor set match")
        let container = try decoder.container(keyedBy: RotorSetMatchCodingKeys.self)
        self.init(
            include: try container.decodeIfPresent([ResolvedStringMatch].self, forKey: .include) ?? [],
            exclude: try container.decodeIfPresent([ResolvedStringMatch].self, forKey: .exclude) ?? []
        )
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RotorSetMatchCodingKeys.self)
        try container.encode(include, forKey: .include)
        try container.encode(exclude, forKey: .exclude)
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

extension AuthoredElementPropertyChange: Codable {
    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ElementProperty.self)
        let keys = container.allKeys
        guard keys.count == 1, let key = keys.first else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected exactly one property change case"
            ))
        }
        switch key {
        case .label, .identifier:
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "\(key.rawValue) is not an update property"
            ))
        case .value:
            self = .value(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<StringMatch>.self, forKey: key, from: container
            ))
        case .traits:
            self = .traits(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<TraitSetMatch>.self, forKey: key, from: container
            ))
        case .hint:
            self = .hint(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<StringMatch>.self, forKey: key, from: container
            ))
        case .actions:
            self = .actions(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<ActionSetMatch>.self, forKey: key, from: container
            ))
        case .frame:
            self = .frame(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<ElementFrameMatch>.self, forKey: key, from: container
            ))
        case .activationPoint:
            self = .activationPoint(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<ElementPointMatch>.self, forKey: key, from: container
            ))
        case .customContent:
            self = .customContent(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<CustomContentMatch>.self, forKey: key, from: container
            ))
        case .rotors:
            self = .rotors(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<RotorSetMatch>.self, forKey: key, from: container
            ))
        }
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

}

extension ResolvedElementPropertyChangeValue: Codable {
    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ElementProperty.self)
        let keys = container.allKeys
        guard keys.count == 1, let key = keys.first else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected exactly one property change case"
            ))
        }
        switch key {
        case .label, .identifier:
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "\(key.rawValue) is not an update property"
            ))
        case .value:
            self = .value(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<ResolvedStringMatch>.self, forKey: key, from: container
            ))
        case .traits:
            self = .traits(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<TraitSetMatch>.self, forKey: key, from: container
            ))
        case .hint:
            self = .hint(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<ResolvedStringMatch>.self, forKey: key, from: container
            ))
        case .actions:
            self = .actions(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<ActionSetMatch>.self, forKey: key, from: container
            ))
        case .frame:
            self = .frame(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<ElementFrameMatch>.self, forKey: key, from: container
            ))
        case .activationPoint:
            self = .activationPoint(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<ElementPointMatch>.self, forKey: key, from: container
            ))
        case .customContent:
            self = .customContent(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<ResolvedCustomContentMatch>.self, forKey: key, from: container
            ))
        case .rotors:
            self = .rotors(try decodeUnlabeledAssociatedValue(
                PropertyChangeCore<ResolvedRotorSetMatch>.self, forKey: key, from: container
            ))
        }
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
}

extension ElementPropertyChange {
    public init(from decoder: Decoder) throws {
        value = try AuthoredElementPropertyChange(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

extension ResolvedElementPropertyChange {
    public init(from decoder: Decoder) throws {
        value = try ResolvedElementPropertyChangeValue(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
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
        try decodeValueIfPresent(from: container).map { ElementPropertyChange(value: $0) }
    }

    func encodeFields(to container: inout KeyedEncodingContainer<ElementUpdateCodingKeys>) throws {
        try value.encodeFields(to: &container)
    }

    private static func decodeValueIfPresent(
        from container: KeyedDecodingContainer<ElementUpdateCodingKeys>
    ) throws -> AuthoredElementPropertyChange? {
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
        return try AuthoredElementPropertyChange.decode(property: property, from: container)
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
            value: try ResolvedElementPropertyChangeValue.decode(property: property, from: container)
        )
    }

    func encodeFields(to container: inout KeyedEncodingContainer<ElementUpdateCodingKeys>) throws {
        try value.encodeFields(to: &container)
    }
}

private extension AuthoredElementPropertyChange {
    static func decode(
        property: ElementProperty,
        from container: KeyedDecodingContainer<ElementUpdateCodingKeys>
    ) throws -> Self {
        switch property {
        case .label, .identifier:
            throw unsupportedUpdateProperty(property, in: container)
        case .value:
            return .value(try PropertyChangeCore<StringMatch>(from: container))
        case .traits:
            return .traits(try PropertyChangeCore<TraitSetMatch>(from: container))
        case .hint:
            return .hint(try PropertyChangeCore<StringMatch>(from: container))
        case .actions:
            return .actions(try PropertyChangeCore<ActionSetMatch>(from: container))
        case .frame:
            return .frame(try PropertyChangeCore<ElementFrameMatch>(from: container))
        case .activationPoint:
            return .activationPoint(try PropertyChangeCore<ElementPointMatch>(from: container))
        case .customContent:
            return .customContent(try PropertyChangeCore<CustomContentMatch>(from: container))
        case .rotors:
            return .rotors(try PropertyChangeCore<RotorSetMatch>(from: container))
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

private extension ResolvedElementPropertyChangeValue {
    static func decode(
        property: ElementProperty,
        from container: KeyedDecodingContainer<ElementUpdateCodingKeys>
    ) throws -> Self {
        switch property {
        case .label, .identifier:
            throw unsupportedUpdateProperty(property, in: container)
        case .value:
            return .value(try PropertyChangeCore<ResolvedStringMatch>(from: container))
        case .traits:
            return .traits(try PropertyChangeCore<TraitSetMatch>(from: container))
        case .hint:
            return .hint(try PropertyChangeCore<ResolvedStringMatch>(from: container))
        case .actions:
            return .actions(try PropertyChangeCore<ActionSetMatch>(from: container))
        case .frame:
            return .frame(try PropertyChangeCore<ElementFrameMatch>(from: container))
        case .activationPoint:
            return .activationPoint(try PropertyChangeCore<ElementPointMatch>(from: container))
        case .customContent:
            return .customContent(try PropertyChangeCore<ResolvedCustomContentMatch>(from: container))
        case .rotors:
            return .rotors(try PropertyChangeCore<ResolvedRotorSetMatch>(from: container))
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
