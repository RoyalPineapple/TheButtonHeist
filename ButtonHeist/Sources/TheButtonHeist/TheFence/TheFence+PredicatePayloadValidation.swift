import Foundation
import ThePlans
import TheScore

extension TheFence {
    nonisolated static func validateElementPredicatePayloadStringMatches(_ value: HeistValue, field: String) throws {
        guard case .object(let object) = value else { return }
        for key in ["label", "identifier", "value", "hint"] {
            guard let match = object[key] else { continue }
            try validateStringMatchObjectOrArray(match, field: "\(field).\(key)")
        }
        for key in ["customContent"] {
            guard let match = object[key] else { continue }
            try validateCustomContentMatchObject(match, field: "\(field).\(key)")
        }
        for key in ["rotors"] {
            guard let match = object[key] else { continue }
            try validateStringMatchArray(match, field: "\(field).\(key)")
        }
        if let actions = object["actions"] {
            try validateElementActionsValue(actions, field: "\(field).actions")
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
            try validateElementPredicateCheck(check, field: "\(field)[\(index)]")
        }
    }

    nonisolated static func validateElementPredicateCheck(_ check: HeistValue, field: String) throws {
        guard case .object(let object) = check else {
            throw SchemaValidationError(
                field: field,
                observed: check.schemaObservedDescription,
                expected: "element predicate check object"
            )
        }
        guard let kind = object["kind"] else {
            throw SchemaValidationError(
                field: "\(field).kind",
                observed: "missing",
                expected: SchemaValidationError.expectedEnum(ElementPredicateCheck<String>.Kind.self)
            )
        }
        guard case .string(let kindName) = kind else {
            throw SchemaValidationError(
                field: "\(field).kind",
                observed: kind.schemaObservedDescription,
                expected: SchemaValidationError.expectedEnum(ElementPredicateCheck<String>.Kind.self)
            )
        }
        guard let checkKind = ElementPredicateCheck<String>.Kind(rawValue: kindName) else {
            throw SchemaValidationError(
                field: "\(field).kind",
                observed: "string \"\(kindName)\"",
                expected: SchemaValidationError.expectedEnum(ElementPredicateCheck<String>.Kind.self)
            )
        }
        switch checkKind {
        case .label, .identifier, .value, .hint:
            try rejectFieldIfPresent("values", in: object, field: "\(field).values", expected: "not present for \(checkKind.rawValue) checks")
            try rejectFieldIfPresent("check", in: object, field: "\(field).check", expected: "not present for \(checkKind.rawValue) checks")
            guard let match = object["match"] else {
                throw SchemaValidationError(field: "\(field).match", observed: "missing", expected: "StringMatch object with mode and optional value")
            }
            try validateStringMatchObject(match, field: "\(field).match")
        case .traits:
            try rejectFieldIfPresent("match", in: object, field: "\(field).match", expected: "not present for traits checks")
            try rejectFieldIfPresent("check", in: object, field: "\(field).check", expected: "not present for traits checks")
            try validateTraitNamesValue(object["values"], field: "\(field).values")
        case .actions:
            try rejectFieldIfPresent("match", in: object, field: "\(field).match", expected: "not present for actions checks")
            try rejectFieldIfPresent("check", in: object, field: "\(field).check", expected: "not present for actions checks")
            try validateElementActionsValue(object["values"], field: "\(field).values")
        case .customContent:
            try rejectFieldIfPresent("values", in: object, field: "\(field).values", expected: "not present for customContent checks")
            try rejectFieldIfPresent("check", in: object, field: "\(field).check", expected: "not present for customContent checks")
            guard let match = object["match"] else {
                throw SchemaValidationError(field: "\(field).match", observed: "missing", expected: "custom content match object")
            }
            try validateCustomContentMatchObject(match, field: "\(field).match")
        case .rotors:
            try rejectFieldIfPresent("match", in: object, field: "\(field).match", expected: "not present for rotors checks")
            try rejectFieldIfPresent("check", in: object, field: "\(field).check", expected: "not present for rotors checks")
            guard let values = object["values"] else {
                throw SchemaValidationError(field: "\(field).values", observed: "missing", expected: "array of StringMatch objects")
            }
            try validateStringMatchArray(values, field: "\(field).values")
        case .exclude:
            try rejectFieldIfPresent("match", in: object, field: "\(field).match", expected: "not present for exclude checks")
            try rejectFieldIfPresent("values", in: object, field: "\(field).values", expected: "not present for exclude checks")
            guard let excluded = object["check"] else {
                throw SchemaValidationError(field: "\(field).check", observed: "missing", expected: "element predicate check object")
            }
            try validateElementPredicateCheck(excluded, field: "\(field).check")
        }
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

    nonisolated static func validateElementActionsValue(_ value: HeistValue?, field: String) throws {
        guard let value else {
            throw SchemaValidationError(
                field: field,
                observed: "missing",
                expected: "array of element actions"
            )
        }
        guard case .array(let values) = value else {
            throw SchemaValidationError(
                field: field,
                observed: value.schemaObservedDescription,
                expected: "array of element actions"
            )
        }
        for (index, item) in values.enumerated() {
            try validateElementActionValue(item, field: "\(field)[\(index)]")
        }
    }

    private nonisolated static func validateElementActionValue(_ value: HeistValue, field: String) throws {
        switch value {
        case .string(let name) where ["activate", "increment", "decrement"].contains(name):
            return
        case .string(let name):
            throw SchemaValidationError(
                field: field,
                observed: "string \"\(name)\"",
                expected: "built-in action string activate|increment|decrement, or {\"custom\":\"\(name)\"}"
            )
        case .object(let object):
            let allowed = Set(["custom"])
            if let unknown = object.keys.sorted().first(where: { !allowed.contains($0) }) {
                throw SchemaValidationError(
                    field: "\(field).\(unknown)",
                    observed: object[unknown]?.schemaObservedDescription ?? "missing",
                    expected: "not present for custom action objects"
                )
            }
            guard let custom = object["custom"] else {
                throw SchemaValidationError(
                    field: "\(field).custom",
                    observed: "missing",
                    expected: "custom action name string"
                )
            }
            guard case .string(let name) = custom else {
                throw SchemaValidationError(
                    field: "\(field).custom",
                    observed: custom.schemaObservedDescription,
                    expected: "custom action name string"
                )
            }
            guard !name.isEmpty else {
                throw SchemaValidationError(
                    field: "\(field).custom",
                    observed: "string \"\"",
                    expected: "non-empty custom action name string"
                )
            }
        default:
            throw SchemaValidationError(
                field: field,
                observed: value.schemaObservedDescription,
                expected: "element action string or custom action object"
            )
        }
    }

    nonisolated static func validateCustomContentMatchObject(_ value: HeistValue, field: String) throws {
        guard case .object(let object) = value else {
            throw SchemaValidationError(
                field: field,
                observed: value.schemaObservedDescription,
                expected: "custom content match object"
            )
        }
        let allowed = Set(["label", "value", "isImportant"])
        if let unknown = object.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw SchemaValidationError(
                field: "\(field).\(unknown)",
                observed: object[unknown]?.schemaObservedDescription ?? "missing",
                expected: "label, value, or isImportant"
            )
        }
        for key in ["label", "value"] {
            guard let match = object[key] else { continue }
            try validateStringMatchObject(match, field: "\(field).\(key)")
        }
        if let isImportant = object["isImportant"],
           case .bool = isImportant {
            return
        } else if let isImportant = object["isImportant"] {
            throw SchemaValidationError(
                field: "\(field).isImportant",
                observed: isImportant.schemaObservedDescription,
                expected: "boolean"
            )
        }
    }

    nonisolated static func validateStringMatchArray(_ value: HeistValue, field: String) throws {
        guard case .array(let values) = value else {
            throw SchemaValidationError(
                field: field,
                observed: value.schemaObservedDescription,
                expected: "array of StringMatch objects"
            )
        }
        for (index, item) in values.enumerated() {
            try validateStringMatchObject(item, field: "\(field)[\(index)]")
        }
    }

    private nonisolated static func validateStringMatchObjectOrArray(_ value: HeistValue, field: String) throws {
        switch value {
        case .object:
            try validateStringMatchObject(value, field: field)
        case .array(let values):
            for (index, item) in values.enumerated() {
                try validateStringMatchObject(item, field: "\(field)[\(index)]")
            }
        default:
            throw SchemaValidationError(
                field: field,
                observed: value.schemaObservedDescription,
                expected: "StringMatch object with mode and optional value, or array of StringMatch objects"
            )
        }
    }

    private nonisolated static func validateStringMatchObject(_ value: HeistValue, field: String) throws {
        guard case .object = value else {
            throw SchemaValidationError(
                field: field,
                observed: value.schemaObservedDescription,
                expected: "StringMatch object with mode and optional value"
            )
        }
        _ = try HeistValuePayloadDecoder.decode(value, field: field, as: StrictStringMatchPayload.self)
    }
}

private struct StrictStringMatchPayload: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case mode, value
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "StringMatch")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decode(StringMatch<String>.Mode.self, forKey: .mode)
        switch mode {
        case .isEmpty:
            if container.contains(.value) {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "isEmpty string match must not include value"
                )
            }
        case .exact:
            _ = try container.decode(String.self, forKey: .value)
        case .contains, .prefix, .suffix:
            let value = try container.decode(String.self, forKey: .value)
            if value.isEmpty {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "\(mode.rawValue) string match value must not be empty"
                )
            }
        }
    }
}
