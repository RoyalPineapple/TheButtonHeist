/// Which accessibility property changed on an element.
public enum ElementProperty: String, Codable, Sendable, CaseIterable {
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
}

extension ElementProperty {
    struct SourceDescriptor: Sendable, Equatable {
        let property: ElementProperty
        let sourceName: String
        let expectedFields: [String]
        let allowsUnlabeledAfter: Bool

        init(
            _ property: ElementProperty,
            expectedFields: [String] = ["before", "after"],
            allowsUnlabeledAfter: Bool = false
        ) {
            self.property = property
            self.sourceName = property.rawValue
            self.expectedFields = expectedFields
            self.allowsUnlabeledAfter = allowsUnlabeledAfter
        }

        var expectedFieldList: String {
            expectedFields.joined(separator: " and ")
        }
    }

    static let parserSupportedSourceDescriptors: [SourceDescriptor] = [
        SourceDescriptor(.label),
        SourceDescriptor(.identifier),
        SourceDescriptor(.value, allowsUnlabeledAfter: true),
        SourceDescriptor(.traits),
        SourceDescriptor(.hint),
        SourceDescriptor(.actions),
        SourceDescriptor(.frame),
        SourceDescriptor(.activationPoint),
        SourceDescriptor(.customContent),
        SourceDescriptor(.rotors),
    ]

    static func parserSupportedSourceDescriptor(named sourceName: String) -> SourceDescriptor? {
        parserSupportedSourceDescriptors.first { $0.sourceName == sourceName }
    }

    static var parserSupportedSourceNameList: String {
        parserSupportedSourceDescriptors.map(\.sourceName).joined(separator: ", ")
    }
}
