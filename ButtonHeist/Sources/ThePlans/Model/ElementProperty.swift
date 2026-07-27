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
    /// `nil` for the identity matchers and for geometry. See
    /// `AssertableProperty` for why neither is askable.
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
///   only ever say "this element was here, and is still here".
///
/// Geometry is not filtered out of the predicate language downstream, it is
/// unrepresentable in it.
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

/// Something that can be hashed over the part of it that means something.
///
/// The tree has two users and each reads a different part of it. `label`,
/// `value`, `traits`, `hint`, `actions`, `rotors` and `customContent` are what
/// a VoiceOver user perceives; `identifier` is what a developer names an
/// element by and what a heist targets. Both are meaning. Geometry is neither:
/// it is how the element is drawn, not what it is, and an element that moved
/// still says exactly what it said before.
///
/// That boundary is why a reading exists. A reading decides whether a change's
/// second leg found something new, so hashing geometry in would let a frame
/// shifting a pixel satisfy an assertion nobody wrote.
///
/// Deliberately narrower than `Hashable`, and both live on the same types:
/// `hash(into:)` identifies the value, this identifies what it means.
public protocol SemanticallyHashable {
    func hashSemantic(into hasher: inout Hasher)
}

extension SemanticallyHashable {
    /// This value's reading, as a number that only means "same" or "different".
    public var semanticHash: Int {
        var hasher = Hasher()
        hashSemantic(into: &hasher)
        return hasher.finalize()
    }
}
