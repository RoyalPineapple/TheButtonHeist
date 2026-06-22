import Foundation

extension HeistCanonicalSwiftDSLRenderer {
    func render(predicate: AccessibilityPredicateExpr, environment: RenderEnvironment) throws -> String {
        switch predicate {
        case .state(let state):
            return try render(state: state, environment: environment)
        case .changed(let change):
            return try ".changed(\(render(change: change, environment: environment)))"
        case .predicate(let predicate):
            return try render(predicate: predicate, environment: environment)
        }
    }

    func render(predicate: AccessibilityPredicate, environment: RenderEnvironment) throws -> String {
        switch predicate {
        case .state(let state):
            return try render(state: state, environment: environment)
        case .changed(let change):
            return try ".changed(\(render(change: change, environment: environment)))"
        }
    }

    func render(state: StatePredicateExpr, environment: RenderEnvironment) throws -> String {
        switch state {
        case .present(let predicate):
            return ".present(\(try render(predicate: predicate, environment: environment)))"
        case .absent(let predicate):
            return ".absent(\(try render(predicate: predicate, environment: environment)))"
        case .presentTarget(let target):
            return ".present(\(try render(target: target, environment: environment)))"
        case .absentTarget(let target):
            return ".absent(\(try render(target: target, environment: environment)))"
        case .all(let states):
            return ".all([\(try states.map { try render(state: $0, environment: environment) }.joined(separator: ", "))])"
        }
    }

    func render(state: AccessibilityPredicate.State, environment: RenderEnvironment) throws -> String {
        switch state {
        case .present(let predicate):
            return ".present(\(render(predicate: predicate)))"
        case .absent(let predicate):
            return ".absent(\(render(predicate: predicate)))"
        case .presentTarget(let target):
            return ".present(\(render(target: target)))"
        case .absentTarget(let target):
            return ".absent(\(render(target: target)))"
        case .all(let states):
            return ".all([\(try states.map { try render(state: $0, environment: environment) }.joined(separator: ", "))])"
        }
    }

    func render(change: AccessibilityPredicate.Change, environment: RenderEnvironment) throws -> String {
        switch change {
        case .screen(let state):
            if let state {
                return try ".screen(where: \(render(state: state, environment: environment)))"
            }
            return ".screen()"
        case .elements:
            return ".elements"
        case .updated(let update):
            return ".updated(\(render(update: update)))"
        }
    }

    func render(change: ChangePredicateExpr, environment: RenderEnvironment) throws -> String {
        switch change {
        case .screen(let state):
            if let state {
                return try ".screen(where: \(render(state: state, environment: environment)))"
            }
            return ".screen()"
        case .elements:
            return ".elements"
        case .updated(let update):
            return try ".updated(\(render(update: update, environment: environment)))"
        }
    }

    func render(update: ElementUpdatePredicate) -> String {
        let fields = [
            update.element.map { render(predicate: $0) },
            update.property.map { "property: .\($0.rawValue)" },
            update.from.map { "from: \(quote($0))" },
            update.to.map { "to: \(quote($0))" },
        ].compactMap { $0 }
        return fields.joined(separator: ", ")
    }

    func render(update: ElementUpdatePredicateExpr, environment: RenderEnvironment) throws -> String {
        let fields = try [
            update.element.map { try render(predicate: $0, environment: environment) },
            update.property.map { "property: .\($0.rawValue)" },
            update.from.map { "from: \(try render(string: $0, environment: environment))" },
            update.to.map { "to: \(try render(string: $0, environment: environment))" },
        ].compactMap { $0 }
        return fields.joined(separator: ", ")
    }
}
