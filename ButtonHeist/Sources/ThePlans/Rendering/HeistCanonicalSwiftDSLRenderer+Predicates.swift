import Foundation

extension HeistCanonicalSwiftDSLRenderer {
    func render<Context>(
        predicate: AccessibilityPredicate<Context>,
        environment: RenderEnvironment
    ) throws -> String {
        try render(predicateNode: predicate.node, environment: environment)
    }

    private func render(
        predicateNode node: AccessibilityPredicateNode,
        environment: RenderEnvironment
    ) throws -> String {
        switch node {
        case .exists(let target):
            return ".exists(\(try render(target: target, environment: environment)))"
        case .missing(let target):
            return ".missing(\(try render(target: target, environment: environment)))"
        case .announcement(let announcement):
            guard let match = announcement.match else { return ".announcement" }
            return ".announcement(\(renderCallArgument(match)))"
        case .changed(let delta):
            return ".changed(\(try render(predicateNode: delta, environment: environment)))"
        case .noChange:
            return ".noChange"
        case .screen(let assertions):
            guard !assertions.isEmpty else { return ".screen()" }
            let rendered = try assertions.map {
                try render(predicateNode: $0, environment: environment)
            }
            return ".screen([\(rendered.joined(separator: ", "))])"
        case .elements(let assertions):
            guard !assertions.isEmpty else { return ".elements()" }
            let rendered = try assertions.map {
                try render(predicateNode: $0, environment: environment)
            }
            return ".elements([\(rendered.joined(separator: ", "))])"
        case .appeared(let target):
            return ".appeared(\(try render(target: target, environment: environment)))"
        case .disappeared(let target):
            return ".disappeared(\(try render(target: target, environment: environment)))"
        case .updated(let target, let change):
            return try ".updated(\(render(target: target, environment: environment)), \(render(propertyChange: change, environment: environment)))"
        }
    }
    func render(propertyChange change: AnyPropertyChange) -> String {
        switch change {
        case .value(let change):
            return renderStringPropertyChange("value", before: change.before, after: change.after)
        case .traits(let change):
            return renderTraitsPropertyChange(before: change.before, after: change.after)
        case .hint(let change):
            return renderStringPropertyChange("hint", before: change.before, after: change.after)
        case .actions(let change):
            return renderPropertyChange("actions", before: change.before, after: change.after, render: render(actionSet:))
        case .frame(let change):
            return renderPropertyChange("frame", before: change.before, after: change.after, render: render(frame:))
        case .activationPoint(let change):
            return renderPropertyChange("activationPoint", before: change.before, after: change.after, render: render(point:))
        case .customContent(let change):
            return renderPropertyChange("customContent", before: change.before, after: change.after, render: render(customContent:))
        case .rotors(let change):
            return renderPropertyChange("rotors", before: change.before, after: change.after, render: render(rotorSet:))
        }
    }

    func render(propertyChange change: AnyPropertyChangeExpr, environment: RenderEnvironment) throws -> String {
        switch change {
        case .value(let change):
            return try renderStringPropertyChange("value", before: change.before, after: change.after, environment: environment)
        case .traits(let change):
            return renderTraitsPropertyChange(before: change.before, after: change.after)
        case .hint(let change):
            return try renderStringPropertyChange("hint", before: change.before, after: change.after, environment: environment)
        case .actions(let change):
            return renderPropertyChange("actions", before: change.before, after: change.after, render: render(actionSet:))
        case .frame(let change):
            return renderPropertyChange("frame", before: change.before, after: change.after, render: render(frame:))
        case .activationPoint(let change):
            return renderPropertyChange("activationPoint", before: change.before, after: change.after, render: render(point:))
        case .customContent(let change):
            return try renderPropertyChange("customContent", before: change.before, after: change.after) {
                try render(customContent: $0, environment: environment)
            }
        case .rotors(let change):
            return try renderPropertyChange("rotors", before: change.before, after: change.after) {
                try render(rotorSet: $0, environment: environment)
            }
        }
    }

    func renderPropertyChange<Checker>(
        _ name: String,
        before: Checker?,
        after: Checker?,
        render: (Checker) throws -> String
    ) rethrows -> String {
        let fields = try [
            before.map { "before: \(try render($0))" },
            after.map { "after: \(try render($0))" },
        ].compactMap { $0 }
        return ".\(name)(\(fields.joined(separator: ", ")))"
    }

    func renderStringPropertyChange(
        _ name: String,
        before: StringMatch<String>?,
        after: StringMatch<String>?
    ) -> String {
        if name == "value", before == nil, let after {
            return ".value(\(renderCallArgument(after)))"
        }
        let fields = [
            before.map { "before: \(renderFieldArgument($0))" },
            after.map { "after: \(renderFieldArgument($0))" },
        ].compactMap { $0 }
        return ".\(name)(\(fields.joined(separator: ", ")))"
    }

    func renderStringPropertyChange(
        _ name: String,
        before: StringMatch<StringExpr>?,
        after: StringMatch<StringExpr>?,
        environment: RenderEnvironment
    ) throws -> String {
        if name == "value", before == nil, let after {
            return try ".value(\(renderCallArgument(after, environment: environment)))"
        }
        let fields = try [
            before.map { "before: \(try renderFieldArgument($0, environment: environment))" },
            after.map { "after: \(try renderFieldArgument($0, environment: environment))" },
        ].compactMap { $0 }
        return ".\(name)(\(fields.joined(separator: ", ")))"
    }

    func renderTraitsPropertyChange(before: TraitSetMatch?, after: TraitSetMatch?) -> String {
        let fields = [
            before.map { "before: \(render(traitSet: $0))" },
            after.map { "after: \(render(traitSet: $0))" },
        ].compactMap { $0 }
        return ".traits(\(fields.joined(separator: ", ")))"
    }

    func render(traitSet match: TraitSetMatch) -> String {
        let fields = renderIncludeExcludeFields(
            include: match.include.isEmpty ? nil : renderTraitArray(match.include),
            exclude: match.exclude.isEmpty ? nil : renderTraitArray(match.exclude)
        )
        return ".init(\(fields))"
    }

    func render(actionSet match: ActionSetMatch) -> String {
        let fields = renderIncludeExcludeFields(
            include: match.include.isEmpty ? nil : renderActionArray(match.include),
            exclude: match.exclude.isEmpty ? nil : renderActionArray(match.exclude)
        )
        return ".init(\(fields))"
    }

    func render(frame match: ElementFrameMatch) -> String {
        let fields = renderIntegerFields([
            ("x", match.x),
            ("y", match.y),
            ("width", match.width),
            ("height", match.height),
        ])
        return ".init(\(fields))"
    }

    func render(point match: ElementPointMatch) -> String {
        let fields = renderIntegerFields([
            ("x", match.x),
            ("y", match.y),
        ])
        return ".init(\(fields))"
    }

    func render(customContent match: CustomContentMatch<String>) -> String {
        let fields = renderCustomContentFields(
            label: match.label.map(renderFieldArgument),
            value: match.value.map(renderFieldArgument),
            isImportant: match.isImportant
        )
        return ".init(\(fields))"
    }

    func render(customContent match: CustomContentMatch<StringExpr>, environment: RenderEnvironment) throws -> String {
        let fields = try renderCustomContentFields(
            label: match.label.map { try renderFieldArgument($0, environment: environment) },
            value: match.value.map { try renderFieldArgument($0, environment: environment) },
            isImportant: match.isImportant
        )
        return ".init(\(fields))"
    }

    func render(rotorSet match: RotorSetMatch<String>) -> String {
        let fields = renderIncludeExcludeFields(
            include: match.include.isEmpty ? nil : renderStringMatchArray(match.include),
            exclude: match.exclude.isEmpty ? nil : renderStringMatchArray(match.exclude)
        )
        return ".init(\(fields))"
    }

    func render(rotorSet match: RotorSetMatch<StringExpr>, environment: RenderEnvironment) throws -> String {
        let include = match.include.isEmpty ? nil : try renderStringMatchArray(match.include, environment: environment)
        let exclude = match.exclude.isEmpty ? nil : try renderStringMatchArray(match.exclude, environment: environment)
        return ".init(\(renderIncludeExcludeFields(include: include, exclude: exclude)))"
    }

    private func renderIntegerFields(_ fields: [(String, Int?)]) -> String {
        fields.compactMap { name, value in
            value.map { "\(name): \($0)" }
        }.joined(separator: ", ")
    }

    private func renderIncludeExcludeFields(include: String?, exclude: String?) -> String {
        [
            include.map { "include: \($0)" },
            exclude.map { "exclude: \($0)" },
        ].compactMap { $0 }.joined(separator: ", ")
    }

    private func renderCustomContentFields(
        label: String?,
        value: String?,
        isImportant: Bool?
    ) -> String {
        [
            label.map { "label: \($0)" },
            value.map { "value: \($0)" },
            isImportant.map { "isImportant: \($0)" },
        ].compactMap { $0 }.joined(separator: ", ")
    }

    func renderActionArray(_ actions: Set<ElementAction>) -> String {
        "[\(actions.sorted { $0.canonicalSortKey < $1.canonicalSortKey }.map(render(action:)).joined(separator: ", "))]"
    }

    func render(action: ElementAction) -> String {
        switch action {
        case .activate:
            return ".activate"
        case .typeText:
            return ".typeText"
        case .increment:
            return ".increment"
        case .decrement:
            return ".decrement"
        case .custom(let name):
            return ".custom(\(quote(name)))"
        }
    }

    func renderStringMatchArray(_ matches: [StringMatch<String>]) -> String {
        "[\(matches.map(renderFieldArgument).joined(separator: ", "))]"
    }

    func renderStringMatchArray(
        _ matches: [StringMatch<StringExpr>],
        environment: RenderEnvironment
    ) throws -> String {
        let rendered = try matches.map { try renderFieldArgument($0, environment: environment) }
        return "[\(rendered.joined(separator: ", "))]"
    }
}
