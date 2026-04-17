import Foundation

import TheScore

extension TheFence {

    // MARK: - Expectation Parsing

    /// Parse the `"expect"` field off a CLI/MCP request dictionary into a typed
    /// `ActionExpectation`. Returns `nil` when no expectation is set. Supports a
    /// single string tier, a single object (discriminator or legacy), or an array
    /// (compound).
    func parseExpectation(_ dictionary: [String: Any]) throws -> ActionExpectation? {
        guard let expect = dictionary["expect"] else { return nil }
        if let array = expect as? [[String: Any]] {
            let sub = try array.map { try parseSingleExpectation($0) }
            return sub.count == 1 ? sub[0] : .compound(sub)
        }
        if let array = expect as? [Any] {
            let sub = try array.map { try parseSingleExpectationValue($0) }
            return sub.count == 1 ? sub[0] : .compound(sub)
        }
        return try parseSingleExpectationValue(expect)
    }

    private func parseSingleExpectationValue(_ expect: Any) throws -> ActionExpectation {
        if let str = expect as? String {
            guard let tier = ExpectationTier(rawValue: str) else {
                let validTiers = ExpectationTier.allCases.map(\.rawValue).joined(separator: ", ")
                throw FenceError.invalidRequest(
                    "Unknown expectation tier: \"\(str)\". " +
                    "Valid: \(validTiers), or {\"type\": \"element_updated\", …}"
                )
            }
            return tier.expectation
        }
        if let dict = expect as? [String: Any] {
            return try parseSingleExpectation(dict)
        }
        throw FenceError.invalidRequest(
            "Invalid expectation type: expected string, object, or array"
        )
    }

    /// Accepts two shapes for backwards compatibility:
    ///   - Wire discriminator: `{"type": "element_updated", "heistId": …}` — matches
    ///     `ActionExpectation`'s Codable encoding. Preferred; lets callers copy JSON
    ///     straight from a wire log into a CLI arg.
    ///   - Legacy nested-key: `{"elementUpdated": {…}}` — the original CLI shape.
    private func parseSingleExpectation(_ dict: [String: Any]) throws -> ActionExpectation {
        if let typeString = dict["type"] as? String {
            return try parseDiscriminatedExpectation(type: typeString, dict: dict)
        }
        return try parseLegacyExpectation(dict)
    }

    private func parseDiscriminatedExpectation(
        type typeString: String, dict: [String: Any]
    ) throws -> ActionExpectation {
        if let tier = ExpectationTier(rawValue: typeString) {
            return tier.expectation
        }
        switch typeString {
        case "element_updated":
            return .elementUpdated(
                heistId: dict["heistId"] as? String,
                property: try parseElementProperty(dict["property"] as? String),
                oldValue: dict["oldValue"] as? String,
                newValue: dict["newValue"] as? String
            )
        case "element_appeared":
            guard let matcherDict = dict["matcher"] as? [String: Any] else {
                throw FenceError.invalidRequest(
                    "element_appeared requires a \"matcher\" object"
                )
            }
            return .elementAppeared(try elementMatcher(matcherDict))
        case "element_disappeared":
            guard let matcherDict = dict["matcher"] as? [String: Any] else {
                throw FenceError.invalidRequest(
                    "element_disappeared requires a \"matcher\" object"
                )
            }
            return .elementDisappeared(try elementMatcher(matcherDict))
        case "compound":
            guard let expectationsArray = dict["expectations"] as? [Any] else {
                throw FenceError.invalidRequest(
                    "compound requires an \"expectations\" array"
                )
            }
            let sub = try expectationsArray.map { try parseSingleExpectationValue($0) }
            return .compound(sub)
        default:
            let validTypes = "screen_changed, elements_changed, element_updated, " +
                "element_appeared, element_disappeared, compound"
            throw FenceError.invalidRequest(
                "Unknown expectation type: \"\(typeString)\". Valid: \(validTypes)"
            )
        }
    }

    private func parseLegacyExpectation(_ dict: [String: Any]) throws -> ActionExpectation {
        if let eu = dict["elementUpdated"] as? [String: Any] {
            return .elementUpdated(
                heistId: eu["heistId"] as? String,
                property: try parseElementProperty(eu["property"] as? String),
                oldValue: eu["oldValue"] as? String,
                newValue: eu["newValue"] as? String
            )
        }
        if dict.keys.contains("elementUpdated") {
            return .elementUpdated()
        }
        if let matcherDict = dict["elementAppeared"] as? [String: Any] {
            return .elementAppeared(try elementMatcher(matcherDict))
        }
        if let matcherDict = dict["elementDisappeared"] as? [String: Any] {
            return .elementDisappeared(try elementMatcher(matcherDict))
        }
        throw FenceError.invalidRequest(
            "Invalid expectation object: expected a \"type\" discriminator " +
            "(e.g. {\"type\": \"element_updated\", …}) or legacy nested key " +
            "(elementUpdated, elementAppeared, elementDisappeared). " +
            "Got keys: \(dict.keys.sorted())"
        )
    }

    private func parseElementProperty(_ string: String?) throws -> ElementProperty? {
        guard let string else { return nil }
        guard let property = ElementProperty(rawValue: string) else {
            throw FenceError.invalidRequest(
                "Unknown element property: \"\(string)\". " +
                "Valid: \(ElementProperty.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        return property
    }
}
