import Foundation

public enum HeistStep: Codable, Sendable, Equatable {
    case action(ActionStep)
    case wait(WaitStep)
    case conditional(ConditionalStep)
    case forEachElement(ForEachElementStep)
    case forEachString(ForEachStringStep)
    case repeatUntil(RepeatUntilStep)
    case warn(WarnStep)
    case fail(FailStep)
    indirect case heist(HeistPlan)
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

    public init(from decoder: Decoder) throws {
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
            self = .heist(try container.decode(HeistPlan.self, forKey: .heist))
        case .invoke:
            try decoder.rejectUnknownKeys(allowed: ["type", "invoke"], typeName: "invoke heist step")
            self = .invoke(try container.decode(HeistInvocationStep.self, forKey: .invoke))
        }
    }

    public func encode(to encoder: Encoder) throws {
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
