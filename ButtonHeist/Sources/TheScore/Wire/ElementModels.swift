import ThePlans
import Foundation
import AccessibilitySnapshotModel

// MARK: - Element Action Set

/// Set-shaped element actions with deterministic boundary projection.
public struct ElementActionSet: Codable, Equatable, Hashable, Sendable, ExpressibleByArrayLiteral {
    public let actions: Set<ElementAction>

    public init<S: Sequence>(_ actions: S) where S.Element == ElementAction {
        self.actions = Set(actions)
    }

    public init(arrayLiteral elements: ElementAction...) {
        self.init(elements)
    }

    public var orderedActions: [ElementAction] {
        actions.sorted { lhs, rhs in
            lhs.canonicalSortKey < rhs.canonicalSortKey
        }
    }

    public var displayText: String {
        orderedActions.map(\.description).joined(separator: ", ")
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode([ElementAction].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(orderedActions)
    }
}

extension Sequence where Element == ElementAction {
    var elementActionSet: ElementActionSet {
        ElementActionSet(self)
    }

    var canonicalElementActionArray: [ElementAction] {
        elementActionSet.orderedActions
    }
}

private extension ElementAction {
    var canonicalSortKey: String {
    switch self {
    case .activate:
        return "0:activate"
    case .typeText:
        return "1:typeText"
    case .increment:
        return "2:increment"
    case .decrement:
        return "3:decrement"
    case .custom(let name):
        return "4:\(name)"
    }
}
}

// MARK: - Heist Element

/// A captured accessibility element, separated into meaning and placement.
public struct HeistElement: Codable, Equatable, Hashable, Sendable {
    public let semantics: Semantics
    public let geometry: Geometry

    public init(semantics: Semantics, geometry: Geometry) {
        self.semantics = semantics
        self.geometry = geometry
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case semantics
        case geometry
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "HeistElement")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            semantics: try container.decode(Semantics.self, forKey: .semantics),
            geometry: try container.decode(Geometry.self, forKey: .geometry)
        )
    }
}

public extension HeistElement {
    struct Semantics: Codable, Equatable, Hashable, Sendable {
        public let spokenDescription: String
        public let assertable: AssertableProperties
        public let respondsToUserInteraction: Bool

        public init(
            spokenDescription: String,
            assertable: AssertableProperties,
            respondsToUserInteraction: Bool
        ) {
            self.spokenDescription = spokenDescription
            self.assertable = assertable
            self.respondsToUserInteraction = respondsToUserInteraction
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case spokenDescription
            case assertable
            case respondsToUserInteraction
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "HeistElement.Semantics")
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                spokenDescription: try container.decode(String.self, forKey: .spokenDescription),
                assertable: try container.decode(AssertableProperties.self, forKey: .assertable),
                respondsToUserInteraction: try container.decode(
                    Bool.self,
                    forKey: .respondsToUserInteraction
                )
            )
        }

        public struct AssertableProperties: Equatable, Hashable, Sendable {
            public let label: String?
            public let value: String?
            public let identifier: String?
            public let hint: String?
            public let traits: Set<HeistTrait>
            public let customContent: [HeistCustomContent]
            public let rotors: Set<HeistRotor>
            public let actions: Set<ElementAction>

            public init(
                label: String?,
                value: String?,
                identifier: String?,
                hint: String? = nil,
                traits: Set<HeistTrait> = [],
                customContent: [HeistCustomContent] = [],
                rotors: Set<HeistRotor> = [],
                actions: Set<ElementAction> = []
            ) {
                self.label = label
                self.value = value
                self.identifier = identifier
                self.hint = hint
                self.traits = traits
                self.customContent = customContent
                self.rotors = rotors
                self.actions = actions
            }

            public var orderedTraits: [HeistTrait] {
                traits.canonicalHeistTraitArray
            }

            public var orderedCustomContent: [HeistCustomContent] {
                customContent
            }

            public var orderedRotors: [HeistRotor] {
                rotors.sorted { $0.name < $1.name }
            }

            public var orderedActions: [ElementAction] {
                ElementActionSet(actions).orderedActions
            }
        }
    }

    struct Geometry: Codable, Equatable, Hashable, Sendable {
        public let screen: ScreenSpace
        public let view: ViewSpace

        public init(screen: ScreenSpace, view: ViewSpace) {
            self.screen = screen
            self.view = view
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case screen
            case view
        }

        public init(from decoder: Decoder) throws {
            try decoder.rejectUnknownKeys(
                allowed: CodingKeys.self,
                typeName: "HeistElement.Geometry"
            )
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                screen: try container.decode(ScreenSpace.self, forKey: .screen),
                view: try container.decode(ViewSpace.self, forKey: .view)
            )
        }

        /// Live geometry for one settled viewport. A viewport move invalidates
        /// this evidence. The next snapshot supplies new screen geometry.
        public enum ScreenSpace: Codable, Equatable, Hashable, Sendable {
            case onscreen(
                frame: ScreenFrameEvidence,
                activationPoint: ActivationPointEvidence
            )
            case offscreen

            private enum Visibility: String, Codable {
                case onscreen
                case offscreen
            }

            private enum CodingKeys: String, CodingKey, CaseIterable {
                case visibility
                case frame
                case activationPoint
            }

            public init(from decoder: Decoder) throws {
                try decoder.rejectUnknownKeys(
                    allowed: CodingKeys.self,
                    typeName: "HeistElement.Geometry.ScreenSpace"
                )
                let container = try decoder.container(keyedBy: CodingKeys.self)
                switch try container.decode(Visibility.self, forKey: .visibility) {
                case .onscreen:
                    self = .onscreen(
                        frame: try container.decode(ScreenFrameEvidence.self, forKey: .frame),
                        activationPoint: try container.decode(
                            ActivationPointEvidence.self,
                            forKey: .activationPoint
                        )
                    )
                case .offscreen:
                    guard !container.contains(.frame),
                          !container.contains(.activationPoint)
                    else {
                        throw DecodingError.dataCorruptedError(
                            forKey: .visibility,
                            in: container,
                            debugDescription: "offscreen geometry cannot carry screen-space evidence"
                        )
                    }
                    self = .offscreen
                }
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .onscreen(let frame, let activationPoint):
                    try container.encode(Visibility.onscreen, forKey: .visibility)
                    try container.encode(frame, forKey: .frame)
                    try container.encode(activationPoint, forKey: .activationPoint)
                case .offscreen:
                    try container.encode(Visibility.offscreen, forKey: .visibility)
                }
            }
        }

        /// Geometry in the coordinate space of the owning view. It stays valid
        /// across viewport moves on the same layout. A layout change or screen
        /// change invalidates the complete parent-space value.
        public enum ViewSpace: Codable, Equatable, Hashable, Sendable {
            case available(Available)
            case invalidated(ownerPath: TreePath)

            public struct Available: Equatable, Hashable, Sendable {
                public let ownerPath: TreePath
                public let frame: ViewRect
                public let activationPoint: ViewPoint

                public init(
                    ownerPath: TreePath,
                    frame: ViewRect,
                    activationPoint: ViewPoint
                ) {
                    self.ownerPath = ownerPath
                    self.frame = frame
                    self.activationPoint = activationPoint
                }
            }

            package var ownerPath: TreePath {
                switch self {
                case .available(let available):
                    available.ownerPath
                case .invalidated(let ownerPath):
                    ownerPath
                }
            }

            package static func admit(
                ownerPath: TreePath,
                frame: ViewRect?,
                activationPoint: ViewPoint?
            ) -> Self {
                guard let frame, let activationPoint else {
                    return .invalidated(ownerPath: ownerPath)
                }
                return .available(Available(
                    ownerPath: ownerPath,
                    frame: frame,
                    activationPoint: activationPoint
                ))
            }

            package func admitted(ownedBy ownerPath: TreePath) -> Self {
                guard case .available(let available) = self,
                      available.ownerPath == ownerPath
                else {
                    return .invalidated(ownerPath: ownerPath)
                }
                return self
            }

            package func rebased(
                fromSubtreeRoot originalRoot: TreePath,
                to projectedRoot: TreePath
            ) -> Self {
                guard let relativeOwnerPath = ownerPath.removingPrefix(originalRoot) else {
                    return .invalidated(ownerPath: .root)
                }
                let projectedOwnerPath = projectedRoot.appending(contentsOf: relativeOwnerPath)
                switch self {
                case .available(let available):
                    return .available(Available(
                        ownerPath: projectedOwnerPath,
                        frame: available.frame,
                        activationPoint: available.activationPoint
                    ))
                case .invalidated:
                    return .invalidated(ownerPath: projectedOwnerPath)
                }
            }

            private enum Availability: String, Codable {
                case available
                case invalidated
            }

            private enum CodingKeys: String, CodingKey, CaseIterable {
                case availability
                case ownerPath
                case frame
                case activationPoint
            }

            public init(from decoder: Decoder) throws {
                try decoder.rejectUnknownKeys(
                    allowed: CodingKeys.self,
                    typeName: "HeistElement.Geometry.ViewSpace"
                )
                let container = try decoder.container(keyedBy: CodingKeys.self)
                switch try container.decode(Availability.self, forKey: .availability) {
                case .available:
                    try container.rejectIncompatibleFields(
                        allowing: [.availability, .ownerPath, .frame, .activationPoint],
                        typeName: "available view-space geometry"
                    )
                    self = .available(Available(
                        ownerPath: try container.decode(TreePath.self, forKey: .ownerPath),
                        frame: try container.decode(ViewRect.self, forKey: .frame),
                        activationPoint: try container.decode(ViewPoint.self, forKey: .activationPoint)
                    ))
                case .invalidated:
                    try container.rejectIncompatibleFields(
                        allowing: [.availability, .ownerPath],
                        typeName: "invalidated view-space geometry"
                    )
                    self = .invalidated(
                        ownerPath: try container.decode(TreePath.self, forKey: .ownerPath)
                    )
                }
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .available(let available):
                    try container.encode(Availability.available, forKey: .availability)
                    try container.encode(available.ownerPath, forKey: .ownerPath)
                    try container.encode(available.frame, forKey: .frame)
                    try container.encode(available.activationPoint, forKey: .activationPoint)
                case .invalidated(let ownerPath):
                    try container.encode(Availability.invalidated, forKey: .availability)
                    try container.encode(ownerPath, forKey: .ownerPath)
                }
            }
        }
    }
}

extension HeistElement.Semantics.AssertableProperties: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case label
        case value
        case identifier
        case hint
        case traits
        case customContent
        case rotors
        case actions
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            allowed: CodingKeys.self,
            typeName: "HeistElement.Semantics.AssertableProperties"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: try container.decodeIfPresent(String.self, forKey: .label),
            value: try container.decodeIfPresent(String.self, forKey: .value),
            identifier: try container.decodeIfPresent(String.self, forKey: .identifier),
            hint: try container.decodeIfPresent(String.self, forKey: .hint),
            traits: Set(try container.decode([HeistTrait].self, forKey: .traits)),
            customContent: try container.decode([HeistCustomContent].self, forKey: .customContent),
            rotors: Set(try container.decode([HeistRotor].self, forKey: .rotors)),
            actions: try container.decode(ElementActionSet.self, forKey: .actions).actions
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(identifier, forKey: .identifier)
        try container.encodeIfPresent(hint, forKey: .hint)
        try container.encode(orderedTraits, forKey: .traits)
        try container.encode(orderedCustomContent, forKey: .customContent)
        try container.encode(orderedRotors, forKey: .rotors)
        try container.encode(orderedActions, forKey: .actions)
    }
}

public extension HeistElement {
    init(
        accessibilityElement element: AccessibilityElement,
        actions: [ElementAction] = [],
        geometry: Geometry
    ) {
        let validCustomContent = element.customContent.compactMap(HeistCustomContent.init(projecting:))
        let validRotors = element.customRotors.filter { !$0.name.isEmpty }
        self.init(
            semantics: Semantics(
                spokenDescription: element.description,
                assertable: Semantics.AssertableProperties(
                    label: element.label,
                    value: element.value,
                    identifier: element.identifier,
                    hint: element.hint,
                    traits: Set(element.traits.heistTraits),
                    customContent: validCustomContent,
                    rotors: Set(validRotors.map { HeistRotor(name: $0.name) }),
                    actions: Set(actions)
                ),
                respondsToUserInteraction: element.respondsToUserInteraction
            ),
            geometry: geometry
        )
    }
}

/// Rotor metadata attached to a HeistElement.
///
/// This intentionally describes availability only. Rotor results are discovered
/// live through a command because rotor movement is contextual and can be
/// direction-dependent or unbounded.
public struct HeistRotor: Codable, Equatable, Hashable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

/// Custom content attached to a HeistElement (maps to AccessibilityElement.CustomContent)
public struct HeistCustomContent: Codable, Equatable, Hashable, Sendable {
    public let label: String
    public let value: String
    public let isImportant: Bool

    public init(label: String, value: String, isImportant: Bool) {
        self.label = label
        self.value = value
        self.isImportant = isImportant
    }

    package init?(projecting content: AccessibilityElement.CustomContent) {
        guard !content.label.isEmpty || !content.value.isEmpty else { return nil }
        self.init(label: content.label, value: content.value, isImportant: content.isImportant)
    }
}
