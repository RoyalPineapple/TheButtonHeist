import Foundation

import TheScore

private let accessibilityAdjustmentCountRange = 1...100

extension TheFence.ScrollPayload {

    var clientMessage: ClientMessage {
        switch self {
        case .scroll(let target):
            return .scroll(target)
        case .scrollToVisible(let target):
            return .scrollToVisible(target)
        case .elementSearch(let target):
            return .elementSearch(target)
        case .scrollToEdge(let target):
            return .scrollToEdge(target)
        }
    }
}

extension TheFence.AccessibilityPayload {

    func clientMessages() throws -> [ClientMessage] {
        switch self {
        case .activate(let target, let actionName, let count):
            guard let actionName else {
                try Self.rejectCount(count)
                return [.activate(target)]
            }
            return try Self.namedAccessibilityCommands(
                target: target,
                actionName: actionName,
                count: count
            )
        case .increment(let target, let count):
            return try Self.repeatedAdjustmentCommands(.increment(target), count: count)
        case .decrement(let target, let count):
            return try Self.repeatedAdjustmentCommands(.decrement(target), count: count)
        case .performCustomAction(let target, let count):
            try Self.rejectCount(count)
            return [.performCustomAction(target)]
        }
    }

    private static func namedAccessibilityCommands(
        target: ElementTarget,
        actionName: String,
        count: TheFence.CountArgument
    ) throws -> [ClientMessage] {
        if actionName.hasPrefix("action:") {
            try rejectCount(count)
            let customName = String(actionName.dropFirst("action:".count))
            guard !customName.isEmpty else {
                throw FenceError.invalidRequest("action: prefix requires a name (e.g. \"action:myAction\")")
            }
            return [.performCustomAction(CustomActionTarget(elementTarget: target, actionName: customName))]
        }

        switch actionName {
        case TheFence.Command.increment.rawValue:
            return try repeatedAdjustmentCommands(.increment(target), count: count)
        case TheFence.Command.decrement.rawValue:
            return try repeatedAdjustmentCommands(.decrement(target), count: count)
        default:
            try rejectCount(count)
            return [.performCustomAction(CustomActionTarget(elementTarget: target, actionName: actionName))]
        }
    }

    private static func repeatedAdjustmentCommands(
        _ message: ClientMessage,
        count countArgument: TheFence.CountArgument
    ) throws -> [ClientMessage] {
        let count = try accessibilityAdjustmentCount(countArgument)
        return Array(repeating: message, count: count)
    }

    private static func accessibilityAdjustmentCount(_ countArgument: TheFence.CountArgument) throws -> Int {
        let count = countArgument.value ?? 1
        guard accessibilityAdjustmentCountRange.contains(count) else {
            throw SchemaValidationError(
                field: "count",
                observed: count,
                expected: "integer in \(accessibilityAdjustmentCountRange.lowerBound)...\(accessibilityAdjustmentCountRange.upperBound)"
            )
        }
        return count
    }

    private static func rejectCount(_ countArgument: TheFence.CountArgument) throws {
        guard countArgument.observed != nil else { return }
        throw SchemaValidationError(
            field: "count",
            observed: countArgument.observed,
            expected: "only valid with increment or decrement"
        )
    }
}

extension TheFence {

    func decodeElementActionPayload(
        command: Command,
        arguments: CommandArgumentEnvelope
    ) throws -> RequestPayload {
        let input = ElementActionRequestInput(arguments)
        switch command {
        case .scroll:
            return .scroll(.scroll(try ScrollRequestInput(input, fence: self).target))
        case .scrollToVisible:
            return .scroll(.scrollToVisible(try ScrollToVisibleRequestInput(input, fence: self).target))
        case .elementSearch:
            return .scroll(.elementSearch(try ElementSearchRequestInput(input, fence: self).target))
        case .scrollToEdge:
            return .scroll(.scrollToEdge(try ScrollToEdgeRequestInput(input, fence: self).target))
        case .activate:
            return .accessibility(try ActivateRequestInput(input, fence: self).payload)
        case .increment:
            return .accessibility(try IncrementRequestInput(input, fence: self).payload)
        case .decrement:
            return .accessibility(try DecrementRequestInput(input, fence: self).payload)
        case .performCustomAction:
            return .accessibility(try PerformCustomActionRequestInput(input, fence: self).payload)
        case .rotor:
            return .rotor(try RotorRequestInput(input, fence: self).target)
        case .typeText:
            return .typeText(try TypeTextRequestInput(input, fence: self).target)
        case .editAction:
            return .editAction(try EditActionRequestInput(input).target)
        case .setPasteboard:
            return .setPasteboard(try SetPasteboardRequestInput(input).target)
        case .waitFor:
            return .waitFor(try WaitForRequestInput(input, fence: self).target)
        default:
            throw FenceError.invalidRequest("Unexpected element action command: \(command.rawValue)")
        }
    }

    func decodedElementTarget(_ arguments: some CommandArgumentReadable) throws -> ElementTarget? {
        try ElementActionRequestInput(arguments).elementTarget(in: self)
    }

    func decodedElementMatcher(_ arguments: some CommandArgumentReadable) throws -> ElementMatcher {
        try ElementActionRequestInput(arguments).matcher()
    }

    /// Parse an array of trait name strings into typed `HeistTrait` values.
    /// Throws `SchemaValidationError` with the list of valid names when an
    /// unknown name is encountered. Returns `nil` when `names` is `nil` so
    /// callers can pass a missing field through unchanged.
    nonisolated static func parseTraitNames(_ names: [String]?, field: String) throws -> [HeistTrait]? {
        try names?.enumerated().map { index, name in
            guard let trait = HeistTrait(rawValue: name) else {
                throw SchemaValidationError(
                    field: "\(field)[\(index)]",
                    observed: name as Any,
                    expected: SchemaValidationError.expectedEnum(HeistTrait.self)
                )
            }
            return trait
        }
    }
}

private extension TheFence {

    struct ElementActionRequestInput {
        private let request: any CommandArgumentReadable

        init(_ request: some CommandArgumentReadable) {
            self.request = request
        }

        @ButtonHeistActor
        func elementTarget(in fence: TheFence) throws -> ElementTarget? {
            let heistId = try string("heistId")
            let matcher = try matcher()
            let ordinal = try ordinal()
            let hasMixedHeistIdTarget = ordinal != nil || hasMatcherFieldKeys
            if heistId != nil, hasMixedHeistIdTarget {
                throw SchemaValidationError(
                    field: "target",
                    observed: request.observedDescription,
                    expected: "either heistId or matcher fields with optional ordinal"
                )
            }
            return ElementTarget(
                heistId: heistId,
                matcher: matcher,
                ordinal: ordinal
            )
        }

        @ButtonHeistActor
        func requiredElementTarget(command: TheFence.Command, in fence: TheFence) throws -> ElementTarget {
            guard let target = try elementTarget(in: fence) else {
                throw MissingElementTarget(command: command.rawValue)
            }
            return target
        }

        func scrollContainerTarget() throws -> ScrollContainerTarget? {
            let container = try request.schemaDictionary("container")
            let stableId = try container?.schemaString("stableId") ?? string("stableId")
            let captureLocalRef = try container?.schemaString("captureLocalRef") ?? string("captureLocalRef")
            guard stableId != nil || captureLocalRef != nil else { return nil }
            return ScrollContainerTarget(stableId: stableId, captureLocalRef: captureLocalRef)
        }

        @ButtonHeistActor
        func scrollContainerSelection(in fence: TheFence) throws -> ScrollContainerSelection {
            let elementTarget = try elementTarget(in: fence)
            let containerTarget = try scrollContainerTarget()
            switch (containerTarget, elementTarget) {
            case (.some, .some):
                throw SchemaValidationError(
                    field: "target",
                    observed: request.observedDescription,
                    expected: "at most one of container or element target"
                )
            case (.some(let containerTarget), nil):
                return .container(containerTarget)
            case (nil, .some(let elementTarget)):
                return .element(elementTarget)
            case (nil, nil):
                return .visibleContainer
            }
        }

        func customActionContainerTarget() throws -> (matcher: ContainerMatcher, ordinal: Int?)? {
            guard let container = try request.schemaDictionary("container") else { return nil }
            let matcher = ContainerMatcher(
                stableId: try container.schemaString("stableId"),
                type: try container.schemaEnum("type", as: ContainerTypeName.self),
                label: try container.schemaString("label"),
                value: try container.schemaString("value"),
                identifier: try container.schemaString("identifier"),
                isModalBoundary: try container.schemaBoolean("isModalBoundary")
            )
            let ordinal = try nonNegativeInteger("ordinal")
            guard matcher.hasPredicates || ordinal != nil else {
                throw SchemaValidationError(
                    field: "container",
                    observed: container.observedDescription,
                    expected: "container selector with stableId, type, label, value, identifier, isModalBoundary, or ordinal"
                )
            }
            return (matcher, ordinal)
        }

        @ButtonHeistActor
        func customActionTarget(actionName: String, in fence: TheFence) throws -> CustomActionTarget {
            let containerTarget = try customActionContainerTarget()
            if let containerTarget {
                guard !hasElementTargetFields else {
                    throw SchemaValidationError(
                        field: "target",
                        observed: request.observedDescription,
                        expected: "exactly one element target or container selector"
                    )
                }
                return CustomActionTarget(
                    containerTarget: containerTarget.matcher,
                    ordinal: containerTarget.ordinal,
                    actionName: actionName
                )
            }

            guard let elementTarget = try elementTarget(in: fence) else {
                throw MissingElementTarget(command: TheFence.Command.performCustomAction.rawValue)
            }
            return CustomActionTarget(elementTarget: elementTarget, actionName: actionName)
        }

        var hasElementTargetFields: Bool {
            if request.keys.contains("heistId") { return true }
            if hasMatcherFieldKeys { return true }
            return false
        }

        var hasMatcherFieldKeys: Bool {
            if request.keys.contains("label") { return true }
            if request.keys.contains("identifier") { return true }
            if request.keys.contains("value") { return true }
            if request.keys.contains("traits") { return true }
            if request.keys.contains("excludeTraits") { return true }
            return false
        }

        @ButtonHeistActor
        func matcher() throws -> ElementMatcher {
            ElementMatcher(
                label: try string("label"),
                identifier: try string("identifier"),
                value: try string("value"),
                traits: try TheFence.parseTraitNames(
                    try request.schemaStringArray("traits"),
                    field: request.field("traits")
                ),
                excludeTraits: try TheFence.parseTraitNames(
                    try request.schemaStringArray("excludeTraits"),
                    field: request.field("excludeTraits")
                )
            )
        }

        func string(_ key: String) throws -> String? {
            try request.schemaString(key)
        }

        func requiredString(_ key: String) throws -> String {
            try request.requiredSchemaString(key)
        }

        func nonEmptyString(_ key: String) throws -> String {
            let value = try requiredString(key)
            if value.isEmpty {
                throw SchemaValidationError(field: request.field(key), observed: value as Any, expected: "non-empty string")
            }
            return value
        }

        func optionalNonEmptyString(_ key: String) throws -> String? {
            guard let value = try string(key) else { return nil }
            if value.isEmpty {
                throw SchemaValidationError(field: request.field(key), observed: value as Any, expected: "non-empty string")
            }
            return value
        }

        func accessibilityActionName(_ key: String) throws -> String? {
            guard let value = try optionalNonEmptyString(key) else { return nil }
            if value.hasPrefix("action:") {
                let customName = String(value.dropFirst("action:".count))
                if !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
                throw SchemaValidationError(
                    field: request.field(key),
                    observed: value as Any,
                    expected: "action: prefix followed by a custom action name or a built-in action name"
                )
            }
            return value
        }

        func integer(_ key: String) throws -> Int? {
            try request.schemaInteger(key)
        }

        func nonNegativeInteger(_ key: String) throws -> Int? {
            try request.schemaNonNegativeInteger(key)
        }

        func ordinal() throws -> Int? {
            try nonNegativeInteger("ordinal")
        }

        func boolean(_ key: String) throws -> Bool? {
            try request.schemaBoolean(key)
        }

        func number(_ key: String) throws -> Double? {
            try request.schemaNumber(key)
        }

        func enumValue<E>(
            _ key: String,
            as type: E.Type,
            normalizedBy normalize: (String) -> String = { $0 }
        ) throws -> E? where E: CaseIterable & RawRepresentable, E.RawValue == String {
            try request.schemaEnum(key, as: type, normalizedBy: normalize)
        }

        func requiredEnumValue<E>(
            _ key: String,
            as type: E.Type,
            normalizedBy normalize: (String) -> String = { $0 }
        ) throws -> E where E: CaseIterable & RawRepresentable, E.RawValue == String {
            try request.requiredSchemaEnum(key, as: type, normalizedBy: normalize)
        }

        func countArgument() throws -> TheFence.CountArgument {
            TheFence.CountArgument(
                value: try integer("count"),
                observed: request.observedValue(for: "count")
            )
        }

        func rotorTextCursor() throws -> RotorTextCursorInput {
            let startOffset = try integer("currentTextStartOffset")
            let endOffset = try integer("currentTextEndOffset")
            if (startOffset == nil) != (endOffset == nil) {
                throw FenceError.invalidRequest("currentTextStartOffset and currentTextEndOffset must be provided together")
            }
            guard let startOffset, let endOffset else {
                return RotorTextCursorInput(currentHeistId: nil, currentTextRange: nil)
            }
            guard let currentHeistId = try string("currentHeistId") else {
                throw SchemaValidationError(field: "currentHeistId", observed: nil, expected: "string")
            }
            guard startOffset >= 0, endOffset >= startOffset else {
                throw SchemaValidationError(
                    field: "currentTextStartOffset/currentTextEndOffset",
                    observed: "\(startOffset)..<\(endOffset)",
                    expected: "integer range with start >= 0 and end >= start"
                )
            }
            return RotorTextCursorInput(
                currentHeistId: currentHeistId,
                currentTextRange: TextRangeReference(startOffset: startOffset, endOffset: endOffset)
            )
        }
    }

    struct RotorTextCursorInput {
        let currentHeistId: String?
        let currentTextRange: TextRangeReference?
    }

    struct ScrollRequestInput {
        let target: ScrollTarget

        @ButtonHeistActor
        init(_ request: ElementActionRequestInput, fence: TheFence) throws {
            let direction = try request.enumValue("direction", as: ScrollDirection.self) { $0.lowercased() } ?? .down
            target = ScrollTarget(
                selection: try request.scrollContainerSelection(in: fence),
                direction: direction
            )
        }
    }

    struct ScrollToVisibleRequestInput {
        let target: ScrollToVisibleTarget

        @ButtonHeistActor
        init(_ request: ElementActionRequestInput, fence: TheFence) throws {
            target = ScrollToVisibleTarget(
                elementTarget: try request.requiredElementTarget(command: .scrollToVisible, in: fence)
            )
        }
    }

    struct ElementSearchRequestInput {
        let target: ElementSearchTarget

        @ButtonHeistActor
        init(_ request: ElementActionRequestInput, fence: TheFence) throws {
            target = ElementSearchTarget(
                elementTarget: try request.requiredElementTarget(command: .elementSearch, in: fence),
                direction: try request.enumValue("direction", as: ScrollSearchDirection.self) { $0.lowercased() }
            )
        }
    }

    struct ScrollToEdgeRequestInput {
        let target: ScrollToEdgeTarget

        @ButtonHeistActor
        init(_ request: ElementActionRequestInput, fence: TheFence) throws {
            let edge = try request.enumValue("edge", as: ScrollEdge.self) { $0.lowercased() } ?? .top
            target = ScrollToEdgeTarget(
                selection: try request.scrollContainerSelection(in: fence),
                edge: edge
            )
        }
    }

    struct ActivateRequestInput {
        let payload: AccessibilityPayload

        @ButtonHeistActor
        init(_ request: ElementActionRequestInput, fence: TheFence) throws {
            let target = try request.requiredElementTarget(command: .activate, in: fence)
            payload = .activate(
                target,
                actionName: try request.accessibilityActionName("action"),
                count: try request.countArgument()
            )
        }
    }

    struct IncrementRequestInput {
        let payload: AccessibilityPayload

        @ButtonHeistActor
        init(_ request: ElementActionRequestInput, fence: TheFence) throws {
            let target = try request.requiredElementTarget(command: .increment, in: fence)
            payload = .increment(target, count: try request.countArgument())
        }
    }

    struct DecrementRequestInput {
        let payload: AccessibilityPayload

        @ButtonHeistActor
        init(_ request: ElementActionRequestInput, fence: TheFence) throws {
            let target = try request.requiredElementTarget(command: .decrement, in: fence)
            payload = .decrement(target, count: try request.countArgument())
        }
    }

    struct PerformCustomActionRequestInput {
        let payload: AccessibilityPayload

        @ButtonHeistActor
        init(_ request: ElementActionRequestInput, fence: TheFence) throws {
            let actionName = try request.nonEmptyString("action")
            payload = .performCustomAction(
                try request.customActionTarget(actionName: actionName, in: fence),
                count: try request.countArgument()
            )
        }
    }

    struct RotorRequestInput {
        let target: RotorTarget

        @ButtonHeistActor
        init(_ request: ElementActionRequestInput, fence: TheFence) throws {
            let rotorIndex = try request.nonNegativeInteger("rotorIndex")
            let cursor = try request.rotorTextCursor()
            let currentHeistId = try cursor.currentHeistId ?? request.string("currentHeistId")

            target = RotorTarget(
                elementTarget: try request.requiredElementTarget(command: .rotor, in: fence),
                rotor: try request.string("rotor"),
                rotorIndex: rotorIndex,
                direction: try request.enumValue("direction", as: RotorDirection.self) { $0.lowercased() } ?? .next,
                currentHeistId: currentHeistId,
                currentTextRange: cursor.currentTextRange
            )
        }
    }

    struct TypeTextRequestInput {
        let target: TypeTextTarget

        @ButtonHeistActor
        init(_ request: ElementActionRequestInput, fence: TheFence) throws {
            target = TypeTextTarget(
                text: try request.nonEmptyString("text"),
                elementTarget: try request.elementTarget(in: fence)
            )
        }
    }

    struct EditActionRequestInput {
        let target: EditActionTarget

        init(_ request: ElementActionRequestInput) throws {
            target = EditActionTarget(
                action: try request.requiredEnumValue("action", as: EditAction.self)
            )
        }
    }

    struct SetPasteboardRequestInput {
        let target: SetPasteboardTarget

        init(_ request: ElementActionRequestInput) throws {
            target = SetPasteboardTarget(
                text: try request.requiredString("text")
            )
        }
    }

    struct WaitForRequestInput {
        let target: WaitForTarget

        @ButtonHeistActor
        init(_ request: ElementActionRequestInput, fence: TheFence) throws {
            target = WaitForTarget(
                elementTarget: try request.requiredElementTarget(command: .waitFor, in: fence),
                absent: try request.boolean("absent"),
                timeout: try request.number("timeout")
            )
        }
    }
}
