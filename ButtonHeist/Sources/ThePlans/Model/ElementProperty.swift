/// Which accessibility property changed on an element.
///
/// The observation vocabulary: every property the tree observer can report a
/// change on, geometry included. A moving frame is a real change and has to be
/// nameable, because that is how settlement knows the tree is still moving.
///
/// The predicate language uses a narrower type. See `AssertableProperty`.
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
    ///
    /// Observed and reported, never asserted on: there is no `AssertableProperty`
    /// case for either, so a geometry predicate cannot be written down.
    public var isGeometry: Bool {
        self == .frame || self == .activationPoint
    }

    /// The predicate-language twin, when this property has one.
    ///
    /// `nil` for the two identity matchers, because pairing an element across
    /// captures is what they do, and for geometry, because a predicate cannot
    /// reason about it.
    public var assertable: AssertableProperty? {
        switch self {
        case .value: return .value
        case .traits: return .traits
        case .hint: return .hint
        case .actions: return .actions
        case .customContent: return .customContent
        case .rotors: return .rotors
        case .label, .identifier, .frame, .activationPoint: return nil
        }
    }

    public init?(intValue: Int) { nil }
    public var intValue: Int? { nil }
}

/// Which property an `updated` assertion constrains.
///
/// The predicate language's vocabulary, and deliberately smaller than
/// `ElementProperty`. Two kinds of property are absent because they are
/// unaskable rather than merely unsupported:
///
/// - The identity matchers, `label` and `identifier`. Pairing an element across
///   two captures is what they do, so constraining them describes a different
///   element rather than a changed one.
/// - Geometry, `frame` and `activationPoint`. A reading is taken over the
///   projection, which carries no coordinates, so a geometry assertion could
///   only ever say "this element was here, and is still here". A series of frame
///   changes is correct to emit and inert to a predicate: it reads identically
///   to the tick before it, lands on the same answer, and falls off on its own.
///
/// Being a separate type is the point. Geometry is not filtered out of the
/// predicate language downstream, it is unrepresentable in it.
public enum AssertableProperty: String, Codable, Sendable, CaseIterable, CodingKey {
    case value
    case traits
    case hint
    case actions
    case customContent
    case rotors

    /// The observation vocabulary's name for this property.
    ///
    /// Total, unlike its inverse: everything assertable is observable.
    public var observed: ElementProperty {
        switch self {
        case .value: return .value
        case .traits: return .traits
        case .hint: return .hint
        case .actions: return .actions
        case .customContent: return .customContent
        case .rotors: return .rotors
        }
    }

    static var nameList: String {
        allCases.map(\.rawValue).joined(separator: ", ")
    }

    public init?(intValue: Int) { nil }
    public var intValue: Int? { nil }
}
