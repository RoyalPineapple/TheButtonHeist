import Foundation

import TheScore

private let accessibilityAdjustmentCountRange = 1...100

private extension TheFence {
    static func accessibilityClientMessages(
        target: ElementTarget,
        actionName: String?,
        count: TheFence.CountArgument
    ) throws -> [ClientMessage] {
        guard let actionName else {
            try rejectCount(count)
            return [.activate(target)]
        }
        switch actionName {
        case ElementAction.increment.description:
            return try repeatedAdjustmentCommands(.increment(target), count: count)
        case ElementAction.decrement.description:
            return try repeatedAdjustmentCommands(.decrement(target), count: count)
        default:
            try rejectCount(count)
            return [.performCustomAction(CustomActionTarget(elementTarget: target, actionName: actionName))]
        }
    }

    static func repeatedAdjustmentCommands(
        _ message: ClientMessage,
        count countArgument: TheFence.CountArgument
    ) throws -> [ClientMessage] {
        let count = try accessibilityAdjustmentCount(countArgument)
        return Array(repeating: message, count: count)
    }

    static func accessibilityAdjustmentCount(_ countArgument: TheFence.CountArgument) throws -> Int {
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

    static func rejectCount(_ countArgument: TheFence.CountArgument) throws {
        guard countArgument.observed != nil else { return }
        throw SchemaValidationError(
            field: "count",
            observed: countArgument.observed ?? "missing",
            expected: "only valid with increment or decrement"
        )
    }
}

extension TheFence {

    func decodeElementActionDispatch(
        command: Command,
        arguments: CommandArgumentEnvelope
    ) throws -> DecodedRequestDispatch {
        let input = ElementActionRequestInput(arguments)
        switch command {
        case .scroll:
            let target = try ScrollRequestInput(input, fence: self).target
            return decodedExecutablePayload(.scroll(target))
        case .scrollToVisible:
            let target = try ScrollToVisibleRequestInput(input, fence: self).target
            return decodedExecutablePayload(.scrollToVisible(target))
        case .elementSearch:
            let target = try ElementSearchRequestInput(input, fence: self).target
            return decodedExecutablePayload(.elementSearch(target))
        case .scrollToEdge:
            let target = try ScrollToEdgeRequestInput(input, fence: self).target
            return decodedExecutablePayload(.scrollToEdge(target))
        case .activate:
            let input = try ActivateRequestInput(input, fence: self)
            return Self.clientActionDispatch(
                try Self.accessibilityClientMessages(
                    target: input.target,
                    actionName: input.actionName,
                    count: input.count
                )
            )
        case .rotor:
            let target = try RotorRequestInput(input, fence: self).target
            return decodedExecutablePayload(.rotor(target))
        case .typeText:
            let target = try TypeTextRequestInput(input, fence: self).target
            return decodedExecutablePayload(.typeText(target))
        case .editAction:
            let target = try EditActionRequestInput(input).target
            return decodedExecutablePayload(.editAction(target))
        case .setPasteboard:
            let target = try SetPasteboardRequestInput(input).target
            return decodedExecutablePayload(.setPasteboard(target))
        case .waitFor:
            let target = try WaitForRequestInput(input, fence: self).target
            return decodedExecutablePayload(.waitFor(target))
        default:
            throw FenceError.invalidRequest("Unexpected element action command: \(command.rawValue)")
        }
    }

    private func decodedExecutablePayload(_ message: ClientMessage) -> DecodedRequestDispatch {
        Self.clientActionDispatch([message])
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
                    observed: "string \"\(name)\"",
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

        var observedDescription: String {
            request.observedDescription
        }

        @ButtonHeistActor
        func elementTarget(in fence: TheFence) throws -> ElementTarget? {
            guard let target = try request.schemaDictionary("target") else { return nil }
            try target.rejectUnknownKeys(
                allowed: ["heistId", "matcher", "ordinal"],
                expected: "valid target field"
            )
            let heistId = try target.schemaString("heistId")
            let matcherObject = try target.schemaDictionary("matcher")
            let ordinal = try target.schemaNonNegativeInteger("ordinal")
            let hasMixedHeistIdTarget = ordinal != nil || matcherObject != nil
            if heistId != nil, hasMixedHeistIdTarget {
                throw SchemaValidationError(
                    field: "target",
                    observed: target.observedDescription,
                    expected: "either heistId or matcher with optional ordinal"
                )
            }
            if let heistId {
                return .heistId(heistId)
            }
            guard let matcherObject else {
                throw SchemaValidationError(
                    field: "target",
                    observed: target.observedDescription,
                    expected: "heistId or matcher"
                )
            }
            try matcherObject.rejectUnknownKeys(
                allowed: ["label", "identifier", "value", "traits", "excludeTraits"],
                expected: "valid target.matcher field"
            )
            let matcher = try matcher(from: matcherObject)
            guard matcher.nonEmpty != nil else {
                throw SchemaValidationError(
                    field: target.field("matcher"),
                    observed: matcherObject.observedDescription,
                    expected: "matcher with label, identifier, value, traits, or excludeTraits"
                )
            }
            return ElementTarget(
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
            guard matcher.hasPredicates else {
                throw SchemaValidationError(
                    field: "container",
                    observed: container.observedDescription,
                    expected: "container target with stableId, type, label, value, identifier, or isModalBoundary"
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
                throw MissingElementTarget(command: TheFence.Command.activate.rawValue)
            }
            return CustomActionTarget(elementTarget: elementTarget, actionName: actionName)
        }

        var hasElementTargetFields: Bool {
            request.keys.contains("target")
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
            try matcher(from: request)
        }

        @ButtonHeistActor
        func matcher(from source: some TheFence.CommandArgumentReadable) throws -> ElementMatcher {
            ElementMatcher(
                label: try source.schemaString("label"),
                identifier: try source.schemaString("identifier"),
                value: try source.schemaString("value"),
                traits: try TheFence.parseTraitNames(
                    try source.schemaStringArray("traits"),
                    field: source.field("traits")
                ),
                excludeTraits: try TheFence.parseTraitNames(
                    try source.schemaStringArray("excludeTraits"),
                    field: source.field("excludeTraits")
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
                throw SchemaValidationError(field: request.field(key), observed: "string \"\"", expected: "non-empty string")
            }
            return value
        }

        func optionalNonEmptyString(_ key: String) throws -> String? {
            guard let value = try string(key) else { return nil }
            if value.isEmpty {
                throw SchemaValidationError(field: request.field(key), observed: "string \"\"", expected: "non-empty string")
            }
            return value
        }

        func accessibilityActionName(_ key: String) throws -> String? {
            guard let value = try optionalNonEmptyString(key) else { return nil }
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
            as type: E.Type
        ) throws -> E? where E: CaseIterable & RawRepresentable, E.RawValue == String {
            try request.schemaEnum(key, as: type)
        }

        func requiredEnumValue<E>(
            _ key: String,
            as type: E.Type
        ) throws -> E where E: CaseIterable & RawRepresentable, E.RawValue == String {
            try request.requiredSchemaEnum(key, as: type)
        }

        func countArgument() throws -> TheFence.CountArgument {
            TheFence.CountArgument(
                value: try integer("count"),
                observed: request.observedDescription(for: "count")
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
                throw SchemaValidationError(field: "currentHeistId", observed: "missing", expected: "string")
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
            let direction = try request.enumValue("direction", as: ScrollDirection.self) ?? .down
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
                direction: try request.enumValue("direction", as: ScrollSearchDirection.self) ?? .down
            )
        }
    }

    struct ScrollToEdgeRequestInput {
        let target: ScrollToEdgeTarget

        @ButtonHeistActor
        init(_ request: ElementActionRequestInput, fence: TheFence) throws {
            let edge = try request.enumValue("edge", as: ScrollEdge.self) ?? .top
            target = ScrollToEdgeTarget(
                selection: try request.scrollContainerSelection(in: fence),
                edge: edge
            )
        }
    }

    struct ActivateRequestInput {
        let target: ElementTarget
        let actionName: String?
        let count: TheFence.CountArgument

        @ButtonHeistActor
        init(_ request: ElementActionRequestInput, fence: TheFence) throws {
            self.target = try request.requiredElementTarget(command: .activate, in: fence)
            self.actionName = try request.accessibilityActionName("action")
            self.count = try request.countArgument()
        }
    }

    struct RotorRequestInput {
        let target: RotorTarget

        @ButtonHeistActor
        init(_ request: ElementActionRequestInput, fence: TheFence) throws {
            let rotor = try request.string("rotor")
            let rotorIndex = try request.nonNegativeInteger("rotorIndex")
            if rotor != nil, rotorIndex != nil {
                throw SchemaValidationError(
                    field: "rotor/rotorIndex",
                    observed: request.observedDescription,
                    expected: "either rotor or rotorIndex"
                )
            }
            let cursor = try request.rotorTextCursor()
            let currentHeistId = try cursor.currentHeistId ?? request.string("currentHeistId")
            let selection: RotorSelection = if let rotor {
                .named(rotor)
            } else if let rotorIndex {
                .index(rotorIndex)
            } else {
                .automatic
            }
            let continuation: RotorContinuation = if let range = cursor.currentTextRange,
                                                     let currentHeistId {
                .textRange(currentHeistId, range)
            } else if let currentHeistId {
                .item(currentHeistId)
            } else {
                .none
            }

            target = RotorTarget(
                elementTarget: try request.requiredElementTarget(command: .rotor, in: fence),
                selection: selection,
                direction: try request.enumValue("direction", as: RotorDirection.self) ?? .next,
                continuation: continuation
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
