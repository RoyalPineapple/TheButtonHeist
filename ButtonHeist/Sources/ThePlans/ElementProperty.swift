/// Which accessibility property changed on an element.
public enum ElementProperty: String, Codable, Sendable, CaseIterable {
    // No `label`/`identifier`: those are element identity (diff pairing key), so a
    // change to them is a remove+add, never a property update.
    case value
    case traits
    case hint
    case actions
    case frame
    case activationPoint
    case customContent
    case rotors
    case respondsToUserInteraction

    /// Geometry properties: frame position/size and activation point coordinates.
    public var isGeometry: Bool {
        self == .frame || self == .activationPoint
    }
}
