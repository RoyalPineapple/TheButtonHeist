import Foundation

struct HeistRuntimeSafetyTraversalDraft: Sendable, Equatable {
    let plan: HeistPlan

    init(candidate: HeistPlanAdmissionCandidate) {
        plan = candidate.runtimeSafetyTraversalDraftPlan()
    }
}

// Admission owns the externally submitted plan shape. Decoding this type proves
// only that source/artifact JSON can be loaded as plan IR; runtime safety is the
// separate executable-plan boundary.
package struct HeistPlanAdmissionCandidate: Codable, Sendable, Equatable {
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
        body: [HeistStepAdmissionCandidate]
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

    package init(from decoder: Decoder) throws {
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

    package func encode(to encoder: Encoder) throws {
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

    func runtimeSafetyTraversalDraftPlan() -> HeistPlan {
        // This is the one remaining bridge into HeistPlan-shaped traversal. The
        // draft must stay inside source parsing or runtime safety validation and
        // must not be returned before HeistPlanRuntimeSafetyValidator accepts it.
        HeistPlan(
            runtimeValidatedVersion: version,
            name: name,
            parameter: parameter,
            definitions: definitions.map { $0.runtimeSafetyTraversalDraftPlan() },
            body: body.map(\.runtimeSafetyTraversalDraftStep)
        )
    }
}

package enum HeistStepAdmissionCandidate: Codable, Sendable, Equatable {
    case action(ActionStep)
    case wait(WaitStep)
    case conditional(ConditionalStep)
    case forEachElement(ForEachElementStep)
    case forEachString(ForEachStringStep)
    case repeatUntil(RepeatUntilStep)
    case warn(WarnStep)
    case fail(FailStep)
    indirect case heist(HeistPlanAdmissionCandidate)
    case invoke(HeistInvocationStep)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, action, wait, conditional
        case forEachElement = "for_each_element"
        case forEachString = "for_each_string"
        case repeatUntil = "repeat_until"
        case warn, fail, heist, invoke
    }

    private enum StepType: String, Codable {
        case action
        case wait
        case conditional
        case forEachElement = "for_each_element"
        case forEachString = "for_each_string"
        case repeatUntil = "repeat_until"
        case warn
        case fail
        case heist
        case invoke
    }

    init(_ step: HeistStep) {
        switch step {
        case .action(let step):
            self = .action(step)
        case .wait(let step):
            self = .wait(step)
        case .conditional(let step):
            self = .conditional(step)
        case .forEachElement(let step):
            self = .forEachElement(step)
        case .forEachString(let step):
            self = .forEachString(step)
        case .repeatUntil(let step):
            self = .repeatUntil(step)
        case .warn(let step):
            self = .warn(step)
        case .fail(let step):
            self = .fail(step)
        case .heist(let plan):
            self = .heist(HeistPlanAdmissionCandidate(plan))
        case .invoke(let step):
            self = .invoke(step)
        }
    }

    var runtimeSafetyTraversalDraftStep: HeistStep {
        switch self {
        case .action(let step):
            return .action(step)
        case .wait(let step):
            return .wait(step)
        case .conditional(let step):
            return .conditional(step)
        case .forEachElement(let step):
            return .forEachElement(step)
        case .forEachString(let step):
            return .forEachString(step)
        case .repeatUntil(let step):
            return .repeatUntil(step)
        case .warn(let step):
            return .warn(step)
        case .fail(let step):
            return .fail(step)
        case .heist(let plan):
            return .heist(plan.runtimeSafetyTraversalDraftPlan())
        case .invoke(let step):
            return .invoke(step)
        }
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StepType.self, forKey: .type)
        switch type {
        case .action:
            try decoder.rejectUnknownKeys(allowed: ["type", "action"], typeName: "action heist step")
            self = .action(try container.decode(ActionStep.self, forKey: .action))
        case .wait:
            try decoder.rejectUnknownKeys(allowed: ["type", "wait"], typeName: "wait heist step")
            self = .wait(try container.decode(WaitStep.self, forKey: .wait))
        case .conditional:
            try decoder.rejectUnknownKeys(allowed: ["type", "conditional"], typeName: "conditional heist step")
            self = .conditional(try container.decode(ConditionalStep.self, forKey: .conditional))
        case .forEachElement:
            try decoder.rejectUnknownKeys(
                allowed: ["type", CodingKeys.forEachElement.stringValue],
                typeName: "for_each_element heist step"
            )
            self = .forEachElement(try container.decode(ForEachElementStep.self, forKey: .forEachElement))
        case .forEachString:
            try decoder.rejectUnknownKeys(
                allowed: ["type", CodingKeys.forEachString.stringValue],
                typeName: "for_each_string heist step"
            )
            self = .forEachString(try container.decode(ForEachStringStep.self, forKey: .forEachString))
        case .repeatUntil:
            try decoder.rejectUnknownKeys(
                allowed: ["type", CodingKeys.repeatUntil.stringValue],
                typeName: "repeat_until heist step"
            )
            self = .repeatUntil(try container.decode(RepeatUntilStep.self, forKey: .repeatUntil))
        case .warn:
            try decoder.rejectUnknownKeys(allowed: ["type", "warn"], typeName: "warn heist step")
            self = .warn(try container.decode(WarnStep.self, forKey: .warn))
        case .fail:
            try decoder.rejectUnknownKeys(allowed: ["type", "fail"], typeName: "fail heist step")
            self = .fail(try container.decode(FailStep.self, forKey: .fail))
        case .heist:
            try decoder.rejectUnknownKeys(allowed: ["type", "heist"], typeName: "heist group step")
            self = .heist(try container.decode(HeistPlanAdmissionCandidate.self, forKey: .heist))
        case .invoke:
            try decoder.rejectUnknownKeys(allowed: ["type", "invoke"], typeName: "invoke heist step")
            self = .invoke(try container.decode(HeistInvocationStep.self, forKey: .invoke))
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .action(let step):
            try container.encode(StepType.action, forKey: .type)
            try container.encode(step, forKey: .action)
        case .wait(let step):
            try container.encode(StepType.wait, forKey: .type)
            try container.encode(step, forKey: .wait)
        case .conditional(let step):
            try container.encode(StepType.conditional, forKey: .type)
            try container.encode(step, forKey: .conditional)
        case .forEachElement(let step):
            try container.encode(StepType.forEachElement, forKey: .type)
            try container.encode(step, forKey: .forEachElement)
        case .forEachString(let step):
            try container.encode(StepType.forEachString, forKey: .type)
            try container.encode(step, forKey: .forEachString)
        case .repeatUntil(let step):
            try container.encode(StepType.repeatUntil, forKey: .type)
            try container.encode(step, forKey: .repeatUntil)
        case .warn(let step):
            try container.encode(StepType.warn, forKey: .type)
            try container.encode(step, forKey: .warn)
        case .fail(let step):
            try container.encode(StepType.fail, forKey: .type)
            try container.encode(step, forKey: .fail)
        case .heist(let plan):
            try container.encode(StepType.heist, forKey: .type)
            try container.encode(plan, forKey: .heist)
        case .invoke(let step):
            try container.encode(StepType.invoke, forKey: .type)
            try container.encode(step, forKey: .invoke)
        }
    }
}
