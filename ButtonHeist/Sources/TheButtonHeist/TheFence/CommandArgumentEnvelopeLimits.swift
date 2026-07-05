import Foundation

import TheScore

enum CommandArgumentEnvelopeLimits {

    static func validateRunHeist(_ arguments: TheFence.CommandArgumentEnvelope) throws {
        try validateHeistPlanSource(arguments, field: "run_heist")
    }

    static func validateHeistPlanSource(
        _ arguments: TheFence.CommandArgumentEnvelope,
        field: String
    ) throws {
        try validate(
            arguments,
            field: field,
            maxBytes: TheFence.DecodeLimits.maxRunHeistRequestBytes,
            maxDepth: TheFence.DecodeLimits.maxRunHeistNestingDepth,
            maxObjectKeys: TheFence.DecodeLimits.maxRunHeistObjectKeys
        )
    }

    static func validate(
        _ arguments: TheFence.CommandArgumentEnvelope,
        field: String,
        maxBytes: Int,
        maxDepth: Int,
        maxObjectKeys: Int
    ) throws {
        try PublicJSONValuePreflight.validateObject(
            arguments.values,
            policy: PublicJSONInputPolicy(
                maxBytes: maxBytes,
                maxNestingDepth: maxDepth,
                maxTotalObjectKeys: maxObjectKeys
            ),
            makeError: { schemaValidationError(field: field, violation: $0) },
            node: jsonValueNode
        )
    }

    private static func jsonValueNode(_ value: HeistValue) -> PublicJSONValueNode<HeistValue> {
        switch value {
        case .string(let string):
            return .string(string)
        case .bool(let bool):
            return .bool(bool)
        case .int(let number):
            return .int(number)
        case .double(let number):
            return .double(number)
        case .array(let array):
            return .array(array)
        case .object(let object):
            return .object(object)
        }
    }

    private static func schemaValidationError(
        field: String,
        violation: PublicJSONInputViolation
    ) -> SchemaValidationError {
        switch violation {
        case .bytes(let max, let observed):
            return SchemaValidationError(
                field: field,
                observed: "\(observed) bytes",
                expected: "JSON request <= \(max) bytes"
            )
        case .nestingDepth(let max, let observed):
            return SchemaValidationError(
                field: field,
                observed: "nesting depth \(observed)",
                expected: "nesting depth <= \(max)"
            )
        case .objectKeyCount(let max, let observed):
            return SchemaValidationError(
                field: field,
                observed: "object key count \(observed)",
                expected: "object key count <= \(max)"
            )
        case .arrayValueCount(let max, let observed):
            return SchemaValidationError(
                field: field,
                observed: "array value count \(observed)",
                expected: "array value count <= \(max)"
            )
        case .stringBytes(let max, let observed):
            return SchemaValidationError(
                field: field,
                observed: "\(observed) string bytes",
                expected: "string bytes <= \(max)"
            )
        case .nullValue(let expected):
            return SchemaValidationError(field: field, observed: "null", expected: expected)
        case .nonFiniteNumber(let observed):
            return SchemaValidationError(field: field, observed: observed, expected: "finite JSON number")
        }
    }
}
