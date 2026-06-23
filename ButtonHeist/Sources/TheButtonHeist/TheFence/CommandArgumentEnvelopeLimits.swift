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
        try validateObjectKeyCount(arguments.argumentValues, field: field, maxObjectKeys: maxObjectKeys)
        let byteCount = try jsonEncodedSize(
            of: arguments.argumentValues,
            field: field,
            maxBytes: maxBytes,
            maxDepth: maxDepth
        )
        guard byteCount <= maxBytes else {
            throw SchemaValidationError(
                field: field,
                observed: "\(byteCount) bytes",
                expected: "JSON request <= \(maxBytes) bytes"
            )
        }
    }

    private static func validateObjectKeyCount(
        _ object: [String: HeistValue],
        field: String,
        maxObjectKeys: Int
    ) throws {
        var keyCount = 0
        try countObjectKeys(in: object, field: field, maxObjectKeys: maxObjectKeys, count: &keyCount)
    }

    private static func countObjectKeys(
        in object: [String: HeistValue],
        field: String,
        maxObjectKeys: Int,
        count: inout Int
    ) throws {
        count += object.count
        guard count <= maxObjectKeys else {
            throw SchemaValidationError(
                field: field,
                observed: "object key count \(count)",
                expected: "object key count <= \(maxObjectKeys)"
            )
        }

        for value in object.values {
            try countObjectKeys(
                in: value,
                field: field,
                maxObjectKeys: maxObjectKeys,
                count: &count
            )
        }
    }

    private static func countObjectKeys(
        in value: HeistValue,
        field: String,
        maxObjectKeys: Int,
        count: inout Int
    ) throws {
        switch value {
        case .object(let object):
            try countObjectKeys(in: object, field: field, maxObjectKeys: maxObjectKeys, count: &count)
        case .array(let array):
            for item in array {
                try countObjectKeys(in: item, field: field, maxObjectKeys: maxObjectKeys, count: &count)
            }
        case .string, .bool, .int, .double:
            return
        }
    }

    private static func jsonEncodedSize(
        of object: [String: HeistValue],
        field: String,
        maxBytes: Int,
        maxDepth: Int,
        depth: Int = 1
    ) throws -> Int {
        try validateDepth(depth, field: field, maxDepth: maxDepth)

        var size = 2
        for (index, entry) in object.enumerated() {
            if index > 0 { size = try bounded(size + 1, field: field, maxBytes: maxBytes) }
            size = try bounded(size + jsonStringEncodedSize(entry.key) + 1, field: field, maxBytes: maxBytes)
            let valueSize = try jsonEncodedSize(
                of: entry.value,
                field: field,
                maxBytes: maxBytes,
                maxDepth: maxDepth,
                depth: depth + 1
            )
            size = try bounded(size + valueSize, field: field, maxBytes: maxBytes)
        }
        return size
    }

    private static func jsonEncodedSize(
        of value: HeistValue,
        field: String,
        maxBytes: Int,
        maxDepth: Int,
        depth: Int
    ) throws -> Int {
        try validateDepth(depth, field: field, maxDepth: maxDepth)

        switch value {
        case .object(let object):
            return try jsonEncodedSize(
                of: object,
                field: field,
                maxBytes: maxBytes,
                maxDepth: maxDepth,
                depth: depth
            )

        case .array(let array):
            var size = 2
            for (index, item) in array.enumerated() {
                if index > 0 { size = try bounded(size + 1, field: field, maxBytes: maxBytes) }
                let itemSize = try jsonEncodedSize(
                    of: item,
                    field: field,
                    maxBytes: maxBytes,
                    maxDepth: maxDepth,
                    depth: depth + 1
                )
                size = try bounded(size + itemSize, field: field, maxBytes: maxBytes)
            }
            return size

        case .string(let string):
            return try bounded(jsonStringEncodedSize(string), field: field, maxBytes: maxBytes)

        case .bool(let bool):
            return bool ? 4 : 5

        case .int(let number):
            return try bounded(String(number).utf8.count, field: field, maxBytes: maxBytes)

        case .double(let number):
            guard number.isFinite else {
                throw SchemaValidationError(field: field, observed: number, expected: "finite JSON number")
            }
            return try bounded(String(number).utf8.count, field: field, maxBytes: maxBytes)
        }
    }

    private static func validateDepth(_ depth: Int, field: String, maxDepth: Int) throws {
        guard depth <= maxDepth else {
            throw SchemaValidationError(
                field: field,
                observed: "nesting depth \(depth)",
                expected: "nesting depth <= \(maxDepth)"
            )
        }
    }

    private static func bounded(_ size: Int, field: String, maxBytes: Int) throws -> Int {
        guard size <= maxBytes else {
            throw SchemaValidationError(
                field: field,
                observed: "\(size) bytes",
                expected: "JSON request <= \(maxBytes) bytes"
            )
        }
        return size
    }

    private static func jsonStringEncodedSize(_ value: String) -> Int {
        var size = 2
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22, 0x5C:
                size += 2
            case 0x00...0x1F:
                size += 6
            default:
                size += scalar.utf8.count
            }
        }
        return size
    }
}
