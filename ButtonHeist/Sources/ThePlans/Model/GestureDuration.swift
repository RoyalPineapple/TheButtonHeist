public struct GestureDuration: Codable, Sendable, Equatable, CustomStringConvertible {
    public static let maximumSeconds = 60.0

    public static let longPressDefault = GestureDuration(validatedSeconds: 0.5)
    public static let swipeDefault = GestureDuration(validatedSeconds: 0.15)
    public static let dragDefault = GestureDuration(validatedSeconds: 0.5)
    public static let scrollSwipeDefault = GestureDuration(validatedSeconds: 0.12)

    public let seconds: Double

    public init(seconds: Double) {
        self.seconds = seconds
    }

    public init(validatingSeconds seconds: Double) throws {
        if let expected = Self.validationFailure(for: seconds) {
            throw GestureProjectionError.invalidDuration(observed: seconds, expected: expected)
        }
        self.seconds = seconds
    }

    private init(validatedSeconds seconds: Double) {
        self.seconds = seconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validatingSeconds: try container.decode(Double.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(seconds)
    }

    public var description: String {
        ScoreDescription.decimal(seconds)
    }

    public static func validationFailure(for seconds: Double) -> String? {
        guard seconds.isFinite else {
            return "number"
        }
        guard seconds > 0 else {
            return "number > 0"
        }
        guard seconds <= maximumSeconds else {
            return "number in 0...\(maximumSeconds)"
        }
        return nil
    }
}
