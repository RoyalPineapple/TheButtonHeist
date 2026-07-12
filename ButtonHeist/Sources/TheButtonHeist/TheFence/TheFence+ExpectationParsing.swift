import Foundation
import ThePlans
import TheScore

extension TheFence {

    struct ExpectationPayload: Sendable {
        let expectation: AccessibilityPredicate<RootContext>?
        let timeout: Double?

        init(expectation: AccessibilityPredicate<RootContext>?, timeout: Double?) {
            self.expectation = expectation
            self.timeout = timeout
        }

        init(arguments: CommandArgumentEnvelope) throws {
            self.init(
                expectation: try Self.parseExpectation(arguments.value(for: .expect)),
                timeout: try arguments.value(FenceParameters.timeout)
            )
        }

        var postActionValidationTimeout: Double? {
            expectation == nil ? nil : timeout ?? defaultActionExpectationTimeout
        }

        static func parseExpectation(_ value: HeistValue?) throws -> AccessibilityPredicate<RootContext>? {
            guard let value else { return nil }
            return try parsePredicate(value)
        }

        /// Parse a required `AccessibilityPredicate` object (the `wait`
        /// `predicate` field). Throws if missing or malformed.
        static func parseRequiredPredicate(_ value: HeistValue?) throws -> AccessibilityPredicate<RootContext> {
            guard let value else {
                throw FenceError.invalidRequest("wait requires a \"predicate\" object")
            }
            return try parsePredicate(value)
        }

        static func parsePredicate(_ value: HeistValue) throws -> AccessibilityPredicate<RootContext> {
            guard case .object(let object) = value else {
                throw FenceError.invalidRequest(
                    "Invalid predicate type: expected object with a \"type\" discriminator"
                )
            }
            guard let type = object["type"] else {
                throw FenceError.invalidRequest(
                    "Predicate object requires a \"type\" discriminator " +
                        "(e.g. {\"type\": \"exists\", …}). " +
                        "Got keys: \(object.keys.sorted())"
                )
            }
            guard case .string = type else {
                throw FenceError.invalidRequest(
                    "Predicate object requires a string \"type\" discriminator " +
                        "(e.g. {\"type\": \"exists\", …}). " +
                        "Got type: \(type.schemaObservedDescription)"
                )
            }
            try validatePredicateStringMatchObjects(value, path: [])
            let predicate = try TheFence.HeistValuePayloadDecoder.decode(
                value,
                field: "expect",
                as: AccessibilityPredicate<RootContext>.self,
                includesRootInField: false,
                dataCorruptedHandling: .invalidRequest
            )
            return try predicate.resolve(in: .empty)
        }

        private static func validatePredicateStringMatchObjects(_ value: HeistValue, path: [String]) throws {
            guard case .object(let object) = value else { return }
            if let target = object["target"] {
                try validateAccessibilityTargetStringMatchObjects(target, path: path + ["target"])
            }
            if let match = object["match"] {
                try TheFence.validateStringMatchObject(match, field: (path + ["match"]).joined(separator: "."))
            }
            if let assertions = object["assertions"], case .array(let values) = assertions {
                for (index, child) in values.enumerated() {
                    try validatePredicateStringMatchObjects(child, path: path + ["assertions[\(index)]"])
                }
            }
        }

        private static func validateAccessibilityTargetStringMatchObjects(_ value: HeistValue, path: [String]) throws {
            try TheFence.validateElementPredicatePayloadStringMatches(
                value,
                field: path.joined(separator: ".")
            )
            guard case .object(let object) = value,
                  let nested = object["target"] else { return }
            try validateAccessibilityTargetStringMatchObjects(nested, path: path + ["target"])
        }

    }

    // MARK: - Expectation Parsing

    /// Parse compact command input into the same typed expectation argument
    /// shape accepted by direct, MCP, batch, and heist request decoding.
    public nonisolated static func parseExpectationArgument(_ rawValue: String) throws -> HeistValue {
        do {
            return try PublicJSONInputDecoder.decodeHeistValue(
                from: rawValue,
                root: .object,
                context: "Expectation JSON",
                rootMismatchMessage: "Expected expectation JSON object"
            )
        } catch let error as PublicJSONInputError {
            throw FenceError.invalidRequest(error.message)
        } catch {
            throw FenceError.invalidRequest("Invalid expectation JSON: \(error.localizedDescription)")
        }
    }
}
