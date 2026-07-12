import Foundation
import ThePlans

public struct HeistInvocationEvidence: Codable, Sendable, Equatable {
    private let storage: Storage

    public struct InvocationExpectationEvidence: Sendable, Equatable {
        private enum Storage: Sendable, Equatable {
            case summary(actionResult: ActionResult, expectation: ExpectationResult)
            case wait(HeistWaitEvidence)
        }

        private let storage: Storage

        public var actionResult: ActionResult {
            switch storage {
            case .summary(let actionResult, _): actionResult
            case .wait(let evidence): evidence.actionResult
            }
        }

        public var expectation: ExpectationResult {
            switch storage {
            case .summary(_, let expectation): expectation
            case .wait(let evidence): evidence.expectation
            }
        }

        public var waitEvidence: HeistWaitEvidence? {
            guard case .wait(let evidence) = storage else { return nil }
            return evidence
        }

        public init(
            actionResult: ActionResult,
            expectation: ExpectationResult,
            waitEvidence: HeistWaitEvidence? = nil
        ) {
            if let waitEvidence {
                precondition(
                    waitEvidence.actionResult == actionResult && waitEvidence.expectation == expectation,
                    "Invocation expectation evidence must match its summarized action result and expectation"
                )
            }
            storage = waitEvidence.map(Storage.wait)
                ?? .summary(actionResult: actionResult, expectation: expectation)
        }
    }

    private enum Storage: Sendable, Equatable {
        case heist(name: String?, childFailedPath: String?)
        case invocation(
            invocation: HeistInvocationStep,
            name: String?,
            argument: String?,
            childFailedPath: String?,
            expectation: InvocationExpectationEvidence?
        )
    }

    public static func heist(
        name: String?,
        childFailedPath: String? = nil
    ) -> HeistInvocationEvidence {
        HeistInvocationEvidence(storage: .heist(name: name, childFailedPath: childFailedPath))
    }

    public static func invocation(
        _ invocation: HeistInvocationStep,
        name: String?,
        argument: String? = nil,
        childFailedPath: String? = nil,
        expectation: InvocationExpectationEvidence? = nil
    ) -> HeistInvocationEvidence {
        precondition(
            childFailedPath == nil || expectation == nil,
            "Child-aborted invocation evidence cannot include expectation evidence"
        )
        return HeistInvocationEvidence(storage: .invocation(
            invocation: invocation,
            name: name,
            argument: argument,
            childFailedPath: childFailedPath,
            expectation: expectation
        ))
    }

    private init(storage: Storage) {
        self.storage = storage
    }

    public var invocation: HeistInvocationStep? {
        guard case .invocation(let invocation, _, _, _, _) = storage else { return nil }
        return invocation
    }

    public var name: String? {
        switch storage {
        case .heist(let name, _),
             .invocation(_, let name, _, _, _):
            return name
        }
    }

    public var argument: String? {
        guard case .invocation(_, _, let argument, _, _) = storage else { return nil }
        return argument
    }

    public var childFailedPath: String? {
        switch storage {
        case .heist(_, let childFailedPath),
             .invocation(_, _, _, let childFailedPath, _):
            return childFailedPath
        }
    }

    public var expectationActionResult: ActionResult? {
        guard case .invocation(_, _, _, _, let expectation) = storage else { return nil }
        return expectation?.actionResult
    }

    public var expectation: ExpectationResult? {
        guard case .invocation(_, _, _, _, let expectation) = storage else { return nil }
        return expectation?.expectation
    }

    public var expectationEvidence: HeistWaitEvidence? {
        guard case .invocation(_, _, _, _, let expectation) = storage else { return nil }
        return expectation?.waitEvidence
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case invocation
        case name
        case argument
        case childFailedPath
        case expectationActionResult
        case expectation
        case expectationEvidence
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist invocation evidence")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let invocation = try container.decodeIfPresent(HeistInvocationStep.self, forKey: .invocation)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        let argument = try container.decodeIfPresent(String.self, forKey: .argument)
        let childFailedPath = try container.decodeIfPresent(String.self, forKey: .childFailedPath)
        let expectationActionResult = try container.decodeIfPresent(ActionResult.self, forKey: .expectationActionResult)
        let expectation = try container.decodeIfPresent(ExpectationResult.self, forKey: .expectation)
        let expectationEvidence = try container.decodeIfPresent(HeistWaitEvidence.self, forKey: .expectationEvidence)

        if let invocation {
            if childFailedPath != nil,
               expectationActionResult != nil || expectation != nil || expectationEvidence != nil {
                throw Self.decodingError(
                    "child-aborted invocation evidence must not include expectation evidence",
                    key: .childFailedPath,
                    container: container
                )
            }
            let expectationSummary = try Self.decodeExpectationEvidence(
                actionResult: expectationActionResult,
                expectation: expectation,
                waitEvidence: expectationEvidence,
                container: container
            )
            storage = .invocation(
                invocation: invocation,
                name: name,
                argument: argument,
                childFailedPath: childFailedPath,
                expectation: expectationSummary
            )
        } else {
            guard argument == nil,
                  childFailedPath == nil || expectationActionResult == nil && expectation == nil && expectationEvidence == nil,
                  expectationActionResult == nil,
                  expectation == nil,
                  expectationEvidence == nil
            else {
                throw Self.decodingError(
                    "inline heist invocation evidence must not include invoke-only fields",
                    key: .invocation,
                    container: container
                )
            }
            storage = .heist(name: name, childFailedPath: childFailedPath)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(invocation, forKey: .invocation)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(argument, forKey: .argument)
        try container.encodeIfPresent(childFailedPath, forKey: .childFailedPath)
        try container.encodeIfPresent(expectationActionResult, forKey: .expectationActionResult)
        try container.encodeIfPresent(expectation, forKey: .expectation)
        try container.encodeIfPresent(expectationEvidence, forKey: .expectationEvidence)
    }

    private static func decodeExpectationEvidence(
        actionResult: ActionResult?,
        expectation: ExpectationResult?,
        waitEvidence: HeistWaitEvidence?,
        container: KeyedDecodingContainer<CodingKeys>
    ) throws -> InvocationExpectationEvidence? {
        switch (actionResult, expectation, waitEvidence) {
        case (.none, .none, .none):
            return nil
        case (.some(let actionResult), .some(let expectation), .none):
            return InvocationExpectationEvidence(actionResult: actionResult, expectation: expectation)
        case (.some(let actionResult), .some(let expectation), .some(let waitEvidence)):
            guard waitEvidence.actionResult == actionResult && waitEvidence.expectation == expectation else {
                throw decodingError(
                    "invocation expectation evidence must match expectationActionResult and expectation",
                    key: .expectationEvidence,
                    container: container
                )
            }
            return InvocationExpectationEvidence(
                actionResult: actionResult,
                expectation: expectation,
                waitEvidence: waitEvidence
            )
        case (.none, _, .some), (_, .none, .some), (.some, .none, .none), (.none, .some, .none):
            throw decodingError(
                "invocation expectation evidence requires expectationActionResult and expectation",
                key: .expectationEvidence,
                container: container
            )
        }
    }

    private static func decodingError(
        _ message: String,
        key: CodingKeys,
        container: KeyedDecodingContainer<CodingKeys>
    ) -> DecodingError {
        DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: message)
    }
}
