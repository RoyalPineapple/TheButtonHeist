import Foundation

public enum HeistParameter: Codable, Sendable, Equatable {
    case none
    case string(name: HeistReferenceName)
    case elementTarget(name: HeistReferenceName)

    public var name: HeistReferenceName? {
        switch self {
        case .none:
            return nil
        case .string(let name), .elementTarget(let name):
            return name
        }
    }

    public var kind: HeistParameterKind {
        switch self {
        case .none: return .none
        case .string: return .string
        case .elementTarget: return .elementTarget
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, name
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist parameter")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(HeistParameterKind.self, forKey: .type)
        switch type {
        case .none:
            if container.contains(.name) {
                throw DecodingError.dataCorruptedError(
                    forKey: .name,
                    in: container,
                    debugDescription: "none heist parameter must not include a name"
                )
            }
            self = .none
        case .string:
            self = .string(name: try container.decode(String.self, forKey: .name))
        case .elementTarget:
            self = .elementTarget(name: try container.decode(String.self, forKey: .name))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)
        if let name {
            try container.encode(name, forKey: .name)
        }
    }
}

public enum HeistParameterKind: String, Codable, Sendable, Equatable {
    case none
    case string
    case elementTarget = "element_target"
}

public enum HeistArgument: Codable, Sendable, Equatable {
    case none
    case string(StringExpr)
    case elementTarget(ElementTargetExpr)

    public var kind: HeistParameterKind {
        switch self {
        case .none: return .none
        case .string: return .string
        case .elementTarget: return .elementTarget
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, value
        case valueRef = "value_ref"
        case target
        case values
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist argument")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(HeistParameterKind.self, forKey: .type)
        switch type {
        case .none:
            let hasValue = container.contains(.value)
                || container.contains(.valueRef)
                || container.contains(.target)
                || container.contains(.values)
            if hasValue {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "none heist argument must not include a value"
                ))
            }
            self = .none
        case .string:
            if container.contains(.values) {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath + [CodingKeys.values],
                    debugDescription: "string heist argument accepts exactly one value; use ForEach for multiple string values"
                ))
            }
            let hasValue = container.contains(.value)
            let hasRef = container.contains(.valueRef)
            guard hasValue != hasRef else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "string heist argument requires exactly one of value/value_ref"
                ))
            }
            self = hasValue
                ? .string(.literal(try container.decode(String.self, forKey: .value)))
                : .string(.ref(try container.decode(String.self, forKey: .valueRef)))
        case .elementTarget:
            // Singular: a predicate for exactly one element, carried under `target`
            // as an element-target expression (concrete target, predicate, or ref).
            guard container.contains(.target) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "element_target heist argument requires a target"
                ))
            }
            self = .elementTarget(try container.decode(ElementTargetExpr.self, forKey: .target))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)
        switch self {
        case .none:
            break
        case .string(let value):
            switch value {
            case .literal(let string):
                try container.encode(string, forKey: .value)
            case .ref(let reference):
                try container.encode(reference, forKey: .valueRef)
            }
        case .elementTarget(let target):
            try container.encode(target, forKey: .target)
        }
    }
}
