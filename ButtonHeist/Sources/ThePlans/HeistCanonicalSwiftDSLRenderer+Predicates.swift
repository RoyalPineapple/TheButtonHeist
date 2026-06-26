import Foundation

extension HeistCanonicalSwiftDSLRenderer {
    func render(predicate: AccessibilityPredicateExpr, environment: RenderEnvironment) throws -> String {
        switch predicate {
        case .state(let state):
            return try render(state: state, environment: environment)
        case .changePredicate(let change):
            return try ".change(\(render(change: change, environment: environment)))"
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
            return try ".change(\(render(change: change, environment: environment)))"
        case .noChangePredicate:
            return ".noChange"
        }
    }

    func render(state: StatePredicateExpr, environment: RenderEnvironment) throws -> String {
        switch state {
        case .exists(let predicate):
            return ".exists(\(try render(predicate: predicate, environment: environment)))"
        case .missing(let predicate):
            return ".missing(\(try render(predicate: predicate, environment: environment)))"
        case .existsTarget(let target):
            return ".exists(\(try render(target: target, environment: environment)))"
        case .missingTarget(let target):
            return ".missing(\(try render(target: target, environment: environment)))"
        case .all(let states):
            return ".all([\(try states.map { try render(state: $0, environment: environment) }.joined(separator: ", "))])"
        }
    }

    func render(state: AccessibilityPredicate.State, environment: RenderEnvironment) throws -> String {
        switch state {
        case .exists(let predicate):
            return ".exists(\(render(predicate: predicate)))"
        case .missing(let predicate):
            return ".missing(\(render(predicate: predicate)))"
        case .existsTarget(let target):
            return ".exists(\(render(target: target)))"
        case .missingTarget(let target):
            return ".missing(\(render(target: target)))"
        case .all(let states):
            return ".all([\(try states.map { try render(state: $0, environment: environment) }.joined(separator: ", "))])"
        }
    }

    func render(change: AccessibilityPredicate.Change, environment: RenderEnvironment) throws -> String {
        switch change {
        case .any:
            return ""
        case .screenScope(let assertions):
            return try ".screen(\(assertions.map { try render(state: $0, environment: environment) }.joined(separator: ", ")))"
        case .elementsScope(let assertions):
            return ".elements(\(assertions.map { render(elementDelta: $0) }.joined(separator: ", ")))"
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
            return try ".elements(\(assertions.map { try render(elementDelta: $0, environment: environment) }.joined(separator: ", ")))"
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
            update.before.map { "before: \(render(predicate: $0))" },
            update.after.map { "after: \(render(predicate: $0))" },
            update.property.map { "property: .\($0.rawValue)" },
        ].compactMap { $0 }
        return fields.joined(separator: ", ")
    }

    func render(update: ElementUpdatePredicateExpr, environment: RenderEnvironment) throws -> String {
        let fields = try [
            update.before.map { "before: \(try render(predicate: $0, environment: environment))" },
            update.after.map { "after: \(try render(predicate: $0, environment: environment))" },
            update.property.map { "property: .\($0.rawValue)" },
        ].compactMap { $0 }
        return fields.joined(separator: ", ")
    }
}
