@_spi(ButtonHeistTooling) import ButtonHeist
import ThePlans

enum CLIElementTargetPayloadEncoder {
    static func value(_ target: ElementTarget) -> HeistValue {
        object(target).heistValue
    }

    static func object(_ target: ElementTarget) -> CLIRequestObject {
        switch target {
        case .predicate(let predicate, let ordinal):
            return object(predicate).adding(CommandArgumentWriter.optional(.ordinal, ordinal))
        }
    }

    private static func object(_ predicate: ElementPredicate) -> CLIRequestObject {
        var object = CLIRequestObject()
        for check in predicate.checks {
            append(check, to: &object)
        }
        return object
    }

    private static func append(
        _ check: ElementPredicateCheck<String>,
        to object: inout CLIRequestObject
    ) {
        switch check {
        case .label(let match):
            object.appendOneOrMany(stringMatchValue(match), for: .label)
        case .identifier(let match):
            object.appendOneOrMany(stringMatchValue(match), for: .identifier)
        case .value(let match):
            object.appendOneOrMany(stringMatchValue(match), for: .value)
        case .traits(let traits):
            appendTraits(traits, to: .traits, in: &object)
        case .excludeTraits(let traits):
            appendTraits(traits, to: .excludeTraits, in: &object)
        }
    }

    private static func appendTraits(
        _ traits: Set<HeistTrait>,
        to key: FenceParameterKey,
        in object: inout CLIRequestObject
    ) {
        guard !traits.isEmpty else { return }
        var values: [HeistValue]
        if case .array(let existing)? = object[key] {
            values = existing
        } else {
            values = []
        }
        values.append(contentsOf: traits.sorted { $0.rawValue < $1.rawValue }.map { .string($0.rawValue) })
        object[key] = .array(values)
    }

    private static func stringMatchValue(_ match: StringMatch<String>) -> HeistValue {
        CommandArgumentWriter.object(
            CommandArgumentWriter.value(.mode, match.mode.rawValue),
            CommandArgumentWriter.value(.value, match.value)
        ).heistValue
    }
}

private extension CLIRequestObject {
    func adding(_ fields: CommandArgumentWriter.Field?...) -> Self {
        var copy = self
        for field in fields.compactMap({ $0 }) {
            copy[field.key] = field.value
        }
        return copy
    }
}
