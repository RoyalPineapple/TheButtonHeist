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
        if predicate.traits.isEmpty, predicate.excludeTraits.isEmpty {
            if predicate.labelMatches.count == 1,
               predicate.identifierMatches.isEmpty,
               predicate.valueMatches.isEmpty {
                return ".label(\(renderCallArgument(predicate.labelMatches[0])))"
            }
            if predicate.labelMatches.isEmpty,
               predicate.identifierMatches.count == 1,
               predicate.valueMatches.isEmpty {
                return ".identifier(\(renderCallArgument(predicate.identifierMatches[0])))"
            }
            if predicate.labelMatches.isEmpty,
               predicate.identifierMatches.isEmpty,
               predicate.valueMatches.count == 1 {
                return ".value(\(renderCallArgument(predicate.valueMatches[0])))"
            }
        }
        if usesRepeatedStringMatches(predicate) {
            return ".element(\(renderElementPredicateChecks(predicate)))"
        }
        return ".element(\(renderElementPredicateFields(predicate)))"
    }

    func render(predicate: ElementPredicate) -> String {
        if predicate.traits.isEmpty, predicate.excludeTraits.isEmpty {
            if predicate.labelMatches.count == 1,
               predicate.identifierMatches.isEmpty,
               predicate.valueMatches.isEmpty {
                return ".label(\(renderCallArgument(predicate.labelMatches[0])))"
            }
            if predicate.labelMatches.isEmpty,
               predicate.identifierMatches.count == 1,
               predicate.valueMatches.isEmpty {
                return ".identifier(\(renderCallArgument(predicate.identifierMatches[0])))"
            }
            if predicate.labelMatches.isEmpty,
               predicate.identifierMatches.isEmpty,
               predicate.valueMatches.count == 1 {
                return ".value(\(renderCallArgument(predicate.valueMatches[0])))"
            }
        }
        if usesRepeatedStringMatches(predicate) {
            return ".element(\(renderElementPredicateChecks(predicate)))"
        }
        return ".element(\(renderElementPredicateFields(predicate)))"
    }

    func render(predicate: ElementPredicateTemplate, environment: RenderEnvironment) throws -> String {
        if predicate.traits.isEmpty, predicate.excludeTraits.isEmpty {
            if predicate.labelMatches.count == 1,
               predicate.identifierMatches.isEmpty,
               predicate.valueMatches.isEmpty {
                return ".label(\(try renderCallArgument(predicate.labelMatches[0], environment: environment)))"
            }
            if predicate.labelMatches.isEmpty,
               predicate.identifierMatches.count == 1,
               predicate.valueMatches.isEmpty {
                return ".identifier(\(try renderCallArgument(predicate.identifierMatches[0], environment: environment)))"
            }
            if predicate.labelMatches.isEmpty,
               predicate.identifierMatches.isEmpty,
               predicate.valueMatches.count == 1 {
                return ".value(\(try renderCallArgument(predicate.valueMatches[0], environment: environment)))"
            }
        }
        if usesRepeatedStringMatches(predicate) {
            return ".element(\(try renderElementPredicateTemplateChecks(predicate, environment: environment)))"
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

    func renderElementPredicateChecks(_ predicate: ElementPredicate) -> String {
        var fields = predicate.labelMatches.map { ".label(\(renderCallArgument($0)))" }
        fields += predicate.identifierMatches.map { ".identifier(\(renderCallArgument($0)))" }
        fields += predicate.valueMatches.map { ".value(\(renderCallArgument($0)))" }
        fields += [
            renderTraits("traits", predicate.traits),
            renderTraits("excludeTraits", predicate.excludeTraits),
        ].compactMap { $0 }
        return fields.joined(separator: ", ")
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

    func renderElementPredicateTemplateChecks(
        _ predicate: ElementPredicateTemplate,
        environment: RenderEnvironment
    ) throws -> String {
        var fields = try predicate.labelMatches.map {
            ".label(\(try renderCallArgument($0, environment: environment)))"
        }
        fields += try predicate.identifierMatches.map {
            ".identifier(\(try renderCallArgument($0, environment: environment)))"
        }
        fields += try predicate.valueMatches.map {
            ".value(\(try renderCallArgument($0, environment: environment)))"
        }
        fields += [
            renderTraits("traits", predicate.traits),
            renderTraits("excludeTraits", predicate.excludeTraits),
        ].compactMap { $0 }
        return fields.joined(separator: ", ")
    }

    func usesRepeatedStringMatches(_ predicate: ElementPredicate) -> Bool {
        predicate.labelMatches.count > 1 ||
            predicate.identifierMatches.count > 1 ||
            predicate.valueMatches.count > 1
    }

    func usesRepeatedStringMatches(_ predicate: ElementPredicateTemplate) -> Bool {
        predicate.labelMatches.count > 1 ||
            predicate.identifierMatches.count > 1 ||
            predicate.valueMatches.count > 1
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
