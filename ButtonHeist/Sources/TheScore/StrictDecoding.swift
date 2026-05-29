struct ScoreUnknownCodingKey: CodingKey {
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

extension Decoder {
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
        let dynamicContainer = try container(keyedBy: ScoreUnknownCodingKey.self)
        guard let unknownKey = dynamicContainer.allKeys.first(where: { !knownKeys.contains($0.stringValue) }) else {
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: codingPath + [unknownKey],
            debugDescription: "Unknown \(typeName) field \"\(unknownKey.stringValue)\""
        ))
    }
}
