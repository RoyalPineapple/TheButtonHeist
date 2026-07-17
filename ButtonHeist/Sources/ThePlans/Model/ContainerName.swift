/// Button Heist's generated name for a container in the current interface capture.
public struct ContainerName: NonBlankStringValue, Comparable {
    public let rawValue: String

    public init(validating value: String) throws {
        self.rawValue = try validateNonBlank(value, kind: "container name")
    }

    public var description: String {
        rawValue
    }

    public static func < (lhs: ContainerName, rhs: ContainerName) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
