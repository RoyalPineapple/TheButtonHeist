import Foundation

// Admission owns the externally submitted plan shape. Decoding this type proves
// only that source/artifact JSON can be loaded as plan IR; runtime safety is the
// separate executable-plan boundary.
public struct HeistPlanAdmissionCandidate: Codable, Sendable, Equatable {
    package let version: Int
    package let name: HeistPlanName?
    package let parameter: HeistParameter
    package let definitions: [HeistPlanAdmissionCandidate]
    package let body: [HeistStepAdmissionCandidate]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, name, parameter, definitions, body
    }

    package init(
        version: Int = HeistPlan.currentVersion,
        name: HeistPlanName? = nil,
        parameter: HeistParameter = .none,
        definitions: [HeistPlanAdmissionCandidate] = [],
        body: [HeistStepAdmissionCandidate] = []
    ) {
        self.version = version
        self.name = name
        self.parameter = parameter
        self.definitions = definitions
        self.body = body
    }

    init(_ plan: HeistPlan) {
        version = plan.version
        name = plan.name
        parameter = plan.parameter
        definitions = plan.definitions.map(HeistPlanAdmissionCandidate.init)
        body = plan.body.map(HeistStepAdmissionCandidate.init)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decode(Int.self, forKey: .version)
        guard decodedVersion == HeistPlan.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Unsupported heist plan version \(decodedVersion). " +
                    "This Button Heist build supports version \(HeistPlan.currentVersion)."
            )
        }
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist plan")
        version = decodedVersion
        name = try container.decodeIfPresent(HeistPlanName.self, forKey: .name)
        parameter = try container.decodeIfPresent(HeistParameter.self, forKey: .parameter) ?? .none
        definitions = try container.decodeIfPresent([HeistPlanAdmissionCandidate].self, forKey: .definitions) ?? []
        body = try container.decode([HeistStepAdmissionCandidate].self, forKey: .body)
        guard !body.isEmpty || !definitions.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .body,
                in: container,
                debugDescription: "HeistPlan requires a non-empty body or definitions"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(name, forKey: .name)
        if parameter != .none {
            try container.encode(parameter, forKey: .parameter)
        }
        if !definitions.isEmpty {
            try container.encode(definitions, forKey: .definitions)
        }
        try container.encode(body, forKey: .body)
    }
}

package struct HeistStepAdmissionCandidate: Codable, Sendable, Equatable {
    let payload: HeistStepAdmissionPayload

    private init(_ payload: HeistStepAdmissionPayload) {
        self.payload = payload
    }

    package init(_ step: HeistStep) {
        switch step {
        case .action(let step): self.init(HeistStepAdmissionPayload.action(step))
        case .wait(let step): self.init(.wait(HeistWaitAdmissionCandidate(step)))
        case .conditional(let step): self.init(.conditional(HeistConditionalAdmissionCandidate(step)))
        case .forEachElement(let step): self.init(.forEachElement(HeistForEachElementAdmissionCandidate(step)))
        case .forEachString(let step): self.init(.forEachString(HeistForEachStringAdmissionCandidate(step)))
        case .repeatUntil(let step): self.init(.repeatUntil(HeistRepeatUntilAdmissionCandidate(step)))
        case .warn(let step): self.init(HeistStepAdmissionPayload.warn(step))
        case .fail(let step): self.init(HeistStepAdmissionPayload.fail(step))
        case .heist(let plan): self.init(.heist(HeistPlanAdmissionCandidate(plan)))
        case .invoke(let step): self.init(HeistStepAdmissionPayload.invoke(step))
        }
    }

    package static func action(_ step: ActionStep) -> Self {
        Self(HeistStepAdmissionPayload.action(step))
    }
    package static func wait(_ step: WaitStep) -> Self { Self(.wait(HeistWaitAdmissionCandidate(step))) }
    package static func conditional(_ step: ConditionalStep) -> Self {
        Self(.conditional(HeistConditionalAdmissionCandidate(step)))
    }
    package static func forEachElement(_ step: ForEachElementStep) -> Self {
        Self(.forEachElement(HeistForEachElementAdmissionCandidate(step)))
    }
    package static func forEachString(_ step: ForEachStringStep) -> Self {
        Self(.forEachString(HeistForEachStringAdmissionCandidate(step)))
    }
    package static func repeatUntil(_ step: RepeatUntilStep) -> Self {
        Self(.repeatUntil(HeistRepeatUntilAdmissionCandidate(step)))
    }
    package static func warn(_ step: WarnStep) -> Self {
        Self(HeistStepAdmissionPayload.warn(step))
    }
    package static func fail(_ step: FailStep) -> Self {
        Self(HeistStepAdmissionPayload.fail(step))
    }
    package static func heist(_ plan: HeistPlanAdmissionCandidate) -> Self { Self(.heist(plan)) }
    package static func invoke(_ step: HeistInvocationStep) -> Self {
        Self(HeistStepAdmissionPayload.invoke(step))
    }

    static func wait(_ step: HeistWaitAdmissionCandidate) -> Self { Self(.wait(step)) }
    static func conditional(_ step: HeistConditionalAdmissionCandidate) -> Self { Self(.conditional(step)) }
    static func forEachElement(_ step: HeistForEachElementAdmissionCandidate) -> Self { Self(.forEachElement(step)) }
    static func forEachString(_ step: HeistForEachStringAdmissionCandidate) -> Self { Self(.forEachString(step)) }
    static func repeatUntil(_ step: HeistRepeatUntilAdmissionCandidate) -> Self { Self(.repeatUntil(step)) }

    package init(from decoder: Decoder) throws {
        let envelope = try HeistStepTaggedEnvelope(from: decoder)
        switch envelope.type {
        case .action: self = .action(try envelope.decode(ActionStep.self))
        case .wait: self = .wait(try envelope.decode(HeistWaitAdmissionCandidate.self))
        case .conditional: self = .conditional(try envelope.decode(HeistConditionalAdmissionCandidate.self))
        case .forEachElement: self = .forEachElement(try envelope.decode(HeistForEachElementAdmissionCandidate.self))
        case .forEachString: self = .forEachString(try envelope.decode(HeistForEachStringAdmissionCandidate.self))
        case .repeatUntil: self = .repeatUntil(try envelope.decode(HeistRepeatUntilAdmissionCandidate.self))
        case .warn: self = .warn(try envelope.decode(WarnStep.self))
        case .fail: self = .fail(try envelope.decode(FailStep.self))
        case .heist: self = .heist(try envelope.decode(HeistPlanAdmissionCandidate.self))
        case .invoke: self = .invoke(try envelope.decode(HeistInvocationStep.self))
        }
    }

    package func encode(to encoder: Encoder) throws {
        switch payload {
        case .action(let step): try HeistStepTaggedEnvelope.encode(.action, payload: step, to: encoder)
        case .wait(let step): try HeistStepTaggedEnvelope.encode(.wait, payload: step, to: encoder)
        case .conditional(let step): try HeistStepTaggedEnvelope.encode(.conditional, payload: step, to: encoder)
        case .forEachElement(let step): try HeistStepTaggedEnvelope.encode(.forEachElement, payload: step, to: encoder)
        case .forEachString(let step): try HeistStepTaggedEnvelope.encode(.forEachString, payload: step, to: encoder)
        case .repeatUntil(let step): try HeistStepTaggedEnvelope.encode(.repeatUntil, payload: step, to: encoder)
        case .warn(let step): try HeistStepTaggedEnvelope.encode(.warn, payload: step, to: encoder)
        case .fail(let step): try HeistStepTaggedEnvelope.encode(.fail, payload: step, to: encoder)
        case .heist(let plan): try HeistStepTaggedEnvelope.encode(.heist, payload: plan, to: encoder)
        case .invoke(let step): try HeistStepTaggedEnvelope.encode(.invoke, payload: step, to: encoder)
        }
    }
}

indirect enum HeistStepAdmissionPayload: Sendable, Equatable {
    case action(ActionStep)
    case wait(HeistWaitAdmissionCandidate)
    case conditional(HeistConditionalAdmissionCandidate)
    case forEachElement(HeistForEachElementAdmissionCandidate)
    case forEachString(HeistForEachStringAdmissionCandidate)
    case repeatUntil(HeistRepeatUntilAdmissionCandidate)
    case warn(WarnStep)
    case fail(FailStep)
    case heist(HeistPlanAdmissionCandidate)
    case invoke(HeistInvocationStep)
}

struct HeistWaitAdmissionCandidate: Codable, Sendable, Equatable {
    let predicate: AccessibilityPredicate
    let timeout: WaitTimeout
    let elseBody: [HeistStepAdmissionCandidate]?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate, timeout
        case elseBody = "else_body"
    }

    init(predicate: AccessibilityPredicate, timeout: WaitTimeout, elseBody: [HeistStepAdmissionCandidate]? = nil) {
        self.predicate = predicate
        self.timeout = timeout
        self.elseBody = elseBody
    }

    init(_ step: WaitStep) {
        self.init(predicate: step.predicate, timeout: step.timeout, elseBody: step.elseBody?.map(HeistStepAdmissionCandidate.init))
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "wait step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            predicate: try container.decode(AccessibilityPredicate.self, forKey: .predicate),
            timeout: try container.decode(WaitTimeout.self, forKey: .timeout),
            elseBody: try container.decodeIfPresent([HeistStepAdmissionCandidate].self, forKey: .elseBody)
        )
    }
}

struct HeistConditionalAdmissionCandidate: Codable, Sendable, Equatable {
    let cases: [HeistPredicateCaseAdmissionCandidate]
    let elseBody: [HeistStepAdmissionCandidate]?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case cases
        case elseBody = "else_body"
    }

    init(cases: [HeistPredicateCaseAdmissionCandidate], elseBody: [HeistStepAdmissionCandidate]? = nil) throws {
        guard !cases.isEmpty else { throw HeistPlanError.emptyPredicateCases("conditional") }
        self.cases = cases
        self.elseBody = elseBody
    }

    init(_ step: ConditionalStep) {
        cases = step.cases.map(HeistPredicateCaseAdmissionCandidate.init)
        elseBody = step.elseBody?.map(HeistStepAdmissionCandidate.init)
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "conditional step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            cases: container.decode([HeistPredicateCaseAdmissionCandidate].self, forKey: .cases),
            elseBody: container.decodeIfPresent([HeistStepAdmissionCandidate].self, forKey: .elseBody)
        )
    }
}

struct HeistPredicateCaseAdmissionCandidate: Codable, Sendable, Equatable {
    let predicate: ChangeDeclaration.ScreenAssertion
    let body: [HeistStepAdmissionCandidate]

    private enum CodingKeys: String, CodingKey, CaseIterable { case predicate, body }

    init(predicate: ChangeDeclaration.ScreenAssertion, body: [HeistStepAdmissionCandidate]) {
        self.predicate = predicate
        self.body = body
    }

    init(_ predicateCase: PredicateCase) {
        self.init(predicate: predicateCase.predicate, body: predicateCase.body.map(HeistStepAdmissionCandidate.init))
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "predicate case")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            predicate: try container.decode(ChangeDeclaration.ScreenAssertion.self, forKey: .predicate),
            body: try container.decode([HeistStepAdmissionCandidate].self, forKey: .body)
        )
    }
}

struct HeistForEachElementAdmissionCandidate: Codable, Sendable, Equatable {
    let matching: ElementPredicateTemplate
    let limit: Int
    let parameter: HeistReferenceName
    let body: [HeistStepAdmissionCandidate]

    private enum CodingKeys: String, CodingKey, CaseIterable { case matching, limit, parameter, body }

    init(
        matching: ElementPredicateTemplate,
        limit: Int,
        parameter: HeistReferenceName,
        body: [HeistStepAdmissionCandidate]
    ) throws {
        guard matching.hasPredicates else { throw HeistPlanError.emptyForEachPredicate }
        guard limit > 0 else { throw HeistPlanError.invalidForEachLimit(limit) }
        guard !body.isEmpty else { throw HeistPlanError.emptyForEachSteps }
        self.matching = matching
        self.limit = limit
        self.parameter = parameter
        self.body = body
    }

    init(_ step: ForEachElementStep) {
        matching = step.matching
        limit = step.limit
        parameter = step.parameter
        body = step.body.map(HeistStepAdmissionCandidate.init)
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "for_each_element step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            matching: container.decode(ElementPredicateTemplate.self, forKey: .matching),
            limit: container.decode(Int.self, forKey: .limit),
            parameter: HeistReferenceName.decode(from: container, forKey: .parameter, type: "for_each_element parameter"),
            body: container.decode([HeistStepAdmissionCandidate].self, forKey: .body)
        )
    }
}

struct HeistForEachStringAdmissionCandidate: Codable, Sendable, Equatable {
    let values: [String]
    let parameter: HeistReferenceName
    let body: [HeistStepAdmissionCandidate]

    private enum CodingKeys: String, CodingKey, CaseIterable { case values, parameter, body }

    init(values: [String], parameter: HeistReferenceName, body: [HeistStepAdmissionCandidate]) throws {
        guard !values.isEmpty else { throw HeistPlanError.emptyForEachValues }
        guard !body.isEmpty else { throw HeistPlanError.emptyForEachSteps }
        self.values = values
        self.parameter = parameter
        self.body = body
    }

    init(_ step: ForEachStringStep) {
        values = step.values
        parameter = step.parameter
        body = step.body.map(HeistStepAdmissionCandidate.init)
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "for_each_string step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            values: container.decode([String].self, forKey: .values),
            parameter: HeistReferenceName.decode(from: container, forKey: .parameter, type: "for_each_string parameter"),
            body: container.decode([HeistStepAdmissionCandidate].self, forKey: .body)
        )
    }
}

struct HeistRepeatUntilAdmissionCandidate: Codable, Sendable, Equatable {
    let predicate: AccessibilityPredicate
    let timeout: WaitTimeout
    let body: [HeistStepAdmissionCandidate]
    let elseBody: [HeistStepAdmissionCandidate]?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate, timeout, body
        case elseBody = "else_body"
    }

    init(
        predicate: AccessibilityPredicate,
        timeout: WaitTimeout,
        body: [HeistStepAdmissionCandidate],
        elseBody: [HeistStepAdmissionCandidate]? = nil
    ) throws {
        guard !body.isEmpty else { throw HeistPlanError.emptyRepeatUntilSteps }
        self.predicate = predicate
        self.timeout = timeout
        self.body = body
        self.elseBody = elseBody
    }

    init(_ step: RepeatUntilStep) {
        predicate = step.predicate
        timeout = step.timeout
        body = step.body.map(HeistStepAdmissionCandidate.init)
        elseBody = step.elseBody?.map(HeistStepAdmissionCandidate.init)
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "repeat_until step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            predicate: container.decode(AccessibilityPredicate.self, forKey: .predicate),
            timeout: container.decode(WaitTimeout.self, forKey: .timeout),
            body: container.decode([HeistStepAdmissionCandidate].self, forKey: .body),
            elseBody: container.decodeIfPresent([HeistStepAdmissionCandidate].self, forKey: .elseBody)
        )
    }
}

extension HeistPlanRuntimeSafetyValidator {
    mutating func validate(_ candidate: HeistPlanAdmissionCandidate) throws -> HeistPlan {
        let plan = try HeistPlan(admitting: candidate)
        inspect(plan)
        guard failures.isEmpty else { throw HeistPlanRuntimeSafetyError(failures: failures) }
        return plan
    }
}

private extension HeistPlan {
    init(admitting candidate: HeistPlanAdmissionCandidate) throws {
        version = candidate.version
        name = candidate.name
        parameter = candidate.parameter
        definitions = try candidate.definitions.map { try HeistPlan(admitting: $0) }
        body = try candidate.body.map { try $0.admittedStep() }
    }
}

private extension HeistStepAdmissionCandidate {
    func admittedStep() throws -> HeistStep {
        switch payload {
        case .action(let step): return .action(step)
        case .wait(let step):
            return .wait(WaitStep(
                predicate: step.predicate,
                timeout: step.timeout,
                elseBody: try step.elseBody?.map { try $0.admittedStep() }
            ))
        case .conditional(let step):
            return .conditional(try ConditionalStep(
                cases: try step.cases.map { predicateCase in
                    PredicateCase(
                        predicate: predicateCase.predicate,
                        body: try predicateCase.body.map { try $0.admittedStep() }
                    )
                },
                elseBody: try step.elseBody?.map { try $0.admittedStep() }
            ))
        case .forEachElement(let step):
            return .forEachElement(try ForEachElementStep(
                matching: step.matching,
                limit: step.limit,
                parameter: step.parameter,
                body: try step.body.map { try $0.admittedStep() }
            ))
        case .forEachString(let step):
            return .forEachString(try ForEachStringStep(
                values: step.values,
                parameter: step.parameter,
                body: try step.body.map { try $0.admittedStep() }
            ))
        case .repeatUntil(let step):
            return .repeatUntil(try RepeatUntilStep(
                predicate: step.predicate,
                timeout: step.timeout,
                body: try step.body.map { try $0.admittedStep() },
                elseBody: try step.elseBody?.map { try $0.admittedStep() }
            ))
        case .warn(let step): return .warn(step)
        case .fail(let step): return .fail(step)
        case .heist(let candidate): return .heist(try HeistPlan(admitting: candidate))
        case .invoke(let step): return .invoke(step)
        }
    }
}
