import Foundation

/// Shared mechanics for open string values whose identity is their exact, nonblank spelling.
public protocol NonBlankStringValue: Codable, Sendable, Hashable, Equatable,
    ExpressibleByStringLiteral, CustomStringConvertible {
    init(validating value: String) throws
}

public extension NonBlankStringValue {
    init(stringLiteral value: String) {
        do {
            try self.init(validating: value)
        } catch {
            preconditionFailure(String(describing: error))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: String(describing: error)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

private struct BlankStringValueError: Error, CustomStringConvertible {
    var description: String { "value must not be blank" }
}

package func validateNonBlank(_ value: String) throws -> String {
    guard value.contains(where: { !$0.isWhitespace }) else { throw BlankStringValueError() }
    return value
}

public struct SessionAuthToken: NonBlankStringValue {
    private let value: String
    public init(validating value: String) throws { self.value = try validateNonBlank(value) }
    public var description: String { value }
}

public struct DriverID: NonBlankStringValue {
    private let value: String
    public init(validating value: String) throws { self.value = try validateNonBlank(value) }
    public var description: String { value }
}

public struct BundleIdentifier: NonBlankStringValue {
    private let value: String
    public init(validating value: String) throws { self.value = try validateNonBlank(value) }
    public var description: String { value }
}

public struct ServerLaunchID: NonBlankStringValue {
    private let value: String
    public init(validating value: String) throws { self.value = try validateNonBlank(value) }
    public var description: String { value }
}

public struct InsideJobInstanceID: NonBlankStringValue {
    private let value: String
    public init(validating value: String) throws { self.value = try validateNonBlank(value) }
    public var description: String { value }
}

public struct InstallationID: NonBlankStringValue {
    private let value: String
    public init(validating value: String) throws { self.value = try validateNonBlank(value) }
    public var description: String { value }
}

public struct SimulatorUDID: NonBlankStringValue {
    private let value: String
    public init(validating value: String) throws { self.value = try validateNonBlank(value) }
    public var description: String { value }
}

public struct VendorIdentifier: NonBlankStringValue {
    private let value: String
    public init(validating value: String) throws { self.value = try validateNonBlank(value) }
    public var description: String { value }
}
