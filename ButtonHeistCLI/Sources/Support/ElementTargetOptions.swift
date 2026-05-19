import ArgumentParser
import ButtonHeist

/// Shared options for commands that target a UI element by heistId or accessibility properties.
struct ElementTargetOptions: ParsableArguments {
    @Argument(help: "Element heistId (from get_interface)")
    var target: String?

    @Option(name: .long, help: "Element heistId (from get_interface)")
    var heistId: String?

    @Option(name: [.long, .customLong("id", withSingleDash: true)], help: "Accessibility identifier")
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

    /// Merges positional `target` and `--heist-id`, rejecting both at once.
    var resolvedHeistId: String? {
        get throws {
            if target != nil && heistId != nil {
                throw ValidationError("Cannot use both positional heistId and --heist-id")
            }
            return target ?? heistId
        }
    }

    func parsedMatcher() throws -> ElementMatcher? {
        let hasFields = identifier != nil || label != nil || value != nil
            || !traits.isEmpty || !excludeTraits.isEmpty
        guard hasFields else { return nil }
        return ElementMatcher(
            label: label,
            identifier: identifier,
            value: value,
            traits: try parseTraits(traits, label: "trait"),
            excludeTraits: try parseTraits(excludeTraits, label: "excludeTrait")
        )
    }

    func requireTarget() throws -> ElementTarget {
        guard let elementTarget = try parsedTarget() else {
            throw ValidationError("Must specify a heistId, -id, or -l")
        }
        return elementTarget
    }

    func parsedTarget() throws -> ElementTarget? {
        ElementTarget(
            heistId: try resolvedHeistId,
            matcher: try parsedMatcher() ?? ElementMatcher(),
            ordinal: ordinal
        )
    }

    private func parseTraits(_ names: [String], label: String) throws -> [HeistTrait]? {
        guard !names.isEmpty else { return nil }
        return try names.map { name in
            guard let trait = HeistTrait(rawValue: name) else {
                throw ValidationError("Unknown \(label) '\(name)'. Valid: \(HeistTrait.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            return trait
        }
    }

    /// Apply targeting options to a TheFence request dictionary.
    /// Uses the raw CLI option values so TheFence can parse them natively.
    func applyTo(_ request: inout [String: Any]) throws {
        if let resolved = try resolvedHeistId { request.set(.heistId, resolved) }
        if let identifier { request.set(.identifier, identifier) }
        if let label { request.set(.label, label) }
        if let value { request.set(.value, value) }
        if !traits.isEmpty { request.set(.traits, traits) }
        if !excludeTraits.isEmpty { request.set(.excludeTraits, excludeTraits) }
        if let ordinal { request.set(.ordinal, ordinal) }
    }

    /// Returns true when the supplied options construct a valid ElementTarget.
    var hasTarget: Bool {
        get throws {
            try parsedTarget() != nil
        }
    }
}
