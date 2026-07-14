import Foundation

public enum HeistParameter: Codable, Sendable, Equatable {
    case none
    case string(name: HeistReferenceName)
    case accessibilityTarget(name: HeistReferenceName)

    public var name: HeistReferenceName? {
        switch self {
        case .none:
            return nil
        case .string(let name), .accessibilityTarget(let name):
            return name
        }
    }

    public var kind: HeistParameterKind {
        switch self {
        case .none: return .none
        case .string: return .string
        case .accessibilityTarget: return .accessibilityTarget
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
            self = .string(name: try HeistReferenceName.decode(from: container, forKey: .name))
        case .accessibilityTarget:
            self = .accessibilityTarget(name: try HeistReferenceName.decode(from: container, forKey: .name))
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
    case accessibilityTarget = "accessibility_target"
}

package enum HeistArgumentCore: Sendable, Equatable {
    case none
    case string(Expr<String>)
    case accessibilityTarget(AccessibilityTarget)
}

public struct HeistArgument: Codable, Sendable, Equatable {
    package let core: HeistArgumentCore

    package init(core: HeistArgumentCore) {
        self.core = core
    }

    public static var none: Self { Self(core: .none) }

    public static func string(_ value: String) -> Self {
        Self(core: .string(.literal(value)))
    }

    public static func string(reference: HeistReferenceName) -> Self {
        Self(core: .string(.ref(reference)))
    }

    public static func accessibilityTarget(_ target: AccessibilityTarget) -> Self {
        Self(core: .accessibilityTarget(target))
    }

    public var kind: HeistParameterKind {
        switch core {
        case .none: return .none
        case .string: return .string
        case .accessibilityTarget: return .accessibilityTarget
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, value
        case valueRef = "value_ref"
        case target
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
            if hasValue {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "none heist argument must not include a value"
                ))
            }
            core = .none
        case .string:
            let hasValue = container.contains(.value)
            let hasRef = container.contains(.valueRef)
            guard hasValue != hasRef else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "string heist argument requires exactly one of value/value_ref"
                ))
            }
            core = hasValue
                ? .string(.literal(try container.decode(String.self, forKey: .value)))
                : .string(.ref(try HeistReferenceName.decode(from: container, forKey: .valueRef)))
        case .accessibilityTarget:
            guard container.contains(.target) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "accessibility_target heist argument requires a target"
                ))
            }
            core = .accessibilityTarget(try container.decode(AccessibilityTarget.self, forKey: .target))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)
        switch core {
        case .none:
            break
        case .string(let value):
            switch value {
            case .literal(let string):
                try container.encode(string, forKey: .value)
            case .ref(let reference):
                try container.encode(reference, forKey: .valueRef)
            }
        case .accessibilityTarget(let target):
            try container.encode(target, forKey: .target)
        }
    }
}
