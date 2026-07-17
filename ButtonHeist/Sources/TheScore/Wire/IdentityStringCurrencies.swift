import ThePlans

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
