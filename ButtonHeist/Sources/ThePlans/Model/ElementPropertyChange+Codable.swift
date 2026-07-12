import Foundation

// MARK: - Element Property Match Codable

extension TraitSetMatch: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case include, exclude
    }

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
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case include, exclude
    }

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
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case x, y, width, height
    }

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
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case x, y
    }

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

extension CustomContentMatch: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case label, value, isImportant
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "custom content match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: try container.decodeIfPresent(StringMatch<Value>.self, forKey: .label),
            value: try container.decodeIfPresent(StringMatch<Value>.self, forKey: .value),
            isImportant: try container.decodeIfPresent(Bool.self, forKey: .isImportant)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(isImportant, forKey: .isImportant)
    }
}

extension RotorSetMatch: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case include, exclude
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "rotor set match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            include: try container.decodeIfPresent([StringMatch<Value>].self, forKey: .include) ?? [],
            exclude: try container.decodeIfPresent([StringMatch<Value>].self, forKey: .exclude) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(include, forKey: .include)
        try container.encode(exclude, forKey: .exclude)
    }
}

// MARK: - Element Property Change Codable

private enum ElementPropertyChangeCodingKeys: String, CodingKey {
    case before, after
}

extension ElementPropertyChange: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ElementPropertyChangeCodingKeys.self)
        self.init(
            before: try container.decodeIfPresent(P.Checker.self, forKey: .before),
            after: try container.decodeIfPresent(P.Checker.self, forKey: .after)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ElementPropertyChangeCodingKeys.self)
        try container.encodeIfPresent(before, forKey: .before)
        try container.encodeIfPresent(after, forKey: .after)
    }
}

extension ElementPropertyChangeExpr: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ElementPropertyChangeCodingKeys.self)
        self.init(
            before: try container.decodeIfPresent(P.ExprChecker.self, forKey: .before),
            after: try container.decodeIfPresent(P.ExprChecker.self, forKey: .after)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ElementPropertyChangeCodingKeys.self)
        try container.encodeIfPresent(before, forKey: .before)
        try container.encodeIfPresent(after, forKey: .after)
    }
}

// MARK: - Erased Element Property Change Codable

private enum UnlabeledAssociatedValueCodingKeys: String, CodingKey {
    case value = "_0"
}

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

extension AnyPropertyChange: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ElementProperty.self)
        let keys = container.allKeys
        guard keys.count == 1, let key = keys.first else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected exactly one property change case"
                )
            )
        }

        switch key {
        case .label, .identifier:
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "\(key.rawValue) is not an update property")
            )
        case .value:
            self = .value(try decodeUnlabeledAssociatedValue(
                ElementPropertyChange<ValueProperty>.self,
                forKey: key,
                from: container
            ))
        case .traits:
            self = .traits(try decodeUnlabeledAssociatedValue(
                ElementPropertyChange<TraitsProperty>.self,
                forKey: key,
                from: container
            ))
        case .hint:
            self = .hint(try decodeUnlabeledAssociatedValue(
                ElementPropertyChange<HintProperty>.self,
                forKey: key,
                from: container
            ))
        case .actions:
            self = .actions(try decodeUnlabeledAssociatedValue(
                ElementPropertyChange<ActionsProperty>.self,
                forKey: key,
                from: container
            ))
        case .frame:
            self = .frame(try decodeUnlabeledAssociatedValue(
                ElementPropertyChange<FrameProperty>.self,
                forKey: key,
                from: container
            ))
        case .activationPoint:
            self = .activationPoint(try decodeUnlabeledAssociatedValue(
                ElementPropertyChange<ActivationPointProperty>.self,
                forKey: key,
                from: container
            ))
        case .customContent:
            self = .customContent(try decodeUnlabeledAssociatedValue(
                ElementPropertyChange<CustomContentProperty>.self,
                forKey: key,
                from: container
            ))
        case .rotors:
            self = .rotors(try decodeUnlabeledAssociatedValue(
                ElementPropertyChange<RotorsProperty>.self,
                forKey: key,
                from: container
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
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

extension AnyPropertyChangeExpr: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ElementProperty.self)
        let keys = container.allKeys
        guard keys.count == 1, let key = keys.first else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected exactly one property change expression case"
                )
            )
        }

        switch key {
        case .label, .identifier:
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "\(key.rawValue) is not an update property")
            )
        case .value:
            self = .value(try decodeUnlabeledAssociatedValue(
                ElementPropertyChangeExpr<ValueProperty>.self,
                forKey: key,
                from: container
            ))
        case .traits:
            self = .traits(try decodeUnlabeledAssociatedValue(
                ElementPropertyChangeExpr<TraitsProperty>.self,
                forKey: key,
                from: container
            ))
        case .hint:
            self = .hint(try decodeUnlabeledAssociatedValue(
                ElementPropertyChangeExpr<HintProperty>.self,
                forKey: key,
                from: container
            ))
        case .actions:
            self = .actions(try decodeUnlabeledAssociatedValue(
                ElementPropertyChangeExpr<ActionsProperty>.self,
                forKey: key,
                from: container
            ))
        case .frame:
            self = .frame(try decodeUnlabeledAssociatedValue(
                ElementPropertyChangeExpr<FrameProperty>.self,
                forKey: key,
                from: container
            ))
        case .activationPoint:
            self = .activationPoint(try decodeUnlabeledAssociatedValue(
                ElementPropertyChangeExpr<ActivationPointProperty>.self,
                forKey: key,
                from: container
            ))
        case .customContent:
            self = .customContent(try decodeUnlabeledAssociatedValue(
                ElementPropertyChangeExpr<CustomContentProperty>.self,
                forKey: key,
                from: container
            ))
        case .rotors:
            self = .rotors(try decodeUnlabeledAssociatedValue(
                ElementPropertyChangeExpr<RotorsProperty>.self,
                forKey: key,
                from: container
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
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

// MARK: - Element Update Predicate Codable

internal enum ElementUpdateCodingKeys: String, CodingKey, CaseIterable {
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

fileprivate extension AnyPropertyChange {
    static func decodeIfPresent(
        from container: KeyedDecodingContainer<ElementUpdateCodingKeys>
    ) throws -> AnyPropertyChange? {
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
        return try decode(property: property, from: container)
    }

    static func decode(
        property: ElementProperty,
        from container: KeyedDecodingContainer<ElementUpdateCodingKeys>
    ) throws -> AnyPropertyChange {
        switch property {
        case .label, .identifier:
            throw unsupportedUpdateProperty(property, in: container)
        case .value:
            return .value(try ElementPropertyChange<ValueProperty>(from: container))
        case .traits:
            return .traits(try ElementPropertyChange<TraitsProperty>(from: container))
        case .hint:
            return .hint(try ElementPropertyChange<HintProperty>(from: container))
        case .actions:
            return .actions(try ElementPropertyChange<ActionsProperty>(from: container))
        case .frame:
            return .frame(try ElementPropertyChange<FrameProperty>(from: container))
        case .activationPoint:
            return .activationPoint(try ElementPropertyChange<ActivationPointProperty>(from: container))
        case .customContent:
            return .customContent(try ElementPropertyChange<CustomContentProperty>(from: container))
        case .rotors:
            return .rotors(try ElementPropertyChange<RotorsProperty>(from: container))
        }
    }

    func encodeFields(to container: inout KeyedEncodingContainer<ElementUpdateCodingKeys>) throws {
        try container.encode(property, forKey: .property)
        switch self {
        case .value(let change):
            try change.encodeFields(to: &container)
        case .traits(let change):
            try change.encodeFields(to: &container)
        case .hint(let change):
            try change.encodeFields(to: &container)
        case .actions(let change):
            try change.encodeFields(to: &container)
        case .frame(let change):
            try change.encodeFields(to: &container)
        case .activationPoint(let change):
            try change.encodeFields(to: &container)
        case .customContent(let change):
            try change.encodeFields(to: &container)
        case .rotors(let change):
            try change.encodeFields(to: &container)
        }
    }
}

extension AnyPropertyChangeExpr {
    internal static func decodeIfPresent(
        from container: KeyedDecodingContainer<ElementUpdateCodingKeys>
    ) throws -> AnyPropertyChangeExpr? {
        let hasBefore = container.contains(.before)
        let hasAfter = container.contains(.after)
        guard let property = try container.decodeIfPresent(ElementProperty.self, forKey: .property) else {
            guard !hasBefore && !hasAfter else {
                throw DecodingError.dataCorruptedError(
                    forKey: .property,
                    in: container,
                    debugDescription: "updated predicate expression before/after require property"
                )
            }
            return nil
        }
        return try decode(property: property, from: container)
    }

    internal static func decode(
        property: ElementProperty,
        from container: KeyedDecodingContainer<ElementUpdateCodingKeys>
    ) throws -> AnyPropertyChangeExpr {
        switch property {
        case .label, .identifier:
            throw unsupportedUpdateProperty(property, in: container)
        case .value:
            return .value(try ElementPropertyChangeExpr<ValueProperty>(from: container))
        case .traits:
            return .traits(try ElementPropertyChangeExpr<TraitsProperty>(from: container))
        case .hint:
            return .hint(try ElementPropertyChangeExpr<HintProperty>(from: container))
        case .actions:
            return .actions(try ElementPropertyChangeExpr<ActionsProperty>(from: container))
        case .frame:
            return .frame(try ElementPropertyChangeExpr<FrameProperty>(from: container))
        case .activationPoint:
            return .activationPoint(try ElementPropertyChangeExpr<ActivationPointProperty>(from: container))
        case .customContent:
            return .customContent(try ElementPropertyChangeExpr<CustomContentProperty>(from: container))
        case .rotors:
            return .rotors(try ElementPropertyChangeExpr<RotorsProperty>(from: container))
        }
    }

    internal func encodeFields(to container: inout KeyedEncodingContainer<ElementUpdateCodingKeys>) throws {
        try container.encode(property, forKey: .property)
        switch self {
        case .value(let change):
            try change.encodeFields(to: &container)
        case .traits(let change):
            try change.encodeFields(to: &container)
        case .hint(let change):
            try change.encodeFields(to: &container)
        case .actions(let change):
            try change.encodeFields(to: &container)
        case .frame(let change):
            try change.encodeFields(to: &container)
        case .activationPoint(let change):
            try change.encodeFields(to: &container)
        case .customContent(let change):
            try change.encodeFields(to: &container)
        case .rotors(let change):
            try change.encodeFields(to: &container)
        }
    }
}

fileprivate extension ElementPropertyChange {
    init(from container: KeyedDecodingContainer<ElementUpdateCodingKeys>) throws {
        self.init(
            before: try container.decodeIfPresent(P.Checker.self, forKey: .before),
            after: try container.decodeIfPresent(P.Checker.self, forKey: .after)
        )
    }

    func encodeFields(to container: inout KeyedEncodingContainer<ElementUpdateCodingKeys>) throws {
        try container.encodeIfPresent(before, forKey: .before)
        try container.encodeIfPresent(after, forKey: .after)
    }
}

fileprivate extension ElementPropertyChangeExpr {
    init(from container: KeyedDecodingContainer<ElementUpdateCodingKeys>) throws {
        self.init(
            before: try container.decodeIfPresent(P.ExprChecker.self, forKey: .before),
            after: try container.decodeIfPresent(P.ExprChecker.self, forKey: .after)
        )
    }

    func encodeFields(to container: inout KeyedEncodingContainer<ElementUpdateCodingKeys>) throws {
        try container.encodeIfPresent(before, forKey: .before)
        try container.encodeIfPresent(after, forKey: .after)
    }
}
