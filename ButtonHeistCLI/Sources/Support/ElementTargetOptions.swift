import ArgumentParser
@_spi(ButtonHeistTooling) import ButtonHeist
import ThePlans

/// Shared options for commands that target a UI element by accessibility properties.
struct ElementTargetOptions: ParsableArguments {
    @Option(name: .long, help: "Accessibility identifier")
    var identifier: String?

    @Option(name: .shortAndLong, help: "Accessibility label")
    var label: String?

    @Option(name: .shortAndLong, help: "Accessibility value")
    var value: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Required traits (all must match)")
    var traits: [String] = []

    @Option(name: .customLong("exclude-traits"), parsing: .upToNextOption, help: "Excluded traits (none may be present)")
    var excludeTraits: [String] = []

    @Option(name: .long, help: "0-based index to select among multiple matches (in tree traversal order)")
    var ordinal: Int?

    func parsedMatcher() throws -> ElementPredicate? {
        let hasFields = identifier != nil || label != nil || value != nil
            || !traits.isEmpty || !excludeTraits.isEmpty
        guard hasFields else { return nil }
        return ElementPredicate(
            label: label.map { .exact($0) },
            identifier: identifier.map { .exact($0) },
            value: value.map { .exact($0) },
            traits: try parseTraits(traits, label: "trait"),
            excludeTraits: try parseTraits(excludeTraits, label: "excludeTrait")
        )
    }

    func requireTarget() throws -> ElementTarget {
        guard let elementTarget = try parsedTarget() else {
            throw ValidationError("Must specify --identifier, -l, -v, or --traits")
        }
        return elementTarget
    }

    func parsedTarget() throws -> ElementTarget? {
        let predicate = try parsedMatcher()
        guard predicate != nil || ordinal != nil else {
            return nil
        }
        do {
            return try ElementTargetGrammar.validatedTarget(
                predicate: predicate,
                predicateWasProvided: predicate != nil,
                ordinal: ordinal
            )
        } catch let error as ElementTargetGrammarError {
            throw ValidationError(error.diagnosticDescription)
        }
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

    /// Returns true when the supplied options construct a valid ElementTarget.
    var hasTarget: Bool {
        get throws {
            try parsedTarget() != nil
        }
    }
}
