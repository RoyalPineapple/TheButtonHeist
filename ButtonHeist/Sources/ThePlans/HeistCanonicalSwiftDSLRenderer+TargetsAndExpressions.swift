import Foundation

extension HeistCanonicalSwiftDSLRenderer {
    func render(target: ElementTargetExpr, environment: RenderEnvironment) throws -> String {
        switch target {
        case .target(let target):
            return render(target: target)
        case .predicate(let predicate, let ordinal):
            let renderedPredicate = try render(predicate: predicate, environment: environment)
            guard let ordinal else { return renderedPredicate }
            return ".target(\(renderedPredicate), ordinal: \(ordinal))"
        case .ref(let reference):
            guard environment.targetReferences.contains(reference) else {
                throw HeistCanonicalSwiftDSLError.unresolvedTargetReference(reference)
            }
            return reference
        }
    }

    func render(target: ElementTarget) -> String {
        switch target {
        case .predicate(let predicate, let ordinal):
            guard let ordinal else { return renderTargetPredicate(predicate) }
            return ".target(\(render(predicate: predicate)), ordinal: \(ordinal))"
        }
    }

    func renderTargetPredicate(_ predicate: ElementPredicate) -> String {
        if predicate.traits.isEmpty, predicate.excludeTraits.isEmpty {
            switch (predicate.label, predicate.identifier, predicate.value) {
            case (.some(let label), nil, nil):
                return ".label(\(renderCallArgument(label)))"
            case (nil, .some(let identifier), nil):
                return ".identifier(\(renderCallArgument(identifier)))"
            case (nil, nil, .some(let value)):
                return ".value(\(renderCallArgument(value)))"
            default:
                break
            }
        }
        return ".element(\(renderElementPredicateFields(predicate)))"
    }

    func render(predicate: ElementPredicate) -> String {
        if predicate.traits.isEmpty, predicate.excludeTraits.isEmpty {
            switch (predicate.label, predicate.identifier, predicate.value) {
            case (.some(let label), nil, nil):
                return ".label(\(renderCallArgument(label)))"
            case (nil, .some(let identifier), nil):
                return ".identifier(\(renderCallArgument(identifier)))"
            case (nil, nil, .some(let value)):
                return ".value(\(renderCallArgument(value)))"
            default:
                break
            }
        }
        return ".element(\(renderElementPredicateFields(predicate)))"
    }

    func render(predicate: ElementPredicateTemplate, environment: RenderEnvironment) throws -> String {
        if predicate.traits.isEmpty, predicate.excludeTraits.isEmpty {
            switch (predicate.label, predicate.identifier, predicate.value) {
            case (.some(let label), nil, nil):
                return ".label(\(try renderCallArgument(label, environment: environment)))"
            case (nil, .some(let identifier), nil):
                return ".identifier(\(try renderCallArgument(identifier, environment: environment)))"
            case (nil, nil, .some(let value)):
                return ".value(\(try renderCallArgument(value, environment: environment)))"
            default:
                break
            }
        }
        return ".element(\(try renderElementPredicateTemplateFields(predicate, environment: environment)))"
    }

    func renderElementPredicateFields(_ predicate: ElementPredicate) -> String {
        [
            predicate.label.map { "label: \(renderFieldArgument($0))" },
            predicate.identifier.map { "identifier: \(renderFieldArgument($0))" },
            predicate.value.map { "value: \(renderFieldArgument($0))" },
            renderTraits("traits", predicate.traits),
            renderTraits("excludeTraits", predicate.excludeTraits),
        ].compactMap { $0 }.joined(separator: ", ")
    }

    func renderElementPredicateTemplateFields(
        _ predicate: ElementPredicateTemplate,
        environment: RenderEnvironment
    ) throws -> String {
        try [
            predicate.label.map { "label: \(try renderFieldArgument($0, environment: environment))" },
            predicate.identifier.map { "identifier: \(try renderFieldArgument($0, environment: environment))" },
            predicate.value.map { "value: \(try renderFieldArgument($0, environment: environment))" },
            renderTraits("traits", predicate.traits),
            renderTraits("excludeTraits", predicate.excludeTraits),
        ].compactMap { $0 }.joined(separator: ", ")
    }

    func renderCallArgument(_ match: StringMatch<String>) -> String {
        switch match {
        case .exact(let value):
            return quote(value)
        case .contains(let value):
            return ".contains(\(quote(value)))"
        case .prefix(let value):
            return ".prefix(\(quote(value)))"
        case .suffix(let value):
            return ".suffix(\(quote(value)))"
        }
    }

    func renderFieldArgument(_ match: StringMatch<String>) -> String {
        switch match {
        case .exact(let value):
            return quote(value)
        case .contains(let value):
            return ".contains(\(quote(value)))"
        case .prefix(let value):
            return ".prefix(\(quote(value)))"
        case .suffix(let value):
            return ".suffix(\(quote(value)))"
        }
    }

    func renderCallArgument(
        _ match: StringMatch<StringExpr>,
        environment: RenderEnvironment
    ) throws -> String {
        switch match {
        case .exact(let value):
            return try render(string: value, environment: environment)
        case .contains(let value):
            return ".contains(\(try render(string: value, environment: environment)))"
        case .prefix(let value):
            return ".prefix(\(try render(string: value, environment: environment)))"
        case .suffix(let value):
            return ".suffix(\(try render(string: value, environment: environment)))"
        }
    }

    func renderFieldArgument(
        _ match: StringMatch<StringExpr>,
        environment: RenderEnvironment
    ) throws -> String {
        switch match {
        case .exact(let value):
            return try render(string: value, environment: environment)
        case .contains(let value):
            return ".contains(\(try render(string: value, environment: environment)))"
        case .prefix(let value):
            return ".prefix(\(try render(string: value, environment: environment)))"
        case .suffix(let value):
            return ".suffix(\(try render(string: value, environment: environment)))"
        }
    }

    func render(string: StringExpr, environment: RenderEnvironment) throws -> String {
        switch string {
        case .literal(let literal):
            return quote(literal)
        case .ref(let reference):
            guard environment.stringReferences.contains(reference) else {
                throw HeistCanonicalSwiftDSLError.unresolvedStringReference(reference)
            }
            return reference
        }
    }

    func render(point: ScreenPoint) -> String {
        "ScreenPoint(x: \(decimal(point.x)), y: \(decimal(point.y)))"
    }

    func render(unitPoint: UnitPoint) -> String {
        "UnitPoint(x: \(decimal(unitPoint.x)), y: \(decimal(unitPoint.y)))"
    }

    func render(duration: GestureDuration) -> String {
        "GestureDuration(seconds: \(decimal(duration.seconds)))"
    }
}
