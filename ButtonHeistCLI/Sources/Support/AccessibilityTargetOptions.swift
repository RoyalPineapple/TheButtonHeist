import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist
import ThePlans

/// Shared options for commands that target a UI element by accessibility properties.
struct AccessibilityTargetOptions: ParsableArguments {
    @Option(name: .long, help: "Accessibility identifier")
    var identifier: String?

    @Option(name: .shortAndLong, help: "Accessibility label")
    var label: String?

    @Option(name: .shortAndLong, help: "Accessibility value")
    var value: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Required traits (all must match)")
    var traits: [String] = []

    @Option(name: .customLong("exclude-traits"), parsing: .upToNextOption, help: "Excluded traits (none may be present)")
    var excludedTraits: [String] = []

    @Option(name: .long, help: "0-based index to select among multiple matches (in tree traversal order)")
    var ordinal: Int?

    func parsedPredicate() throws -> ElementPredicateTemplate? {
        let hasFields = identifier != nil || label != nil || value != nil
            || !traits.isEmpty || !excludedTraits.isEmpty
        guard hasFields else { return nil }
        var checks: [ElementPredicateCheck] = []
        if let label { checks.append(.label(label)) }
        if let identifier { checks.append(.identifier(identifier)) }
        if let value { checks.append(.value(value)) }
        let requiredTraits = Set(try parseTraits(traits, label: "trait"))
        if !requiredTraits.isEmpty { checks.append(.traits(requiredTraits)) }
        let excludedTraits = Set(try parseTraits(excludedTraits, label: "excluded trait"))
        if !excludedTraits.isEmpty { checks.append(.exclude(.traits(excludedTraits))) }
        return ElementPredicateTemplate(checks)
    }

    func requireTarget() throws -> AccessibilityTarget {
        guard let target = try parsedTarget() else {
            throw ValidationError("Must specify --identifier, -l, -v, --traits, or --exclude-traits")
        }
        return target
    }

    func parsedTarget() throws -> AccessibilityTarget? {
        let predicate = try parsedPredicate()
        guard predicate != nil || ordinal != nil else {
            return nil
        }
        guard let predicate else {
            throw ValidationError(AccessibilityTargetGrammarError.missingTarget.diagnosticDescription)
        }
        if let ordinal, ordinal < 0 {
            throw ValidationError(AccessibilityTargetGrammarError.negativeOrdinal(ordinal).diagnosticDescription)
        }
        return .predicate(predicate, ordinal: ordinal)
    }

    private func parseTraits(_ names: [String], label: String) throws -> [HeistTrait] {
        guard !names.isEmpty else { return [] }
        return try names.map { name in
            guard let trait = HeistTrait(rawValue: name) else {
                throw ValidationError("Unknown \(label) '\(name)'. Valid: \(HeistTrait.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            return trait
        }
    }

    /// Returns true when the supplied options construct a valid AccessibilityTarget.
    var hasTarget: Bool {
        get throws {
            try parsedTarget() != nil
        }
    }
}
