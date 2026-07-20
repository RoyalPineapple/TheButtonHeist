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
        let envelope = try HeistStepTaggedEnvelope(from: decoder)
        switch envelope.type {
        case .action: self = .action(try envelope.decode(ActionStep.self))
        case .wait: self = .wait(try envelope.decode(WaitStep.self))
        case .conditional: self = .conditional(try envelope.decode(ConditionalStep.self))
        case .forEachElement: self = .forEachElement(try envelope.decode(ForEachElementStep.self))
        case .forEachString: self = .forEachString(try envelope.decode(ForEachStringStep.self))
        case .repeatUntil: self = .repeatUntil(try envelope.decode(RepeatUntilStep.self))
        case .warn: self = .warn(try envelope.decode(WarnStep.self))
        case .fail: self = .fail(try envelope.decode(FailStep.self))
        case .heist: self = .heist(try envelope.decode(HeistPlan.self))
        case .invoke: self = .invoke(try envelope.decode(HeistInvocationStep.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
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

enum HeistStepWireCodingKey: String, CodingKey, CaseIterable {
    case type, action, wait, conditional
    case forEachElement = "for_each_element"
    case forEachString = "for_each_string"
    case repeatUntil = "repeat_until"
    case warn, fail, heist, invoke
}

enum HeistStepWireType: String, Codable {
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

    var payloadKey: HeistStepWireCodingKey {
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

struct HeistStepTaggedEnvelope {
    let type: HeistStepWireType
    let container: KeyedDecodingContainer<HeistStepWireCodingKey>

    init(from decoder: Decoder) throws {
        container = try decoder.container(keyedBy: HeistStepWireCodingKey.self)
        type = try container.decode(HeistStepWireType.self, forKey: .type)
        try decoder.rejectUnknownKeys(
            allowed: [HeistStepWireCodingKey.type.stringValue, type.payloadKey.stringValue],
            typeName: type.typeName
        )
    }

    func decode<Payload: Decodable>(_ payload: Payload.Type) throws -> Payload {
        try container.decode(payload, forKey: type.payloadKey)
    }

    static func encode<Payload: Encodable>(
        _ type: HeistStepWireType,
        payload: Payload,
        to encoder: Encoder
    ) throws {
        var container = encoder.container(keyedBy: HeistStepWireCodingKey.self)
        try container.encode(type, forKey: .type)
        try container.encode(payload, forKey: type.payloadKey)
    }
}
