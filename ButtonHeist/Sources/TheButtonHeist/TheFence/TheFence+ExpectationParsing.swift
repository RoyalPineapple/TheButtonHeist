import Foundation

import TheScore

extension TheFence {

    // MARK: - Expectation Parsing

    /// Parse the `"expect"` field off a CLI/MCP request dictionary into a typed
    /// `ActionExpectation`. Returns `nil` when no expectation is set. Supports a
    /// short string tier (`"screen_changed"` / `"elements_changed"`), a single
    /// discriminator object (`{"type": "...", …}`), or an array (compound).
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

    /// Expects the wire discriminator shape (`{"type": "...", …}`) — matches
    /// `ActionExpectation`'s Codable encoding, so callers can paste JSON straight
    /// from a wire log into a CLI arg.
    private func parseSingleExpectation(_ dict: [String: Any]) throws -> ActionExpectation {
        guard let typeString = dict["type"] as? String else {
            throw FenceError.invalidRequest(
                "Expectation object requires a \"type\" discriminator " +
                "(e.g. {\"type\": \"element_updated\", …}). " +
                "Got keys: \(dict.keys.sorted())"
            )
        }
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
