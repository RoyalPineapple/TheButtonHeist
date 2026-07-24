import Foundation

public struct MainThreadProbeRequest: Codable, Sendable, Equatable {
    public let responsivenessTimeoutMilliseconds: Int64
    public let workTimeoutMilliseconds: Int64

    package init(
        responsivenessTimeoutMilliseconds: Int64,
        workTimeoutMilliseconds: Int64
    ) {
        precondition(
            responsivenessTimeoutMilliseconds > 0 && workTimeoutMilliseconds > 0
        )
        self.responsivenessTimeoutMilliseconds = responsivenessTimeoutMilliseconds
        self.workTimeoutMilliseconds = workTimeoutMilliseconds
    }

    public static func admit(
        responsivenessTimeoutMilliseconds: Int64,
        workTimeoutMilliseconds: Int64
    ) -> Self? {
        guard responsivenessTimeoutMilliseconds > 0, workTimeoutMilliseconds > 0 else {
            return nil
        }
        return Self(
            responsivenessTimeoutMilliseconds: responsivenessTimeoutMilliseconds,
            workTimeoutMilliseconds: workTimeoutMilliseconds
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case responsivenessTimeoutMilliseconds
        case workTimeoutMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "main-thread probe request")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let admitted = Self.admit(
            responsivenessTimeoutMilliseconds: try container.decode(
                Int64.self,
                forKey: .responsivenessTimeoutMilliseconds
            ),
            workTimeoutMilliseconds: try container.decode(
                Int64.self,
                forKey: .workTimeoutMilliseconds
            )
        ) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "main-thread probe timeouts must be positive millisecond durations"
            ))
        }
        self = admitted
    }
}

public enum MainThreadProbeOutcome: String, Codable, Sendable, Equatable, CaseIterable {
    case responsive
    case mainThreadUnresponsive
    case workTimedOut
}

public struct MainThreadProbeResponse: Codable, Sendable, Equatable {
    public let outcome: MainThreadProbeOutcome

    public init(outcome: MainThreadProbeOutcome) {
        self.outcome = outcome
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case outcome
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "main-thread probe response")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outcome = try container.decode(MainThreadProbeOutcome.self, forKey: .outcome)
    }
}
