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

    public init(from decoder: Decoder) throws {
        self = HeistStep(try HeistStepWirePayload<HeistPlan>(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try wirePayload.encode(to: encoder)
    }
}

enum HeistStepWirePayload<Plan> {
    case action(ActionStep)
    case wait(WaitStep)
    case conditional(ConditionalStep)
    case forEachElement(ForEachElementStep)
    case forEachString(ForEachStringStep)
    case repeatUntil(RepeatUntilStep)
    case warn(WarnStep)
    case fail(FailStep)
    indirect case heist(Plan)
    case invoke(HeistInvocationStep)
}

extension HeistStepWirePayload: Sendable where Plan: Sendable {}
extension HeistStepWirePayload: Equatable where Plan: Equatable {}

extension HeistStepWirePayload: Codable where Plan: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, action, wait, conditional
        case forEachElement = "for_each_element"
        case forEachString = "for_each_string"
        case repeatUntil = "repeat_until"
        case warn, fail, heist, invoke
    }

    private enum WireType: String, Codable {
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
            switch self {
            case .heist: return "heist group step"
            default: return "\(rawValue) heist step"
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(WireType.self, forKey: .type)
        try decoder.rejectUnknownKeys(
            allowed: [CodingKeys.type.stringValue, type.payloadKey.stringValue],
            typeName: type.typeName
        )
        switch type {
        case .action:
            self = .action(try container.decode(ActionStep.self, forKey: .action))
        case .wait:
            self = .wait(try container.decode(WaitStep.self, forKey: .wait))
        case .conditional:
            self = .conditional(try container.decode(ConditionalStep.self, forKey: .conditional))
        case .forEachElement:
            self = .forEachElement(try container.decode(ForEachElementStep.self, forKey: .forEachElement))
        case .forEachString:
            self = .forEachString(try container.decode(ForEachStringStep.self, forKey: .forEachString))
        case .repeatUntil:
            self = .repeatUntil(try container.decode(RepeatUntilStep.self, forKey: .repeatUntil))
        case .warn:
            self = .warn(try container.decode(WarnStep.self, forKey: .warn))
        case .fail:
            self = .fail(try container.decode(FailStep.self, forKey: .fail))
        case .heist:
            self = .heist(try container.decode(Plan.self, forKey: .heist))
        case .invoke:
            self = .invoke(try container.decode(HeistInvocationStep.self, forKey: .invoke))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
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

extension HeistStep {
    init(_ payload: HeistStepWirePayload<HeistPlan>) {
        switch payload {
        case .action(let step): self = .action(step)
        case .wait(let step): self = .wait(step)
        case .conditional(let step): self = .conditional(step)
        case .forEachElement(let step): self = .forEachElement(step)
        case .forEachString(let step): self = .forEachString(step)
        case .repeatUntil(let step): self = .repeatUntil(step)
        case .warn(let step): self = .warn(step)
        case .fail(let step): self = .fail(step)
        case .heist(let plan): self = .heist(plan)
        case .invoke(let step): self = .invoke(step)
        }
    }

    var wirePayload: HeistStepWirePayload<HeistPlan> {
        switch self {
        case .action(let step): return .action(step)
        case .wait(let step): return .wait(step)
        case .conditional(let step): return .conditional(step)
        case .forEachElement(let step): return .forEachElement(step)
        case .forEachString(let step): return .forEachString(step)
        case .repeatUntil(let step): return .repeatUntil(step)
        case .warn(let step): return .warn(step)
        case .fail(let step): return .fail(step)
        case .heist(let plan): return .heist(plan)
        case .invoke(let step): return .invoke(step)
        }
    }
}
