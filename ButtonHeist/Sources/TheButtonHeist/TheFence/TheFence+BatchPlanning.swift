import Foundation

extension TheFence {

    func decodeRunBatchRequest(_ request: [String: Any]) throws -> RunBatchRequest {
        try Self.validateJSONEnvelope(
            request,
            field: "run_batch",
            maxBytes: DecodeLimits.maxRunBatchRequestBytes,
            maxDepth: DecodeLimits.maxRunBatchNestingDepth
        )
        let batchStepDecodeInputs = try request.requiredSchemaDictionaryArray("steps")
        guard !batchStepDecodeInputs.isEmpty else {
            throw SchemaValidationError(
                field: "steps",
                observed: "array count 0",
                expected: "array count 1...\(DecodeLimits.maxRunBatchSteps)"
            )
        }
        guard batchStepDecodeInputs.count <= DecodeLimits.maxRunBatchSteps else {
            throw SchemaValidationError(
                field: "steps",
                observed: "array count \(batchStepDecodeInputs.count)",
                expected: "array count 1...\(DecodeLimits.maxRunBatchSteps)"
            )
        }
        let parser = BatchCommandParser(fence: self)
        return RunBatchRequest(
            steps: batchStepDecodeInputs.enumerated().map { index, stepDecodeInput in
                parser.decode(
                    FenceOperationCatalog.routeBatchStepDecodeInput(stepDecodeInput),
                    index: index
                )
            },
            policy: try request.schemaEnum("policy", as: BatchPolicy.self) ?? .stopOnError
        )
    }
}

private extension TheFence {

    static func validateJSONEnvelope(
        _ value: Any,
        field: String,
        maxBytes: Int,
        maxDepth: Int
    ) throws {
        let byteCount = try jsonEncodedSize(
            of: value,
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

    static func jsonEncodedSize(
        of value: Any,
        field: String,
        maxBytes: Int,
        maxDepth: Int,
        depth: Int = 1
    ) throws -> Int {
        guard depth <= maxDepth else {
            throw SchemaValidationError(
                field: field,
                observed: "nesting depth \(depth)",
                expected: "nesting depth <= \(maxDepth)"
            )
        }

        func bounded(_ size: Int) throws -> Int {
            guard size <= maxBytes else {
                throw SchemaValidationError(
                    field: field,
                    observed: "\(size) bytes",
                    expected: "JSON request <= \(maxBytes) bytes"
                )
            }
            return size
        }

        if let dictionary = value as? [String: Any] {
            var size = 2
            for (index, entry) in dictionary.enumerated() {
                if index > 0 { size = try bounded(size + 1) }
                size = try bounded(size + jsonStringEncodedSize(entry.key) + 1)
                let valueSize = try jsonEncodedSize(
                    of: entry.value,
                    field: field,
                    maxBytes: maxBytes,
                    maxDepth: maxDepth,
                    depth: depth + 1
                )
                size = try bounded(size + valueSize)
            }
            return size
        }

        if let array = value as? [Any] {
            var size = 2
            for (index, item) in array.enumerated() {
                if index > 0 { size = try bounded(size + 1) }
                let itemSize = try jsonEncodedSize(
                    of: item,
                    field: field,
                    maxBytes: maxBytes,
                    maxDepth: maxDepth,
                    depth: depth + 1
                )
                size = try bounded(size + itemSize)
            }
            return size
        }

        if let string = value as? String {
            return try bounded(jsonStringEncodedSize(string))
        }

        if let bool = value as? Bool {
            return bool ? 4 : 5
        }

        if value is NSNull {
            return 4
        }

        if let number = value as? NSNumber {
            guard number.doubleValue.isFinite else {
                throw SchemaValidationError(field: field, observed: number, expected: "finite JSON number")
            }
            return try bounded(String(describing: number).utf8.count)
        }

        throw SchemaValidationError(field: field, observed: value, expected: "JSON value")
    }

    static func jsonStringEncodedSize(_ value: String) -> Int {
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
