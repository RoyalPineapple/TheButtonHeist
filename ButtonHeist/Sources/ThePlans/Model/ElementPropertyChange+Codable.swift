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
        let container = try decoder.container(keyedBy: AssertableProperty.self)
        let key = try container.singlePropertyChangeKey(at: decoder.codingPath)
        switch key {
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
        var container = encoder.container(keyedBy: AssertableProperty.self)
        switch self {
        case .value(let change):
            try encodeUnlabeledAssociatedValue(change, forKey: .value, to: &container)
        case .traits(let change):
            try encodeUnlabeledAssociatedValue(change, forKey: .traits, to: &container)
        case .hint(let change):
            try encodeUnlabeledAssociatedValue(change, forKey: .hint, to: &container)
        case .actions(let change):
            try encodeUnlabeledAssociatedValue(change, forKey: .actions, to: &container)
        case .customContent(let change):
            try encodeUnlabeledAssociatedValue(change, forKey: .customContent, to: &container)
        case .rotors(let change):
            try encodeUnlabeledAssociatedValue(change, forKey: .rotors, to: &container)
        }
    }

}

extension KeyedDecodingContainer where Key == AssertableProperty {
    /// The one property this change names.
    ///
    /// A geometry key lands here as no key at all, because `AssertableProperty`
    /// has no case for it, so the count check is what reports it. The message
    /// names the vocabulary rather than the key, since the key is precisely what
    /// could not be understood.
    func singlePropertyChangeKey(at codingPath: [CodingKey]) throws -> AssertableProperty {
        guard allKeys.count == 1, let key = allKeys.first else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: """
                    Expected exactly one property change case. Valid: \(AssertableProperty.nameList)
                    """
            ))
        }
        return key
    }
}

extension ResolvedElementPropertyChangeValue: Codable {
    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AssertableProperty.self)
        let key = try container.singlePropertyChangeKey(at: decoder.codingPath)
        switch key {
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
        var container = encoder.container(keyedBy: AssertableProperty.self)
        switch self {
        case .value(let change):
            try encodeUnlabeledAssociatedValue(change, forKey: .value, to: &container)
        case .traits(let change):
            try encodeUnlabeledAssociatedValue(change, forKey: .traits, to: &container)
        case .hint(let change):
            try encodeUnlabeledAssociatedValue(change, forKey: .hint, to: &container)
        case .actions(let change):
            try encodeUnlabeledAssociatedValue(change, forKey: .actions, to: &container)
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

extension KeyedDecodingContainer where Key == ElementUpdateCodingKeys {
    /// The assertable property this update names, if it named one.
    ///
    /// The wire speaks the observation vocabulary, so it can name a property the
    /// predicate language has no case for. That is a decode error rather than a
    /// silently ignored field: a plan asserting on geometry does not mean what it
    /// looks like it means, so it is refused rather than reinterpreted.
    func decodeAssertablePropertyIfPresent() throws -> AssertableProperty? {
        guard let observed = try decodeIfPresent(ElementProperty.self, forKey: .property) else {
            return nil
        }
        guard let assertable = observed.assertable else {
            throw DecodingError.dataCorruptedError(
                forKey: .property,
                in: self,
                debugDescription: observed.isGeometry
                    ? """
                        \(observed.rawValue) is geometry, which predicates cannot reason about. \
                        Valid: \(AssertableProperty.nameList)
                        """
                    : """
                        \(observed.rawValue) is an element identity matcher, not an update property. \
                        Valid: \(AssertableProperty.nameList)
                        """
            )
        }
        return assertable
    }
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
        guard let property = try container.decodeAssertablePropertyIfPresent() else {
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
        guard let property = try container.decodeAssertablePropertyIfPresent() else {
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
        property: AssertableProperty,
        from container: KeyedDecodingContainer<ElementUpdateCodingKeys>
    ) throws -> Self {
        switch property {
        case .value:
            return .value(try PropertyChangeCore<StringMatch>(from: container))
        case .traits:
            return .traits(try PropertyChangeCore<TraitSetMatch>(from: container))
        case .hint:
            return .hint(try PropertyChangeCore<StringMatch>(from: container))
        case .actions:
            return .actions(try PropertyChangeCore<ActionSetMatch>(from: container))
        case .customContent:
            return .customContent(try PropertyChangeCore<CustomContentMatch>(from: container))
        case .rotors:
            return .rotors(try PropertyChangeCore<RotorSetMatch>(from: container))
        }
    }

    func encodeFields(to container: inout KeyedEncodingContainer<ElementUpdateCodingKeys>) throws {
        try container.encode(property.observed, forKey: .property)
        switch self {
        case .value(let change): try change.encodeFields(to: &container)
        case .traits(let change): try change.encodeFields(to: &container)
        case .hint(let change): try change.encodeFields(to: &container)
        case .actions(let change): try change.encodeFields(to: &container)
        case .customContent(let change): try change.encodeFields(to: &container)
        case .rotors(let change): try change.encodeFields(to: &container)
        }
    }
}

private extension ResolvedElementPropertyChangeValue {
    static func decode(
        property: AssertableProperty,
        from container: KeyedDecodingContainer<ElementUpdateCodingKeys>
    ) throws -> Self {
        switch property {
        case .value:
            return .value(try PropertyChangeCore<ResolvedStringMatch>(from: container))
        case .traits:
            return .traits(try PropertyChangeCore<TraitSetMatch>(from: container))
        case .hint:
            return .hint(try PropertyChangeCore<ResolvedStringMatch>(from: container))
        case .actions:
            return .actions(try PropertyChangeCore<ActionSetMatch>(from: container))
        case .customContent:
            return .customContent(try PropertyChangeCore<ResolvedCustomContentMatch>(from: container))
        case .rotors:
            return .rotors(try PropertyChangeCore<ResolvedRotorSetMatch>(from: container))
        }
    }

    func encodeFields(to container: inout KeyedEncodingContainer<ElementUpdateCodingKeys>) throws {
        try container.encode(property.observed, forKey: .property)
        switch self {
        case .value(let change): try change.encodeFields(to: &container)
        case .traits(let change): try change.encodeFields(to: &container)
        case .hint(let change): try change.encodeFields(to: &container)
        case .actions(let change): try change.encodeFields(to: &container)
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
