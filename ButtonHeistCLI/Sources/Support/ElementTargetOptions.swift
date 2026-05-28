import ArgumentParser
import ButtonHeist

/// Shared options for commands that target a UI element by heistId or accessibility properties.
struct ElementTargetOptions: ParsableArguments {
    @Argument(help: "Element heistId (from get_interface)")
    var target: String?

    @Option(name: .long, help: "Element heistId (from get_interface)")
    var heistId: String?

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
            throw ValidationError("Must specify a heistId, --identifier, or -l")
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

    func applyTo(_ parameters: inout CLIRequestParameters) throws {
        if let target = try targetParameterValue() {
            parameters.set(.target, target)
        }
    }

    /// Typed equivalent of `applyTo` — returns element targeting as `CLIRequestParameters`.
    func targetParameters() throws -> CLIRequestParameters {
        var parameters: CLIRequestParameters = [:]
        if let target = try targetParameterValue() {
            parameters[.target] = target
        }
        return parameters
    }

    private func targetParameterValue() throws -> HeistValue? {
        if let resolved = try resolvedHeistId {
            var target: [String: HeistValue] = [FenceParameterKey.heistId.rawValue: .string(resolved)]
            if let ordinal {
                target[FenceParameterKey.ordinal.rawValue] = .int(ordinal)
            }
            return .object(target)
        }

        var matcher: [String: HeistValue] = [:]
        if let identifier { matcher[FenceParameterKey.identifier.rawValue] = .string(identifier) }
        if let label { matcher[FenceParameterKey.label.rawValue] = .string(label) }
        if let value { matcher[FenceParameterKey.value.rawValue] = .string(value) }
        if !traits.isEmpty { matcher[FenceParameterKey.traits.rawValue] = .array(traits.map(HeistValue.string)) }
        if !excludeTraits.isEmpty {
            matcher[FenceParameterKey.excludeTraits.rawValue] = .array(excludeTraits.map(HeistValue.string))
        }
        guard !matcher.isEmpty else { return nil }

        var target: [String: HeistValue] = [FenceParameterKey.matcher.rawValue: .object(matcher)]
        if let ordinal {
            target[FenceParameterKey.ordinal.rawValue] = .int(ordinal)
        }
        return .object(target)
    }

    /// Returns true when the supplied options construct a valid ElementTarget.
    var hasTarget: Bool {
        get throws {
            try parsedTarget() != nil
        }
    }
}
