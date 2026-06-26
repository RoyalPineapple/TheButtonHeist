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
                throw HeistCanonicalSwiftDSLError.unresolvedTargetReference(reference.rawValue)
            }
            return reference.rawValue
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
        if let shorthand = renderSingleCheckTarget(predicate.checks) { return shorthand }
        return ".element(\(renderElementPredicateChecks(predicate)))"
    }

    func render(predicate: ElementPredicate) -> String {
        if let shorthand = renderSingleCheckTarget(predicate.checks) { return shorthand }
        return ".element(\(renderElementPredicateChecks(predicate)))"
    }

    func render(predicate: ElementPredicateTemplate, environment: RenderEnvironment) throws -> String {
        if let shorthand = try renderSingleCheckTarget(predicate.checks, environment: environment) { return shorthand }
        return ".element(\(try renderElementPredicateTemplateChecks(predicate, environment: environment)))"
    }

    func renderSingleCheckTarget(_ checks: [ElementPredicateCheck<String>]) -> String? {
        guard checks.count == 1 else { return nil }
        switch checks[0] {
        case .label(let match):
            return ".label(\(renderCallArgument(match)))"
        case .identifier(let match):
            return ".identifier(\(renderCallArgument(match)))"
        case .value(let match):
            return ".value(\(renderCallArgument(match)))"
        case .traits, .excludeTraits:
            return nil
        }
    }

    func renderSingleCheckTarget(
        _ checks: [ElementPredicateCheck<StringExpr>],
        environment: RenderEnvironment
    ) throws -> String? {
        guard checks.count == 1 else { return nil }
        switch checks[0] {
        case .label(let match):
            return ".label(\(try renderCallArgument(match, environment: environment)))"
        case .identifier(let match):
            return ".identifier(\(try renderCallArgument(match, environment: environment)))"
        case .value(let match):
            return ".value(\(try renderCallArgument(match, environment: environment)))"
        case .traits, .excludeTraits:
            return nil
        }
    }

    func renderElementPredicateChecks(_ predicate: ElementPredicate) -> String {
        predicate.checks.map(renderPredicateCheck).joined(separator: ", ")
    }

    func renderElementPredicateTemplateChecks(
        _ predicate: ElementPredicateTemplate,
        environment: RenderEnvironment
    ) throws -> String {
        try predicate.checks.map {
            try renderPredicateCheck($0, environment: environment)
        }.joined(separator: ", ")
    }

    func renderPredicateCheck(_ check: ElementPredicateCheck<String>) -> String {
        switch check {
        case .label(let match):
            return ".label(\(renderCallArgument(match)))"
        case .identifier(let match):
            return ".identifier(\(renderCallArgument(match)))"
        case .value(let match):
            return ".value(\(renderCallArgument(match)))"
        case .traits(let traits):
            return ".traits(\(renderTraitArray(traits)))"
        case .excludeTraits(let traits):
            return ".excludeTraits(\(renderTraitArray(traits)))"
        }
    }

    func renderPredicateCheck(
        _ check: ElementPredicateCheck<StringExpr>,
        environment: RenderEnvironment
    ) throws -> String {
        switch check {
        case .label(let match):
            return ".label(\(try renderCallArgument(match, environment: environment)))"
        case .identifier(let match):
            return ".identifier(\(try renderCallArgument(match, environment: environment)))"
        case .value(let match):
            return ".value(\(try renderCallArgument(match, environment: environment)))"
        case .traits(let traits):
            return ".traits(\(renderTraitArray(traits)))"
        case .excludeTraits(let traits):
            return ".excludeTraits(\(renderTraitArray(traits)))"
        }
    }

    func renderTraitArray(_ traits: [HeistTrait]) -> String {
        "[\(traits.map { ".\($0.rawValue)" }.joined(separator: ", "))]"
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
                throw HeistCanonicalSwiftDSLError.unresolvedStringReference(reference.rawValue)
            }
            return reference.rawValue
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
