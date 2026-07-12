/// Which accessibility property changed on an element.
public enum ElementProperty: String, Codable, Sendable, CaseIterable, CodingKey {
    case label
    case identifier
    case value
    case traits
    case hint
    case actions
    case frame
    case activationPoint
    case customContent
    case rotors

    /// Geometry properties: frame position/size and activation point coordinates.
    public var isGeometry: Bool {
        self == .frame || self == .activationPoint
    }

    /// Properties whose before/after values can change without changing the
    /// identity matcher used to pair an element across captures.
    public var isUpdateProperty: Bool {
        switch self {
        case .label, .identifier:
            return false
        case .value, .traits, .hint, .actions, .frame, .activationPoint, .customContent, .rotors:
            return true
        }
    }

    public static let updateProperties = allCases.filter(\.isUpdateProperty)

    static var updatePropertyNameList: String {
        updateProperties.map(\.rawValue).joined(separator: ", ")
    }

    public init?(intValue: Int) { nil }
    public var intValue: Int? { nil }
}
