// MARK: - Element Property Match Descriptions

extension TraitSetMatch: CustomStringConvertible {
    public var description: String {
        let includedTraits = include.canonicalHeistTraitArray
            .map { ".\($0.rawValue)" }
            .joined(separator: ", ")
        let excludedTraits = exclude.canonicalHeistTraitArray
            .map { ".\($0.rawValue)" }
            .joined(separator: ", ")
        return ScoreDescription.call("traits", [
            include.isEmpty ? nil : "include=[\(includedTraits)]",
            exclude.isEmpty ? nil : "exclude=[\(excludedTraits)]",
        ].compactMap { $0 })
    }
}

extension ActionSetMatch: CustomStringConvertible {
    public var description: String {
        let includedActions = include.canonicalElementActionArray
            .map(\.description)
            .joined(separator: ", ")
        let excludedActions = exclude.canonicalElementActionArray
            .map(\.description)
            .joined(separator: ", ")
        return ScoreDescription.call("actions", [
            include.isEmpty ? nil : "include=[\(includedActions)]",
            exclude.isEmpty ? nil : "exclude=[\(excludedActions)]",
        ].compactMap { $0 })
    }
}

extension ElementFrameMatch: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("frame", [
            x.map { "x=\($0)" },
            y.map { "y=\($0)" },
            width.map { "width=\($0)" },
            height.map { "height=\($0)" },
        ].compactMap { $0 })
    }
}

extension ElementPointMatch: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("activationPoint", [
            x.map { "x=\($0)" },
            y.map { "y=\($0)" },
        ].compactMap { $0 })
    }
}

extension CustomContentMatch: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("customContent", [
            label.map { "label=\($0)" },
            value.map { "value=\($0)" },
            isImportant.map { "isImportant=\($0)" },
        ].compactMap { $0 })
    }
}

extension RotorSetMatch: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("rotors", [
            include.isEmpty ? nil : "include=[\(include.map(\.description).joined(separator: ", "))]",
            exclude.isEmpty ? nil : "exclude=[\(exclude.map(\.description).joined(separator: ", "))]",
        ].compactMap { $0 })
    }
}

extension AnyPropertyChange: CustomStringConvertible {
    public var description: String {
        switch self {
        case .value(let change): return change.description(name: "value")
        case .traits(let change): return change.description(name: "traits")
        case .hint(let change): return change.description(name: "hint")
        case .actions(let change): return change.description(name: "actions")
        case .frame(let change): return change.description(name: "frame")
        case .activationPoint(let change): return change.description(name: "activationPoint")
        case .customContent(let change): return change.description(name: "customContent")
        case .rotors(let change): return change.description(name: "rotors")
        }
    }
}

extension AnyPropertyChangeExpr: CustomStringConvertible {
    public var description: String {
        switch self {
        case .value(let change): return change.description(name: "value")
        case .traits(let change): return change.description(name: "traits")
        case .hint(let change): return change.description(name: "hint")
        case .actions(let change): return change.description(name: "actions")
        case .frame(let change): return change.description(name: "frame")
        case .activationPoint(let change): return change.description(name: "activationPoint")
        case .customContent(let change): return change.description(name: "customContent")
        case .rotors(let change): return change.description(name: "rotors")
        }
    }
}

fileprivate extension ElementPropertyChange {
    func description(name: String) -> String {
        ScoreDescription.call(name, [
            before.map { "before=\($0)" },
            after.map { "after=\($0)" },
        ].compactMap { $0 })
    }
}

fileprivate extension ElementPropertyChangeExpr {
    func description(name: String) -> String {
        ScoreDescription.call(name, [
            before.map { "before=\($0)" },
            after.map { "after=\($0)" },
        ].compactMap { $0 })
    }
}
