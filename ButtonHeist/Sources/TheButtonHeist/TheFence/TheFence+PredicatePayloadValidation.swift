import Foundation
import TheScore

extension TheFence {
    nonisolated static func validateElementPredicatePayloadStringMatches(_ value: HeistValue, field: String) throws {
        guard case .object(let object) = value else { return }
        for key in ["label", "identifier", "value"] {
            guard let match = object[key] else { continue }
            guard isStrictStringMatchObjectOrArray(match) else {
                throw SchemaValidationError(
                    field: "\(field).\(key)",
                    observed: match.schemaObservedDescription,
                    expected: "StringMatch object with mode and value, or array of StringMatch objects"
                )
            }
        }
        if let checks = object["checks"] {
            try validateElementPredicateChecks(checks, field: "\(field).checks")
        }
    }

    nonisolated static func validateElementPredicateChecks(_ value: HeistValue, field: String) throws {
        guard case .array(let checks) = value else {
            throw SchemaValidationError(
                field: field,
                observed: value.schemaObservedDescription,
                expected: "array of element predicate check objects"
            )
        }
        for (index, check) in checks.enumerated() {
            guard case .object(let object) = check else {
                throw SchemaValidationError(
                    field: "\(field)[\(index)]",
                    observed: check.schemaObservedDescription,
                    expected: "element predicate check object"
                )
            }
            guard let kind = object["kind"] else {
                throw SchemaValidationError(
                    field: "\(field)[\(index)].kind",
                    observed: "missing",
                    expected: SchemaValidationError.expectedEnumValues(elementPredicateCheckKinds)
                )
            }
            guard case .string(let kindName) = kind else {
                throw SchemaValidationError(
                    field: "\(field)[\(index)].kind",
                    observed: kind.schemaObservedDescription,
                    expected: SchemaValidationError.expectedEnumValues(elementPredicateCheckKinds)
                )
            }
            switch kindName {
            case "label", "identifier", "value":
                try rejectFieldIfPresent(
                    "values",
                    in: object,
                    field: "\(field)[\(index)].values",
                    expected: "not present for \(kindName) checks"
                )
                guard let match = object["match"] else {
                    throw SchemaValidationError(
                        field: "\(field)[\(index)].match",
                        observed: "missing",
                        expected: "StringMatch object with mode and value"
                    )
                }
                guard isStrictStringMatchObject(match) else {
                    throw SchemaValidationError(
                        field: "\(field)[\(index)].match",
                        observed: match.schemaObservedDescription,
                        expected: "StringMatch object with mode and value"
                    )
                }
            case "traits", "excludeTraits":
                try rejectFieldIfPresent(
                    "match",
                    in: object,
                    field: "\(field)[\(index)].match",
                    expected: "not present for \(kindName) checks"
                )
                try validateTraitNamesValue(
                    object["values"],
                    field: "\(field)[\(index)].values"
                )
            default:
                throw SchemaValidationError(
                    field: "\(field)[\(index)].kind",
                    observed: "string \"\(kindName)\"",
                    expected: SchemaValidationError.expectedEnumValues(elementPredicateCheckKinds)
                )
            }
        }
    }

    private nonisolated static var elementPredicateCheckKinds: [String] {
        ["label", "identifier", "value", "traits", "excludeTraits"]
    }

    private nonisolated static func rejectFieldIfPresent(
        _ key: String,
        in object: [String: HeistValue],
        field: String,
        expected: String
    ) throws {
        guard let value = object[key] else { return }
        throw SchemaValidationError(
            field: field,
            observed: value.schemaObservedDescription,
            expected: expected
        )
    }

    private nonisolated static func validateTraitNamesValue(_ value: HeistValue?, field: String) throws {
        guard let value else {
            throw SchemaValidationError(
                field: field,
                observed: "missing",
                expected: "array of trait names"
            )
        }
        guard case .array(let values) = value else {
            throw SchemaValidationError(
                field: field,
                observed: value.schemaObservedDescription,
                expected: "array of trait names"
            )
        }
        for (index, item) in values.enumerated() {
            guard case .string(let name) = item else {
                throw SchemaValidationError(
                    field: "\(field)[\(index)]",
                    observed: item.schemaObservedDescription,
                    expected: "trait name"
                )
            }
            guard HeistTrait(rawValue: name) != nil else {
                throw SchemaValidationError(
                    field: "\(field)[\(index)]",
                    observed: "string \"\(name)\"",
                    expected: SchemaValidationError.expectedEnum(HeistTrait.self)
                )
            }
        }
    }

    nonisolated static func isStrictStringMatchObjectOrArray(_ value: HeistValue) -> Bool {
        switch value {
        case .object:
            return true
        case .array(let values):
            return values.allSatisfy(isStrictStringMatchObject)
        default:
            return false
        }
    }

    nonisolated static func isStrictStringMatchObject(_ value: HeistValue) -> Bool {
        if case .object = value { return true }
        return false
    }
}
