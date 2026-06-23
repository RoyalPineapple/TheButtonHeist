import Foundation
import MCP
import ButtonHeist

enum MCPArgumentInputPreflight {
    static func validate(
        _ arguments: [String: Value]?,
        context: String = "MCP arguments",
        maxBytes: Int = PublicAdapterInputLimits.maxRequestBytes,
        maxNestingDepth: Int = PublicAdapterInputLimits.maxNestingDepth,
        maxTotalObjectKeys: Int = PublicAdapterInputLimits.maxTotalObjectKeys
    ) throws {
        var objectKeyCount = 0
        let byteCount = try jsonEncodedSize(
            of: arguments ?? [:],
            context: context,
            maxBytes: maxBytes,
            maxNestingDepth: maxNestingDepth,
            maxTotalObjectKeys: maxTotalObjectKeys,
            depth: 1,
            objectKeyCount: &objectKeyCount
        )
        guard byteCount <= maxBytes else {
            throw PublicAdapterInputError(
                "\(context) exceeds \(maxBytes) bytes (observed \(byteCount) bytes)"
            )
        }
    }

    private static func jsonEncodedSize(
        of object: [String: Value],
        context: String,
        maxBytes: Int,
        maxNestingDepth: Int,
        maxTotalObjectKeys: Int,
        depth: Int,
        objectKeyCount: inout Int
    ) throws -> Int {
        try validateDepth(depth, context: context, maxNestingDepth: maxNestingDepth)
        objectKeyCount += object.count
        guard objectKeyCount <= maxTotalObjectKeys else {
            throw PublicAdapterInputError(
                "\(context) object key count exceeds \(maxTotalObjectKeys) (observed \(objectKeyCount))"
            )
        }

        var size = 2
        for (index, entry) in object.enumerated() {
            if index > 0 { size = try bounded(size + 1, context: context, maxBytes: maxBytes) }
            size = try bounded(size + jsonStringEncodedSize(entry.key) + 1, context: context, maxBytes: maxBytes)
            let valueSize = try jsonEncodedSize(
                of: entry.value,
                context: context,
                maxBytes: maxBytes,
                maxNestingDepth: maxNestingDepth,
                maxTotalObjectKeys: maxTotalObjectKeys,
                depth: depth + 1,
                objectKeyCount: &objectKeyCount
            )
            size = try bounded(size + valueSize, context: context, maxBytes: maxBytes)
        }
        return size
    }

    private static func jsonEncodedSize(
        of value: Value,
        context: String,
        maxBytes: Int,
        maxNestingDepth: Int,
        maxTotalObjectKeys: Int,
        depth: Int,
        objectKeyCount: inout Int
    ) throws -> Int {
        try validateDepth(depth, context: context, maxNestingDepth: maxNestingDepth)

        switch value {
        case .null:
            return 4
        case .bool(let bool):
            return bool ? 4 : 5
        case .int(let int):
            return try bounded(String(int).utf8.count, context: context, maxBytes: maxBytes)
        case .double(let double):
            guard double.isFinite else {
                throw PublicAdapterInputError("\(context) contains a non-finite number")
            }
            return try bounded(String(double).utf8.count, context: context, maxBytes: maxBytes)
        case .string(let string):
            return try bounded(jsonStringEncodedSize(string), context: context, maxBytes: maxBytes)
        case let .data(mimeType, data):
            let prefix = "data:\(mimeType ?? "text/plain");base64,"
            let base64ByteCount = ((data.count + 2) / 3) * 4
            return try bounded(
                jsonStringEncodedSize(prefix) + base64ByteCount,
                context: context,
                maxBytes: maxBytes
            )
        case .array(let values):
            var size = 2
            for (index, nested) in values.enumerated() {
                if index > 0 { size = try bounded(size + 1, context: context, maxBytes: maxBytes) }
                let valueSize = try jsonEncodedSize(
                    of: nested,
                    context: context,
                    maxBytes: maxBytes,
                    maxNestingDepth: maxNestingDepth,
                    maxTotalObjectKeys: maxTotalObjectKeys,
                    depth: depth + 1,
                    objectKeyCount: &objectKeyCount
                )
                size = try bounded(size + valueSize, context: context, maxBytes: maxBytes)
            }
            return size
        case .object(let object):
            return try jsonEncodedSize(
                of: object,
                context: context,
                maxBytes: maxBytes,
                maxNestingDepth: maxNestingDepth,
                maxTotalObjectKeys: maxTotalObjectKeys,
                depth: depth,
                objectKeyCount: &objectKeyCount
            )
        }
    }

    private static func validateDepth(
        _ depth: Int,
        context: String,
        maxNestingDepth: Int
    ) throws {
        guard depth <= maxNestingDepth else {
            throw PublicAdapterInputError(
                "\(context) nesting depth exceeds \(maxNestingDepth) (observed \(depth))"
            )
        }
    }

    private static func bounded(_ size: Int, context: String, maxBytes: Int) throws -> Int {
        guard size <= maxBytes else {
            throw PublicAdapterInputError(
                "\(context) exceeds \(maxBytes) bytes (observed \(size) bytes)"
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
