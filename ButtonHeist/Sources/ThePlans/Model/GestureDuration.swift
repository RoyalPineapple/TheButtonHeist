public struct GestureDuration: Codable, Sendable, Equatable, CustomStringConvertible,
    ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    public static let maximumSeconds = 60.0

    public static let longPressDefault: Self = 0.5
    public static let swipeDefault: Self = 0.15
    public static let dragDefault: Self = 0.5
    public static let scrollSwipeDefault: Self = 0.12

    private let boundedSeconds: BoundedSeconds

    public init(validatingSeconds seconds: Double) throws(GestureProjectionError) {
        do {
            self.init(boundedSeconds: try BoundedSeconds(
                value: seconds,
                maximum: Self.maximumSeconds
            ))
        } catch let error {
            throw GestureProjectionError.invalidDuration(
                observed: error.observed,
                expected: error.expected
            )
        }
    }

    public init(floatLiteral value: Double) {
        self = requireValidLiteralPayload {
            try Self(validatingSeconds: value)
        }
    }

    public init(integerLiteral value: Int) {
        self = requireValidLiteralPayload {
            try Self(validatingSeconds: Double(value))
        }
    }

    private init(boundedSeconds: BoundedSeconds) {
        self.boundedSeconds = boundedSeconds
    }

    public var seconds: Double {
        boundedSeconds.value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let seconds = try container.decode(Double.self)
        do {
            self = try Self(validatingSeconds: seconds)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: String(describing: error)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(seconds)
    }

    public var description: String {
        CanonicalValueDescription.decimal(seconds)
    }
}
