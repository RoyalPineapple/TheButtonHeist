public struct GestureDuration: Codable, Sendable, Equatable, CustomStringConvertible,
    ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    public static let maximumSeconds = 60.0

    public static let longPressDefault = GestureDuration(seconds: 0.5)
    public static let swipeDefault = GestureDuration(seconds: 0.15)
    public static let dragDefault = GestureDuration(seconds: 0.5)
    public static let scrollSwipeDefault = GestureDuration(seconds: 0.12)

    private let boundedSeconds: BoundedSeconds

    public init(validatingSeconds seconds: Double) throws {
        self = try Self.admitting(seconds: seconds)
    }

    package init(seconds: Double) {
        self = requireValidPublicPayload {
            try Self.admitting(seconds: seconds)
        }
    }

    public init(floatLiteral value: Double) {
        self = requireValidPublicPayload {
            try Self(validatingSeconds: value)
        }
    }

    public init(integerLiteral value: Int) {
        self = requireValidPublicPayload {
            try Self(validatingSeconds: Double(value))
        }
    }

    package static func admitting(seconds: Double) throws -> Self {
        do {
            return Self(boundedSeconds: try BoundedSeconds(
                value: seconds,
                maximum: maximumSeconds
            ))
        } catch let error as BoundedSecondsError {
            throw GestureProjectionError.invalidDuration(
                observed: error.observed,
                expected: error.expected
            )
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
            self = try Self.admitting(seconds: seconds)
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
        ScoreDescription.decimal(seconds)
    }
}
