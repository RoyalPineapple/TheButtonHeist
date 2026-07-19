private struct UnknownCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

package extension Decoder {
    func rejectUnknownKeys<K>(
        allowed keyType: K.Type,
        additional allowedFieldNames: Set<String> = [],
        typeName: String
    ) throws where K: CodingKey & CaseIterable {
        let knownKeys = Set(keyType.allCases.map(\.stringValue)).union(allowedFieldNames)
        try rejectUnknownKeys(allowed: knownKeys, typeName: typeName)
    }

    func rejectUnknownKeys(
        allowed knownKeys: Set<String>,
        typeName: String
    ) throws {
        let dynamicContainer = try container(keyedBy: UnknownCodingKey.self)
        guard let unknownKey = dynamicContainer.allKeys.first(where: { !knownKeys.contains($0.stringValue) }) else {
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: codingPath + [unknownKey],
            debugDescription: "Unknown \(typeName) field \"\(unknownKey.stringValue)\""
        ))
    }
}

package extension KeyedDecodingContainer where Key: CaseIterable & Hashable {
    func rejectIncompatibleFields(
        allowing allowedKeys: Set<Key>,
        typeName: String
    ) throws {
        guard let incompatibleKey = Key.allCases.first(where: {
            !allowedKeys.contains($0) && contains($0)
        }) else { return }

        throw DecodingError.dataCorruptedError(
            forKey: incompatibleKey,
            in: self,
            debugDescription: "\(typeName) must not include \(incompatibleKey.stringValue)"
        )
    }
}
