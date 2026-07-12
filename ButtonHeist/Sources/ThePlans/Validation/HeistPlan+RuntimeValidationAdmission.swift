import Foundation

// Admission owns the externally submitted plan shape. Decoding this type proves
// only that source/artifact JSON can be loaded as plan IR; runtime safety is the
// separate executable-plan boundary.
public struct HeistPlanAdmissionCandidate: Codable, Sendable, Equatable {
    package let version: Int
    package let name: String?
    package let parameter: HeistParameter
    package let definitions: [HeistPlanAdmissionCandidate]
    package let body: [HeistStepAdmissionCandidate]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, name, parameter, definitions, body
    }

    package init(
        version: Int = HeistPlan.currentVersion,
        name: String? = nil,
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
        name = try container.decodeIfPresent(String.self, forKey: .name)
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
        case .action(let step): self.init(.action(step))
        case .wait(let step): self.init(.wait(HeistWaitAdmissionCandidate(step)))
        case .conditional(let step): self.init(.conditional(HeistConditionalAdmissionCandidate(step)))
        case .forEachElement(let step): self.init(.forEachElement(HeistForEachElementAdmissionCandidate(step)))
        case .forEachString(let step): self.init(.forEachString(HeistForEachStringAdmissionCandidate(step)))
        case .repeatUntil(let step): self.init(.repeatUntil(HeistRepeatUntilAdmissionCandidate(step)))
        case .warn(let step): self.init(.warn(step))
        case .fail(let step): self.init(.fail(step))
        case .heist(let plan): self.init(.heist(HeistPlanAdmissionCandidate(plan)))
        case .invoke(let step): self.init(.invoke(step))
        }
    }

    package static func action(_ step: ActionStep) -> Self { Self(.action(step)) }
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
    package static func warn(_ step: WarnStep) -> Self { Self(.warn(step)) }
    package static func fail(_ step: FailStep) -> Self { Self(.fail(step)) }
    package static func heist(_ plan: HeistPlanAdmissionCandidate) -> Self { Self(.heist(plan)) }
    package static func invoke(_ step: HeistInvocationStep) -> Self { Self(.invoke(step)) }

    static func wait(_ step: HeistWaitAdmissionCandidate) -> Self { Self(.wait(step)) }
    static func conditional(_ step: HeistConditionalAdmissionCandidate) -> Self { Self(.conditional(step)) }
    static func forEachElement(_ step: HeistForEachElementAdmissionCandidate) -> Self { Self(.forEachElement(step)) }
    static func forEachString(_ step: HeistForEachStringAdmissionCandidate) -> Self { Self(.forEachString(step)) }
    static func repeatUntil(_ step: HeistRepeatUntilAdmissionCandidate) -> Self { Self(.repeatUntil(step)) }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, action, wait, conditional
        case forEachElement = "for_each_element"
        case forEachString = "for_each_string"
        case repeatUntil = "repeat_until"
        case warn, fail, heist, invoke
    }

    private enum WireType: String, Codable {
        case action, wait, conditional
        case forEachElement = "for_each_element"
        case forEachString = "for_each_string"
        case repeatUntil = "repeat_until"
        case warn, fail, heist, invoke

        var payloadKey: CodingKeys {
            switch self {
            case .action: return .action
            case .wait: return .wait
            case .conditional: return .conditional
            case .forEachElement: return .forEachElement
            case .forEachString: return .forEachString
            case .repeatUntil: return .repeatUntil
            case .warn: return .warn
            case .fail: return .fail
            case .heist: return .heist
            case .invoke: return .invoke
            }
        }

        var typeName: String {
            self == .heist ? "heist group step" : "\(rawValue) heist step"
        }
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(WireType.self, forKey: .type)
        try decoder.rejectUnknownKeys(
            allowed: [CodingKeys.type.stringValue, type.payloadKey.stringValue],
            typeName: type.typeName
        )
        switch type {
        case .action: self = .action(try container.decode(ActionStep.self, forKey: .action))
        case .wait: self = .wait(try container.decode(HeistWaitAdmissionCandidate.self, forKey: .wait))
        case .conditional:
            self = .conditional(try container.decode(HeistConditionalAdmissionCandidate.self, forKey: .conditional))
        case .forEachElement:
            self = .forEachElement(try container.decode(HeistForEachElementAdmissionCandidate.self, forKey: .forEachElement))
        case .forEachString:
            self = .forEachString(try container.decode(HeistForEachStringAdmissionCandidate.self, forKey: .forEachString))
        case .repeatUntil:
            self = .repeatUntil(try container.decode(HeistRepeatUntilAdmissionCandidate.self, forKey: .repeatUntil))
        case .warn: self = .warn(try container.decode(WarnStep.self, forKey: .warn))
        case .fail: self = .fail(try container.decode(FailStep.self, forKey: .fail))
        case .heist: self = .heist(try container.decode(HeistPlanAdmissionCandidate.self, forKey: .heist))
        case .invoke: self = .invoke(try container.decode(HeistInvocationStep.self, forKey: .invoke))
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch payload {
        case .action(let step):
            try container.encode(WireType.action, forKey: .type)
            try container.encode(step, forKey: .action)
        case .wait(let step):
            try container.encode(WireType.wait, forKey: .type)
            try container.encode(step, forKey: .wait)
        case .conditional(let step):
            try container.encode(WireType.conditional, forKey: .type)
            try container.encode(step, forKey: .conditional)
        case .forEachElement(let step):
            try container.encode(WireType.forEachElement, forKey: .type)
            try container.encode(step, forKey: .forEachElement)
        case .forEachString(let step):
            try container.encode(WireType.forEachString, forKey: .type)
            try container.encode(step, forKey: .forEachString)
        case .repeatUntil(let step):
            try container.encode(WireType.repeatUntil, forKey: .type)
            try container.encode(step, forKey: .repeatUntil)
        case .warn(let step):
            try container.encode(WireType.warn, forKey: .type)
            try container.encode(step, forKey: .warn)
        case .fail(let step):
            try container.encode(WireType.fail, forKey: .type)
            try container.encode(step, forKey: .fail)
        case .heist(let plan):
            try container.encode(WireType.heist, forKey: .type)
            try container.encode(plan, forKey: .heist)
        case .invoke(let step):
            try container.encode(WireType.invoke, forKey: .type)
            try container.encode(step, forKey: .invoke)
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
    let predicate: AccessibilityPredicate<RootContext>
    let timeout: Double
    let elseBody: [HeistStepAdmissionCandidate]?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate, timeout
        case elseBody = "else_body"
    }

    init(predicate: AccessibilityPredicate<RootContext>, timeout: Double, elseBody: [HeistStepAdmissionCandidate]? = nil) {
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
        let timeout = try container.decode(Double.self, forKey: .timeout)
        guard timeout >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .timeout,
                in: container,
                debugDescription: "wait step timeout must be non-negative"
            )
        }
        self.init(
            predicate: try container.decode(AccessibilityPredicate<RootContext>.self, forKey: .predicate),
            timeout: timeout,
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
    let predicate: AccessibilityPredicate<ScreenAssertionContext>
    let body: [HeistStepAdmissionCandidate]

    private enum CodingKeys: String, CodingKey, CaseIterable { case predicate, body }

    init(predicate: AccessibilityPredicate<ScreenAssertionContext>, body: [HeistStepAdmissionCandidate]) {
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
            predicate: try container.decode(AccessibilityPredicate<ScreenAssertionContext>.self, forKey: .predicate),
            body: try container.decode([HeistStepAdmissionCandidate].self, forKey: .body)
        )
    }
}

struct HeistForEachElementAdmissionCandidate: Codable, Sendable, Equatable {
    let matching: ElementPredicate
    let limit: Int
    let parameter: HeistReferenceName
    let body: [HeistStepAdmissionCandidate]

    private enum CodingKeys: String, CodingKey, CaseIterable { case matching, limit, parameter, body }

    init(matching: ElementPredicate, limit: Int, parameter: HeistReferenceName, body: [HeistStepAdmissionCandidate]) throws {
        guard matching.hasPredicates else { throw HeistPlanError.emptyForEachPredicate }
        guard limit > 0 else { throw HeistPlanError.invalidForEachLimit(limit) }
        guard !body.isEmpty else { throw HeistPlanError.emptyForEachSteps }
        let parameter = try HeistParameterName.normalized(parameter.rawValue)
        self.matching = matching
        self.limit = limit
        self.parameter = HeistReferenceName(rawValue: parameter)
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
            matching: container.decode(ElementPredicate.self, forKey: .matching),
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
        let parameter = try HeistParameterName.normalized(parameter.rawValue)
        self.values = values
        self.parameter = HeistReferenceName(rawValue: parameter)
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
    let predicate: AccessibilityPredicate<RootContext>
    let timeout: Double
    let body: [HeistStepAdmissionCandidate]
    let elseBody: [HeistStepAdmissionCandidate]?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate, timeout, body
        case elseBody = "else_body"
    }

    init(
        predicate: AccessibilityPredicate<RootContext>,
        timeout: Double,
        body: [HeistStepAdmissionCandidate],
        elseBody: [HeistStepAdmissionCandidate]? = nil
    ) throws {
        guard timeout >= 0 else { throw HeistPlanError.negativeTimeout(timeout) }
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
            predicate: container.decode(AccessibilityPredicate<RootContext>.self, forKey: .predicate),
            timeout: container.decode(Double.self, forKey: .timeout),
            body: container.decode([HeistStepAdmissionCandidate].self, forKey: .body),
            elseBody: container.decodeIfPresent([HeistStepAdmissionCandidate].self, forKey: .elseBody)
        )
    }
}

private struct HeistPlanRuntimeAdmission {}

extension HeistPlanRuntimeSafetyValidator {
    mutating func validate(_ candidate: HeistPlanAdmissionCandidate) throws -> HeistPlan {
        inspect(candidate)
        guard failures.isEmpty else { throw HeistPlanRuntimeSafetyError(failures: failures) }
        return try HeistPlan(candidate, admittedBy: HeistPlanRuntimeAdmission())
    }
}

private extension HeistPlan {
    init(_ candidate: HeistPlanAdmissionCandidate, admittedBy admission: HeistPlanRuntimeAdmission) throws {
        version = candidate.version
        name = candidate.name
        parameter = candidate.parameter
        definitions = try candidate.definitions.map { try HeistPlan($0, admittedBy: admission) }
        body = try candidate.body.map { try $0.admittedStep(admission) }
    }
}

private extension HeistStepAdmissionCandidate {
    func admittedStep(_ admission: HeistPlanRuntimeAdmission) throws -> HeistStep {
        switch payload {
        case .action(let step): return .action(step)
        case .wait(let step):
            return .wait(WaitStep(
                predicate: step.predicate,
                timeout: step.timeout,
                elseBody: try step.elseBody?.map { try $0.admittedStep(admission) }
            ))
        case .conditional(let step):
            return .conditional(try ConditionalStep(
                cases: try step.cases.map { predicateCase in
                    PredicateCase(
                        predicate: predicateCase.predicate,
                        body: try predicateCase.body.map { try $0.admittedStep(admission) }
                    )
                },
                elseBody: try step.elseBody?.map { try $0.admittedStep(admission) }
            ))
        case .forEachElement(let step):
            return .forEachElement(try ForEachElementStep(
                matching: step.matching,
                limit: step.limit,
                parameter: step.parameter,
                body: try step.body.map { try $0.admittedStep(admission) }
            ))
        case .forEachString(let step):
            return .forEachString(try ForEachStringStep(
                values: step.values,
                parameter: step.parameter,
                body: try step.body.map { try $0.admittedStep(admission) }
            ))
        case .repeatUntil(let step):
            return .repeatUntil(try RepeatUntilStep(
                predicate: step.predicate,
                timeout: step.timeout,
                body: try step.body.map { try $0.admittedStep(admission) },
                elseBody: try step.elseBody?.map { try $0.admittedStep(admission) }
            ))
        case .warn(let step): return .warn(step)
        case .fail(let step): return .fail(step)
        case .heist(let candidate): return .heist(try HeistPlan(candidate, admittedBy: admission))
        case .invoke(let step): return .invoke(step)
        }
    }
}
