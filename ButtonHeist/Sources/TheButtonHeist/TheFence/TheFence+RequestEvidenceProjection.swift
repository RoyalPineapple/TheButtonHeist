import Foundation

import TheScore

extension HeistValue {
    static func encoded<T: Encodable>(_ value: T) throws -> HeistValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(HeistValue.self, from: data)
    }
}

extension Encodable {
    func heistEvidenceArguments(
        accepting acceptedKeys: Set<String>,
        renaming renamedKeys: [String: String] = [:]
    ) throws -> [String: HeistValue] {
        guard case .object(let encoded) = try HeistValue.encoded(self) else {
            throw DecodingError.typeMismatch(
                [String: HeistValue].self,
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Heist evidence projection must encode \(Self.self) as an object"
                )
            )
        }
        var arguments = encoded.reduce(into: [String: HeistValue]()) { result, pair in
            guard acceptedKeys.contains(pair.key) else { return }
            result[renamedKeys[pair.key] ?? pair.key] = pair.value
        }
        arguments.flattenRotorTextRange()
        return arguments
    }
}

extension Dictionary where Key == String, Value == HeistValue {
    mutating func flattenRotorTextRange() {
        guard case .object(let textRange)? = removeValue(forKey: "currentTextRange") else { return }
        if let startOffset = textRange["startOffset"] {
            self["currentTextStartOffset"] = startOffset
        }
        if let endOffset = textRange["endOffset"] {
            self["currentTextEndOffset"] = endOffset
        }
    }
}

struct HeistRecordingProjection {
    let arguments: [String: HeistValue]
    let elementTarget: ElementTarget?
    let coordinateOnly: Bool

    static let empty = HeistRecordingProjection(arguments: [:])

    static func target(
        arguments: [String: HeistValue] = [:],
        elementTarget: ElementTarget?,
        coordinateOnly: Bool = false
    ) -> Self {
        Self(arguments: arguments, elementTarget: elementTarget, coordinateOnly: coordinateOnly)
    }

    init(
        arguments: [String: HeistValue] = [:],
        elementTarget: ElementTarget? = nil,
        coordinateOnly: Bool = false
    ) {
        self.arguments = arguments
        self.elementTarget = elementTarget
        self.coordinateOnly = coordinateOnly
    }
}
