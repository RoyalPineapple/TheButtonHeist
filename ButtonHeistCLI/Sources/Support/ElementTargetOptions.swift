import ArgumentParser
import ButtonHeist

/// Shared options for commands that target a UI element by heistId or accessibility properties.
struct ElementTargetOptions: ParsableArguments {
    @Option(name: .long, help: "Element heistId (from get_interface)")
    var heistId: String?

    @Option(name: .long, help: "Accessibility identifier")
    var identifier: String?

    @Option(name: .long, help: "Accessibility label")
    var label: String?

    @Option(name: .long, help: "Accessibility value")
    var value: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Required traits (all must match)")
    var traits: [String] = []

    @Option(name: .customLong("exclude-traits"), parsing: .upToNextOption, help: "Excluded traits (none may be present)")
    var excludeTraits: [String] = []

    func parsedMatcher() throws -> ElementMatcher? {
        let hasFields = identifier != nil || label != nil || value != nil
            || !traits.isEmpty || !excludeTraits.isEmpty
        guard hasFields else { return nil }
        let parsedTraits: [HeistTrait]? = traits.isEmpty ? nil : try traits.map { name in
            guard let trait = HeistTrait(rawValue: name) else {
                throw ValidationError("Unknown trait '\(name)'. Valid: \(HeistTrait.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            return trait
        }
        let parsedExcludeTraits: [HeistTrait]? = excludeTraits.isEmpty ? nil : try excludeTraits.map { name in
            guard let trait = HeistTrait(rawValue: name) else {
                throw ValidationError("Unknown excludeTrait '\(name)'. Valid: \(HeistTrait.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            return trait
        }
        return ElementMatcher(
            label: label,
            identifier: identifier,
            value: value,
            traits: parsedTraits,
            excludeTraits: parsedExcludeTraits
        )
    }

    func actionTarget() throws -> ElementTarget? {
        ElementTarget(heistId: heistId, matcher: try parsedMatcher() ?? ElementMatcher())
    }

    func requireTarget() throws -> ElementTarget {
        guard let target = try actionTarget() else {
            throw ValidationError("Must specify --heist-id, --identifier, or --label")
        }
        return target
    }

    /// Apply targeting options to a TheFence request dictionary.
    /// Uses the raw CLI option values so TheFence can parse them natively.
    func applyTo(_ request: inout [String: Any]) {
        if let heistId { request["heistId"] = heistId }
        if let identifier { request["identifier"] = identifier }
        if let label { request["label"] = label }
        if let value { request["value"] = value }
        if !traits.isEmpty { request["traits"] = traits }
        if !excludeTraits.isEmpty { request["excludeTraits"] = excludeTraits }
    }

    /// Returns true if any targeting option is specified.
    var hasTarget: Bool {
        heistId != nil || identifier != nil || label != nil || value != nil
            || !traits.isEmpty || !excludeTraits.isEmpty
    }
}
