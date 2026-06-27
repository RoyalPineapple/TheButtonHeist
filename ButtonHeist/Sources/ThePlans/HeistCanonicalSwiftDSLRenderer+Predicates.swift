import Foundation

extension HeistCanonicalSwiftDSLRenderer {
    func render(predicate: AccessibilityPredicateExpr, environment: RenderEnvironment) throws -> String {
        switch predicate {
        case .state(let state):
            return try render(state: state, environment: environment)
        case .changePredicate(let change):
            return try render(changePredicate: change, environment: environment)
        case .noChangePredicate:
            return ".noChange"
        case .predicate(let predicate):
            return try render(predicate: predicate, environment: environment)
        }
    }

    func render(predicate: AccessibilityPredicate, environment: RenderEnvironment) throws -> String {
        switch predicate {
        case .state(let state):
            return try render(state: state, environment: environment)
        case .changePredicate(let change):
            return try render(changePredicate: change, environment: environment)
        case .noChangePredicate:
            return ".noChange"
        }
    }

    func render(changePredicate change: ChangePredicateExpr, environment: RenderEnvironment) throws -> String {
        if case .elementsScope(let assertions) = change, assertions.count == 1 {
            return try render(elementDelta: assertions[0], environment: environment)
        }
        return try ".change(\(render(change: change, environment: environment)))"
    }

    func render(changePredicate change: AccessibilityPredicate.Change, environment: RenderEnvironment) throws -> String {
        if case .elementsScope(let assertions) = change, assertions.count == 1 {
            return render(elementDelta: assertions[0])
        }
        return try ".change(\(render(change: change, environment: environment)))"
    }

    func render(state: StatePredicateExpr, environment: RenderEnvironment) throws -> String {
        switch state {
        case .exists(let predicate):
            return try render(predicate: predicate, environment: environment)
        case .missing(let predicate):
            return ".missing(\(try render(predicate: predicate, environment: environment)))"
        case .existsTarget(let target):
            return ".exists(\(try render(target: target, environment: environment)))"
        case .missingTarget(let target):
            return ".missing(\(try render(target: target, environment: environment)))"
        case .all(let states):
            return ".all(\(try states.map { try render(state: $0, environment: environment) }.joined(separator: ", ")))"
        }
    }

    func render(state: AccessibilityPredicate.State, environment: RenderEnvironment) throws -> String {
        switch state {
        case .exists(let predicate):
            return render(predicate: predicate)
        case .missing(let predicate):
            return ".missing(\(render(predicate: predicate)))"
        case .existsTarget(let target):
            return ".exists(\(render(target: target)))"
        case .missingTarget(let target):
            return ".missing(\(render(target: target)))"
        case .all(let states):
            return ".all(\(try states.map { try render(state: $0, environment: environment) }.joined(separator: ", ")))"
        }
    }

    func render(change: AccessibilityPredicate.Change, environment: RenderEnvironment) throws -> String {
        switch change {
        case .any:
            return ""
        case .screenScope(let assertions):
            return try ".screen(\(assertions.map { try render(state: $0, environment: environment) }.joined(separator: ", ")))"
        case .elementsScope(let assertions):
            switch assertions.count {
            case 0:
                return ".elements()"
            case 1:
                return render(elementDelta: assertions[0])
            default:
                return ".elements(\(assertions.map { render(elementDelta: $0) }.joined(separator: ", ")))"
            }
        case .allScopes(let changes):
            return try changes.map { try render(change: $0, environment: environment) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
    }

    func render(change: ChangePredicateExpr, environment: RenderEnvironment) throws -> String {
        switch change {
        case .any:
            return ""
        case .screenScope(let assertions):
            return try ".screen(\(assertions.map { try render(state: $0, environment: environment) }.joined(separator: ", ")))"
        case .elementsScope(let assertions):
            switch assertions.count {
            case 0:
                return ".elements()"
            case 1:
                return try render(elementDelta: assertions[0], environment: environment)
            default:
                return try ".elements(\(assertions.map { try render(elementDelta: $0, environment: environment) }.joined(separator: ", ")))"
            }
        case .allScopes(let changes):
            return try changes.map { try render(change: $0, environment: environment) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
    }

    func render(elementDelta: ElementDeltaPredicate) -> String {
        switch elementDelta {
        case .appearedElement(let element):
            return ".appeared(\(render(predicate: element)))"
        case .disappearedElement(let element):
            return ".disappeared(\(render(predicate: element)))"
        case .updatedElement(let update):
            return ".updated(\(render(update: update)))"
        }
    }

    func render(elementDelta: ElementDeltaPredicateExpr, environment: RenderEnvironment) throws -> String {
        switch elementDelta {
        case .appearedElement(let element):
            return try ".appeared(\(render(predicate: element, environment: environment)))"
        case .disappearedElement(let element):
            return try ".disappeared(\(render(predicate: element, environment: environment)))"
        case .updatedElement(let update):
            return try ".updated(\(render(update: update, environment: environment)))"
        }
    }

    func render(update: ElementUpdatePredicate) -> String {
        let fields = [
            update.element.map { "element: \(render(predicate: $0))" },
            update.change.map { render(propertyChange: $0) },
        ].compactMap { $0 }
        return fields.joined(separator: ", ")
    }

    func render(update: ElementUpdatePredicateExpr, environment: RenderEnvironment) throws -> String {
        let fields = try [
            update.element.map { "element: \(try render(predicate: $0, environment: environment))" },
            update.change.map { try render(propertyChange: $0, environment: environment) },
        ].compactMap { $0 }
        return fields.joined(separator: ", ")
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
            return renderStringPropertyChange("actions", before: change.before, after: change.after)
        case .frame(let change):
            return renderStringPropertyChange("frame", before: change.before, after: change.after)
        case .activationPoint(let change):
            return renderStringPropertyChange("activationPoint", before: change.before, after: change.after)
        case .customContent(let change):
            return renderStringPropertyChange("customContent", before: change.before, after: change.after)
        case .rotors(let change):
            return renderStringPropertyChange("rotors", before: change.before, after: change.after)
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
            return try renderStringPropertyChange("actions", before: change.before, after: change.after, environment: environment)
        case .frame(let change):
            return try renderStringPropertyChange("frame", before: change.before, after: change.after, environment: environment)
        case .activationPoint(let change):
            return try renderStringPropertyChange("activationPoint", before: change.before, after: change.after, environment: environment)
        case .customContent(let change):
            return try renderStringPropertyChange("customContent", before: change.before, after: change.after, environment: environment)
        case .rotors(let change):
            return try renderStringPropertyChange("rotors", before: change.before, after: change.after, environment: environment)
        }
    }

    func renderStringPropertyChange(
        _ name: String,
        before: StringMatch<String>?,
        after: StringMatch<String>?
    ) -> String {
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
        switch (match.include.isEmpty, match.exclude.isEmpty) {
        case (false, true):
            return ".include(\(renderTraitArray(match.include)))"
        case (true, false):
            return ".exclude(\(renderTraitArray(match.exclude)))"
        default:
            return ".match(include: \(renderTraitArray(match.include)), exclude: \(renderTraitArray(match.exclude)))"
        }
    }
}
