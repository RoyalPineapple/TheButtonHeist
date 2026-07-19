extension TraitSetMatch: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("traitSet", [
            CanonicalValueDescription.listField("include", include.isEmpty ? nil : include.canonicalHeistTraitArray),
            CanonicalValueDescription.listField("exclude", exclude.isEmpty ? nil : exclude.canonicalHeistTraitArray),
        ].compactMap { $0 })
    }
}

extension ActionSetMatch: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("actionSet", [
            CanonicalValueDescription.listField("include", include.isEmpty ? nil : include.canonicalElementActionArray),
            CanonicalValueDescription.listField("exclude", exclude.isEmpty ? nil : exclude.canonicalElementActionArray),
        ].compactMap { $0 })
    }
}

extension ElementFrameMatch: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("frame", [
            CanonicalValueDescription.valueField("x", x), CanonicalValueDescription.valueField("y", y),
            CanonicalValueDescription.valueField("width", width), CanonicalValueDescription.valueField("height", height),
        ].compactMap { $0 })
    }
}

extension ElementPointMatch: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("point", [
            CanonicalValueDescription.valueField("x", x), CanonicalValueDescription.valueField("y", y),
        ].compactMap { $0 })
    }
}

extension CustomContentMatchCore: CustomStringConvertible {
    package var description: String {
        CanonicalValueDescription.call("customContent", [
            label.map { "label=\($0)" },
            value.map { "value=\($0)" },
            CanonicalValueDescription.valueField("isImportant", isImportant),
        ].compactMap { $0 })
    }
}

extension CustomContentMatch: CustomStringConvertible {
    public var description: String { core.description }
}

extension RotorSetMatchCore: CustomStringConvertible {
    package var description: String {
        CanonicalValueDescription.call("rotorSet", [
            include.isEmpty ? nil : "include=[\(include.map(\.description).joined(separator: ", "))]",
            exclude.isEmpty ? nil : "exclude=[\(exclude.map(\.description).joined(separator: ", "))]",
        ].compactMap { $0 })
    }
}

extension RotorSetMatch: CustomStringConvertible {
    public var description: String { core.description }
}

extension ElementPropertyChange: CustomStringConvertible {
    public var description: String { core.description }
}

extension ResolvedElementPropertyChange: CustomStringConvertible {
    public var description: String { core.description }
}

extension ElementPropertyChangeCore: CustomStringConvertible {
    package var description: String {
        switch self {
        case .value(let change): return change.description(property: .value)
        case .traits(let change): return change.description(property: .traits)
        case .hint(let change): return change.description(property: .hint)
        case .actions(let change): return change.description(property: .actions)
        case .frame(let change): return change.description(property: .frame)
        case .activationPoint(let change): return change.description(property: .activationPoint)
        case .customContent(let change): return change.description(property: .customContent)
        case .rotors(let change): return change.description(property: .rotors)
        }
    }
}

private extension PropertyChangeCore {
    func description(property: ElementProperty) -> String {
        CanonicalValueDescription.call("change", [
            "property=.\(property.rawValue)",
            before.map { "before=\($0)" },
            after.map { "after=\($0)" },
        ].compactMap { $0 })
    }
}
