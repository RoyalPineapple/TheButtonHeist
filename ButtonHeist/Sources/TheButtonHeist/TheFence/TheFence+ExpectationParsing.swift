import Foundation

import TheScore

extension TheFence {

    // MARK: - Expectation Parsing

    /// Parse the `"expect"` field off a CLI/MCP request dictionary into a typed
    /// `ActionExpectation`. Returns `nil` when no expectation is set. The
    /// accepted shape is the discriminator object used by `ActionExpectation`'s
    /// wire encoding: `{"type": "...", …}`. Compound expectations use the same
    /// object form with `{"type": "compound", "expectations": [...]}`.
    func parseExpectation(_ dictionary: [String: Any]) throws -> ActionExpectation? {
        guard let expect = dictionary["expect"] else { return nil }
        if let dict = expect as? [String: Any] {
            return try parseSingleExpectation(dict)
        }
        throw FenceError.invalidRequest(
            "Invalid expectation type: expected object with a \"type\" discriminator"
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
        switch typeString {
        case "screen_changed":
            return .screenChanged
        case "elements_changed":
            return .elementsChanged
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
            let sub = try expectationsArray.map { value -> ActionExpectation in
                guard let dict = value as? [String: Any] else {
                    throw FenceError.invalidRequest(
                        "compound expectations must be objects with a \"type\" discriminator"
                    )
                }
                return try parseSingleExpectation(dict)
            }
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
