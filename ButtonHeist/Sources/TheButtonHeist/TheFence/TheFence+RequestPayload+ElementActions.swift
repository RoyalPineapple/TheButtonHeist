import Foundation

import TheScore

extension TheFence {

    func decodeElementActionPayload(
        command: Command,
        request: [String: Any]
    ) throws -> RequestPayload {
        switch command {
        case .scroll:
            return .scroll(.scroll(try ScrollRequestInput(request, fence: self).target))
        case .scrollToVisible:
            return .scroll(.scrollToVisible(try ScrollToVisibleRequestInput(request, fence: self).target))
        case .elementSearch:
            return .scroll(.elementSearch(try ElementSearchRequestInput(request, fence: self).target))
        case .scrollToEdge:
            return .scroll(.scrollToEdge(try ScrollToEdgeRequestInput(request, fence: self).target))
        case .activate:
            return .accessibility(try ActivateRequestInput(request, fence: self).payload)
        case .increment:
            return .accessibility(try IncrementRequestInput(request, fence: self).payload)
        case .decrement:
            return .accessibility(try DecrementRequestInput(request, fence: self).payload)
        case .performCustomAction:
            return .accessibility(try PerformCustomActionRequestInput(request, fence: self).payload)
        case .rotor:
            return .rotor(try RotorRequestInput(request, fence: self).target)
        case .typeText:
            return .typeText(try TypeTextRequestInput(request, fence: self).target)
        case .editAction:
            return .editAction(try EditActionRequestInput(request).target)
        case .setPasteboard:
            return .setPasteboard(try SetPasteboardRequestInput(request).target)
        case .waitFor:
            return .waitFor(try WaitForRequestInput(request, fence: self).target)
        default:
            throw FenceError.invalidRequest("Unexpected element action command: \(command.rawValue)")
        }
    }

    func decodedElementTarget(_ request: [String: Any]) throws -> ElementTarget? {
        try ElementTargetRequestInput(request, fence: self).target
    }

    func decodedScrollContainerTarget(_ request: [String: Any]) throws -> ScrollContainerTarget? {
        let container = try request.schemaDictionary("container")
        let stableId = try container?.schemaString("stableId") ?? request.schemaString("stableId")
        let captureLocalRef = try container?.schemaString("captureLocalRef") ?? request.schemaString("captureLocalRef")
        guard stableId != nil || captureLocalRef != nil else { return nil }
        return ScrollContainerTarget(stableId: stableId, captureLocalRef: captureLocalRef)
    }

    func requiredElementTarget(_ request: [String: Any], command: Command) throws -> ElementTarget {
        guard let target = try decodedElementTarget(request) else {
            throw MissingElementTarget(command: command.rawValue)
        }
        return target
    }

    func elementTarget(_ dictionary: [String: Any]) throws -> ElementTarget? {
        try ElementTargetRequestInput(dictionary, fence: self).target
    }

    func elementMatcher(_ dictionary: [String: Any]) throws -> ElementMatcher {
        ElementMatcher(
            label: try dictionary.schemaString("label"),
            identifier: try dictionary.schemaString("identifier"),
            value: try dictionary.schemaString("value"),
            traits: try parseTraitNames(try dictionary.schemaStringArray("traits"), field: "traits"),
            excludeTraits: try parseTraitNames(try dictionary.schemaStringArray("excludeTraits"), field: "excludeTraits")
        )
    }

    /// Parse an array of trait name strings into typed `HeistTrait` values.
    /// Throws `FenceError.invalidRequest` with the list of valid names when an
    /// unknown name is encountered. Returns `nil` when `names` is `nil` so
    /// callers can pass a missing field through unchanged.
    private func parseTraitNames(_ names: [String]?, field: String) throws -> [HeistTrait]? {
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

    struct ElementTargetRequestInput {
        let heistId: HeistId?
        let matcher: ElementMatcher
        let ordinal: Int?

        var target: ElementTarget? {
            ElementTarget(heistId: heistId, matcher: matcher, ordinal: ordinal)
        }

        @ButtonHeistActor
        init(_ request: [String: Any], fence: TheFence) throws {
            self.ordinal = try Self.ordinal(from: request)
            self.heistId = try request.schemaString("heistId")
            self.matcher = try fence.elementMatcher(request)
        }

        static func ordinal(from request: [String: Any]) throws -> Int? {
            guard let ordinal = try request.schemaInteger("ordinal") else { return nil }
            guard ordinal >= 0 else {
                throw SchemaValidationError(field: "ordinal", observed: ordinal, expected: "integer >= 0")
            }
            return ordinal
        }
    }

    struct ScrollRequestInput {
        let target: ScrollTarget

        @ButtonHeistActor
        init(_ request: [String: Any], fence: TheFence) throws {
            let direction = try request.schemaEnum("direction", as: ScrollDirection.self) { $0.lowercased() } ?? .down
            target = ScrollTarget(
                elementTarget: try fence.decodedElementTarget(request),
                containerTarget: try fence.decodedScrollContainerTarget(request),
                direction: direction
            )
        }
    }

    struct ScrollToVisibleRequestInput {
        let target: ScrollToVisibleTarget

        @ButtonHeistActor
        init(_ request: [String: Any], fence: TheFence) throws {
            target = ScrollToVisibleTarget(
                elementTarget: try fence.requiredElementTarget(request, command: .scrollToVisible)
            )
        }
    }

    struct ElementSearchRequestInput {
        let target: ElementSearchTarget

        @ButtonHeistActor
        init(_ request: [String: Any], fence: TheFence) throws {
            target = ElementSearchTarget(
                elementTarget: try fence.requiredElementTarget(request, command: .elementSearch),
                direction: try request.schemaEnum("direction", as: ScrollSearchDirection.self) { $0.lowercased() }
            )
        }
    }

    struct ScrollToEdgeRequestInput {
        let target: ScrollToEdgeTarget

        @ButtonHeistActor
        init(_ request: [String: Any], fence: TheFence) throws {
            let edge = try request.schemaEnum("edge", as: ScrollEdge.self) { $0.lowercased() } ?? .top
            target = ScrollToEdgeTarget(
                elementTarget: try fence.decodedElementTarget(request),
                containerTarget: try fence.decodedScrollContainerTarget(request),
                edge: edge
            )
        }
    }

    struct ActivateRequestInput {
        let payload: AccessibilityPayload

        @ButtonHeistActor
        init(_ request: [String: Any], fence: TheFence) throws {
            let target = try fence.requiredElementTarget(request, command: .activate)
            let count = try CountArgument(request)
            payload = .activate(
                target,
                actionName: try request.schemaString("action"),
                count: count
            )
        }
    }

    struct IncrementRequestInput {
        let payload: AccessibilityPayload

        @ButtonHeistActor
        init(_ request: [String: Any], fence: TheFence) throws {
            let target = try fence.requiredElementTarget(request, command: .increment)
            payload = .increment(target, count: try CountArgument(request))
        }
    }

    struct DecrementRequestInput {
        let payload: AccessibilityPayload

        @ButtonHeistActor
        init(_ request: [String: Any], fence: TheFence) throws {
            let target = try fence.requiredElementTarget(request, command: .decrement)
            payload = .decrement(target, count: try CountArgument(request))
        }
    }

    struct PerformCustomActionRequestInput {
        let payload: AccessibilityPayload

        @ButtonHeistActor
        init(_ request: [String: Any], fence: TheFence) throws {
            let target = try fence.requiredElementTarget(request, command: .performCustomAction)
            let count = try CountArgument(request)
            payload = .performCustomAction(
                target,
                actionName: try request.requiredSchemaString("action"),
                count: count
            )
        }
    }

    struct RotorRequestInput {
        let target: RotorTarget

        @ButtonHeistActor
        init(_ request: [String: Any], fence: TheFence) throws {
            let elementTarget = try fence.requiredElementTarget(request, command: .rotor)
            let rotorIndex = try request.schemaInteger("rotorIndex")
            if let rotorIndex, rotorIndex < 0 {
                throw SchemaValidationError(field: "rotorIndex", observed: rotorIndex, expected: "integer >= 0")
            }

            let currentTextStartOffset = try request.schemaInteger("currentTextStartOffset")
            let currentTextEndOffset = try request.schemaInteger("currentTextEndOffset")
            if (currentTextStartOffset == nil) != (currentTextEndOffset == nil) {
                throw FenceError.invalidRequest("currentTextStartOffset and currentTextEndOffset must be provided together")
            }

            let currentTextRange: TextRangeReference?
            let requiredCurrentHeistId: String?
            if let startOffset = currentTextStartOffset, let endOffset = currentTextEndOffset {
                guard let currentHeistId = try request.schemaString("currentHeistId") else {
                    throw SchemaValidationError(field: "currentHeistId", observed: nil, expected: "string")
                }
                guard startOffset >= 0, endOffset >= startOffset else {
                    throw SchemaValidationError(
                        field: "currentTextStartOffset/currentTextEndOffset",
                        observed: "\(startOffset)..<\(endOffset)",
                        expected: "integer range with start >= 0 and end >= start"
                    )
                }
                currentTextRange = TextRangeReference(startOffset: startOffset, endOffset: endOffset)
                requiredCurrentHeistId = currentHeistId
            } else {
                currentTextRange = nil
                requiredCurrentHeistId = nil
            }

            let rotor = try request.schemaString("rotor")
            let direction = try request.schemaEnum("direction", as: RotorDirection.self) { $0.lowercased() } ?? .next
            let currentHeistId = if let requiredCurrentHeistId {
                requiredCurrentHeistId
            } else {
                try request.schemaString("currentHeistId")
            }

            target = RotorTarget(
                elementTarget: elementTarget,
                rotor: rotor,
                rotorIndex: rotorIndex,
                direction: direction,
                currentHeistId: currentHeistId,
                currentTextRange: currentTextRange
            )
        }
    }

    struct TypeTextRequestInput {
        let target: TypeTextTarget

        @ButtonHeistActor
        init(_ request: [String: Any], fence: TheFence) throws {
            let text = try request.requiredSchemaString("text")
            if text.isEmpty {
                throw SchemaValidationError(field: "text", observed: text as Any, expected: "non-empty string")
            }
            target = TypeTextTarget(
                text: text,
                elementTarget: try fence.decodedElementTarget(request)
            )
        }
    }

    struct EditActionRequestInput {
        let target: EditActionTarget

        init(_ request: [String: Any]) throws {
            target = EditActionTarget(
                action: try request.requiredSchemaEnum("action", as: EditAction.self)
            )
        }
    }

    struct SetPasteboardRequestInput {
        let target: SetPasteboardTarget

        init(_ request: [String: Any]) throws {
            target = SetPasteboardTarget(
                text: try request.requiredSchemaString("text")
            )
        }
    }

    struct WaitForRequestInput {
        let target: WaitForTarget

        @ButtonHeistActor
        init(_ request: [String: Any], fence: TheFence) throws {
            target = WaitForTarget(
                elementTarget: try fence.requiredElementTarget(request, command: .waitFor),
                absent: try request.schemaBoolean("absent"),
                timeout: try request.schemaNumber("timeout")
            )
        }
    }
}

private extension TheFence.CountArgument {

    init(_ request: [String: Any]) throws {
        self.init(
            value: try request.schemaInteger("count"),
            observed: request["count"]
        )
    }
}
