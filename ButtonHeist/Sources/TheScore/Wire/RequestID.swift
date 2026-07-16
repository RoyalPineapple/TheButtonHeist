/// A nonblank Button Heist wire request identifier used to correlate requests and responses.
public struct RequestID: NonBlankStringValue {
    private let value: String
    public init(validating value: String) throws {
        self.value = try validateNonBlank(value)
    }
    public var description: String { value }
}
