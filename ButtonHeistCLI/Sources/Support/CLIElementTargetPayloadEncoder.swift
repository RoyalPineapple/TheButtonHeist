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
        case .within(let container, let target):
            return CommandArgumentWriter.object(
                CommandArgumentWriter.value(.container, object(container)),
                CommandArgumentWriter.value(.target, object(target))
            )
        }
    }

    private static func object(_ predicate: ElementPredicate) -> CLIRequestObject {
        guard !predicate.checks.isEmpty else { return CLIRequestObject() }
        return CommandArgumentWriter.object(
            CommandArgumentWriter.value(.checks, .array(predicate.checks.map(checkValue)))
        )
    }

    private static func checkValue(_ check: ElementPredicateCheck<String>) -> HeistValue {
        switch check {
        case .label(let match):
            return checkObject(kind: "label", match: stringMatchValue(match))
        case .identifier(let match):
            return checkObject(kind: "identifier", match: stringMatchValue(match))
        case .value(let match):
            return checkObject(kind: "value", match: stringMatchValue(match))
        case .hint(let match):
            return checkObject(kind: "hint", match: stringMatchValue(match))
        case .traits(let traits):
            return checkObject(kind: "traits", values: traitValues(traits))
        case .actions(let actions):
            return checkObject(kind: "actions", values: actionValues(actions))
        case .customContent(let match):
            return checkObject(kind: "customContent", match: customContentMatchValue(match))
        case .rotors(let matches):
            return checkObject(kind: "rotors", values: matches.map(stringMatchValue))
        case .exclude(let check):
            return CommandArgumentWriter.object(
                CommandArgumentWriter.value(.kind, "exclude"),
                CommandArgumentWriter.value(.check, checkValue(check))
            ).heistValue
        }
    }

    private static func checkObject(
        kind: String,
        match: HeistValue? = nil,
        values: [HeistValue]? = nil
    ) -> HeistValue {
        CommandArgumentWriter.object(
            CommandArgumentWriter.value(.kind, kind),
            CommandArgumentWriter.optional(.match, match),
            CommandArgumentWriter.optional(.values, values.map(HeistValue.array))
        ).heistValue
    }

    private static func stringMatchValue(_ match: StringMatch<String>) -> HeistValue {
        CommandArgumentWriter.object(
            CommandArgumentWriter.value(.mode, match.mode.rawValue),
            CommandArgumentWriter.optional(.value, match.valueIfPresent)
        ).heistValue
    }

    private static func traitValues(_ traits: Set<HeistTrait>) -> [HeistValue] {
        traits
            .sorted { $0.rawValue < $1.rawValue }
            .map { .string($0.rawValue) }
    }

    private static func actionValues(_ actions: Set<ElementAction>) -> [HeistValue] {
        actions
            .sorted { actionSortKey($0) < actionSortKey($1) }
            .map(actionValue)
    }

    private static func actionValue(_ action: ElementAction) -> HeistValue {
        switch action {
        case .activate:
            return .string("activate")
        case .typeText:
            return .string("typeText")
        case .increment:
            return .string("increment")
        case .decrement:
            return .string("decrement")
        case .custom(let name):
            return CommandArgumentWriter.object(
                CommandArgumentWriter.value(.custom, name)
            ).heistValue
        }
    }

    private static func actionSortKey(_ action: ElementAction) -> String {
        switch action {
        case .activate:
            return "0:activate"
        case .typeText:
            return "1:typeText"
        case .increment:
            return "2:increment"
        case .decrement:
            return "3:decrement"
        case .custom(let name):
            return "4:\(name)"
        }
    }

    private static func customContentMatchValue(_ match: CustomContentMatch<String>) -> HeistValue {
        CommandArgumentWriter.object(
            CommandArgumentWriter.optional(.label, match.label.map(stringMatchValue)),
            CommandArgumentWriter.optional(.value, match.value.map(stringMatchValue)),
            CommandArgumentWriter.optional(.isImportant, match.isImportant)
        ).heistValue
    }

    private static func object(_ predicate: ContainerPredicate) -> CLIRequestObject {
        CommandArgumentWriter.object(
            CommandArgumentWriter.value(.checks, .array(predicate.checks.map(containerCheckValue)))
        )
    }

    private static func containerCheckValue(_ check: ContainerPredicateCheck<String>) -> HeistValue {
        switch check {
        case .type(let type):
            return CommandArgumentWriter.object(
                CommandArgumentWriter.value(.kind, "type"),
                CommandArgumentWriter.value(.type, type.rawValue)
            ).heistValue
        case .semantic(let predicate):
            return CommandArgumentWriter.object(
                CommandArgumentWriter.value(.kind, "semantic"),
                CommandArgumentWriter.value(.semantic, semanticContainerPredicateValue(predicate))
            ).heistValue
        case .rowCount(let count):
            return CommandArgumentWriter.object(
                CommandArgumentWriter.value(.kind, "rowCount"),
                CommandArgumentWriter.value(.value, count)
            ).heistValue
        case .columnCount(let count):
            return CommandArgumentWriter.object(
                CommandArgumentWriter.value(.kind, "columnCount"),
                CommandArgumentWriter.value(.value, count)
            ).heistValue
        case .modalBoundary(let required):
            return CommandArgumentWriter.object(
                CommandArgumentWriter.value(.kind, "modalBoundary"),
                CommandArgumentWriter.value(.value, required)
            ).heistValue
        case .scrollable(let required):
            return CommandArgumentWriter.object(
                CommandArgumentWriter.value(.kind, "scrollable"),
                CommandArgumentWriter.value(.value, required)
            ).heistValue
        case .actions(let actions):
            return CommandArgumentWriter.object(
                CommandArgumentWriter.value(.kind, "actions"),
                CommandArgumentWriter.value(.values, .array(actionValues(actions)))
            ).heistValue
        }
    }

    private static func semanticContainerPredicateValue(_ predicate: SemanticContainerPredicate<String>) -> HeistValue {
        switch predicate {
        case .label(let match):
            return semanticContainerPredicateObject(kind: "label", match: match)
        case .value(let match):
            return semanticContainerPredicateObject(kind: "value", match: match)
        case .identifier(let match):
            return semanticContainerPredicateObject(kind: "identifier", match: match)
        }
    }

    private static func semanticContainerPredicateObject(kind: String, match: StringMatch<String>) -> HeistValue {
        CommandArgumentWriter.object(
            CommandArgumentWriter.value(.kind, kind),
            CommandArgumentWriter.value(.match, stringMatchValue(match))
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
