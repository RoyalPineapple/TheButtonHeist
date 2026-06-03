public struct TapTarget: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case element
        case point
    }

    public let selection: GesturePointSelection

    public init(selection: GesturePointSelection) {
        self.selection = selection
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "tap target")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.selection = try Self.decodeSelection(from: container)
    }

    public func encode(to encoder: Encoder) throws {
        try selection.encode(to: encoder)
    }

    private static func decodeSelection(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> GesturePointSelection {
        let element = try container.decodeIfPresent(ElementTarget.self, forKey: .element)
        let point = try container.decodeIfPresent(ScreenPoint.self, forKey: .point)
        switch (element, point) {
        case (.some(let element), nil):
            return .element(element)
        case (nil, .some(let point)):
            return .coordinate(point)
        case (.some, .some):
            throw GestureProjectionError.mixedCoordinateAndElement(field: "point")
        case (nil, nil):
            throw GestureProjectionError.missingGesturePoint(field: "point")
        }
    }
}

extension TapTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("tap", [
            selection.description,
        ])
    }
}

public struct LongPressTarget: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case element
        case point
        case duration
    }

    public let selection: GesturePointSelection
    /// Duration in seconds.
    public let duration: GestureDuration

    public init(selection: GesturePointSelection, duration: GestureDuration = .longPressDefault) {
        self.selection = selection
        self.duration = duration
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "long press target")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let element = try container.decodeIfPresent(ElementTarget.self, forKey: .element)
        let point = try container.decodeIfPresent(ScreenPoint.self, forKey: .point)
        switch (element, point) {
        case (.some(let element), nil):
            self.selection = .element(element)
        case (nil, .some(let point)):
            self.selection = .coordinate(point)
        case (.some, .some):
            throw GestureProjectionError.mixedCoordinateAndElement(field: "point")
        case (nil, nil):
            throw GestureProjectionError.missingGesturePoint(field: "point")
        }
        self.duration = try container.decodeIfPresent(GestureDuration.self, forKey: .duration) ?? .longPressDefault
    }

    public func encode(to encoder: Encoder) throws {
        try selection.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(duration, forKey: .duration)
    }
}

extension LongPressTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("longPress", [
            selection.description,
            "duration=\(duration)",
        ])
    }
}
