import Foundation

public struct ActionStep: Codable, Sendable, Equatable {
    public let command: HeistActionCommand
    public let expectation: WaitStep?
    public let expectationWaiver: String?
    let expectationValidationFailure: String?

    public init(
        command: HeistActionCommand,
        expectation: WaitStep? = nil,
        expectationWaiver: String? = nil,
        expectationValidationFailure: String? = nil
    ) throws {
        guard expectation?.elseBody == nil else {
            throw HeistPlanError.expectationElseBodyUnsupported
        }
        if let expectationWaiver {
            guard !expectationWaiver.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HeistPlanError.emptyExpectationWaiver
            }
            guard expectation == nil else {
                throw HeistPlanError.ambiguousExpectationContract
            }
        }
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
        self.expectationValidationFailure = expectationValidationFailure
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case command, expectation
        case expectationWaiver = "without_expectation"
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "action step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            command: try container.decode(HeistActionCommand.self, forKey: .command),
            expectation: try container.decodeIfPresent(WaitStep.self, forKey: .expectation),
            expectationWaiver: try container.decodeIfPresent(String.self, forKey: .expectationWaiver)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(expectation, forKey: .expectation)
        try container.encodeIfPresent(expectationWaiver, forKey: .expectationWaiver)
    }

    public static func == (lhs: ActionStep, rhs: ActionStep) -> Bool {
        lhs.command == rhs.command
            && lhs.expectation == rhs.expectation
            && lhs.expectationWaiver == rhs.expectationWaiver
    }
}
