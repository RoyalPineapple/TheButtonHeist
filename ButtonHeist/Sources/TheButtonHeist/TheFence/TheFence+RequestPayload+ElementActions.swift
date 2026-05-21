import Foundation

import TheScore

extension TheFence {

    func decodeElementActionPayload(
        command: Command,
        request: [String: Any]
    ) throws -> RequestPayload {
        switch command {
        case .scroll, .scrollToVisible, .elementSearch, .scrollToEdge:
            return .scroll(try decodeScrollPayload(command: command, request: request))
        case .activate, .increment, .decrement, .performCustomAction:
            return .accessibility(try decodeAccessibilityPayload(command: command, request: request))
        case .rotor:
            return .rotor(try decodeRotorTarget(request))
        case .typeText:
            return .typeText(try decodeTypeTextTarget(request))
        case .editAction:
            return .editAction(EditActionTarget(
                action: try request.requiredSchemaEnum("action", as: EditAction.self)
            ))
        case .setPasteboard:
            return .setPasteboard(SetPasteboardTarget(
                text: try request.requiredSchemaString("text")
            ))
        case .waitFor:
            return .waitFor(try decodeWaitForTarget(request))
        default:
            throw FenceError.invalidRequest("Unexpected element action command: \(command.rawValue)")
        }
    }

    private func decodeScrollPayload(
        command: Command,
        request: [String: Any]
    ) throws -> ScrollPayload {
        switch command {
        case .scroll:
            let direction = try request.requiredSchemaEnum("direction", as: ScrollDirection.self) { $0.lowercased() }
            return .scroll(ScrollTarget(
                elementTarget: try requiredElementTarget(request, command: command),
                direction: direction
            ))
        case .scrollToVisible:
            return .scrollToVisible(ScrollToVisibleTarget(
                elementTarget: try requiredElementTarget(request, command: command)
            ))
        case .elementSearch:
            return .elementSearch(ElementSearchTarget(
                elementTarget: try requiredElementTarget(request, command: command),
                direction: try request.schemaEnum("direction", as: ScrollSearchDirection.self) { $0.lowercased() }
            ))
        case .scrollToEdge:
            let edge = try request.requiredSchemaEnum("edge", as: ScrollEdge.self) { $0.lowercased() }
            return .scrollToEdge(ScrollToEdgeTarget(
                elementTarget: try requiredElementTarget(request, command: command),
                edge: edge
            ))
        default:
            throw FenceError.invalidRequest("Unexpected scroll command: \(command.rawValue)")
        }
    }

    private func decodeAccessibilityPayload(
        command: Command,
        request: [String: Any]
    ) throws -> AccessibilityPayload {
        let target = try requiredElementTarget(request, command: command)
        let count = CountArgument(
            value: try request.schemaInteger("count"),
            observed: request["count"]
        )
        switch command {
        case .activate:
            return .activate(
                target,
                actionName: try request.schemaString("action"),
                count: count
            )
        case .increment:
            return .increment(target, count: count)
        case .decrement:
            return .decrement(target, count: count)
        case .performCustomAction:
            return .performCustomAction(
                target,
                actionName: try request.requiredSchemaString("action"),
                count: count
            )
        default:
            throw FenceError.invalidRequest("Unexpected accessibility command: \(command.rawValue)")
        }
    }

    private func decodeRotorTarget(_ request: [String: Any]) throws -> RotorTarget {
        let target = try requiredElementTarget(request, command: .rotor)
        if let rotorIndex = try request.schemaInteger("rotorIndex"), rotorIndex < 0 {
            throw SchemaValidationError(field: "rotorIndex", observed: rotorIndex, expected: "integer >= 0")
        }
        let currentTextStartOffset = try request.schemaInteger("currentTextStartOffset")
        let currentTextEndOffset = try request.schemaInteger("currentTextEndOffset")
        if (currentTextStartOffset == nil) != (currentTextEndOffset == nil) {
            throw FenceError.invalidRequest("currentTextStartOffset and currentTextEndOffset must be provided together")
        }
        let currentTextRange: TextRangeReference?
        if let startOffset = currentTextStartOffset, let endOffset = currentTextEndOffset {
            guard try request.schemaString("currentHeistId") != nil else {
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
        } else {
            currentTextRange = nil
        }

        return RotorTarget(
            elementTarget: target,
            rotor: try request.schemaString("rotor"),
            rotorIndex: try request.schemaInteger("rotorIndex"),
            direction: try request.schemaEnum("direction", as: RotorDirection.self) { $0.lowercased() } ?? .next,
            currentHeistId: try request.schemaString("currentHeistId"),
            currentTextRange: currentTextRange
        )
    }

    private func decodeTypeTextTarget(_ request: [String: Any]) throws -> TypeTextTarget {
        let text = try request.requiredSchemaString("text")
        if text.isEmpty {
            throw SchemaValidationError(field: "text", observed: text as Any, expected: "non-empty string")
        }
        return TypeTextTarget(
            text: text,
            elementTarget: try decodedElementTarget(request)
        )
    }

    private func decodeWaitForTarget(_ request: [String: Any]) throws -> WaitForTarget {
        let target = try requiredElementTarget(request, command: .waitFor)
        return WaitForTarget(
            elementTarget: target,
            absent: try request.schemaBoolean("absent"),
            timeout: try request.schemaNumber("timeout")
        )
    }

    func decodedElementTarget(_ request: [String: Any]) throws -> ElementTarget? {
        _ = try elementTargetOrdinal(request)
        return try elementTarget(request)
    }

    func requiredElementTarget(_ request: [String: Any], command: Command) throws -> ElementTarget {
        guard let target = try decodedElementTarget(request) else {
            throw MissingElementTarget(command: command.rawValue)
        }
        return target
    }

    private func elementTargetOrdinal(_ request: [String: Any]) throws -> Int? {
        guard let ordinal = try request.schemaInteger("ordinal") else { return nil }
        guard ordinal >= 0 else {
            throw SchemaValidationError(field: "ordinal", observed: ordinal, expected: "integer >= 0")
        }
        return ordinal
    }

    func elementTarget(_ dictionary: [String: Any]) throws -> ElementTarget? {
        ElementTarget(
            heistId: try dictionary.schemaString("heistId"),
            matcher: try elementMatcher(dictionary),
            ordinal: try dictionary.schemaInteger("ordinal")
        )
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
