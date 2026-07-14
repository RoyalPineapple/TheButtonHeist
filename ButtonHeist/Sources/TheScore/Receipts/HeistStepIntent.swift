import Foundation
import ThePlans

public enum HeistStepIntent: Codable, Sendable, Equatable {
    case action(command: HeistActionCommand)
    case wait(predicate: AccessibilityPredicate, timeout: Double)
    case conditional
    case forEachString(parameter: HeistReferenceName, count: Int)
    case forEachElement(parameter: HeistReferenceName, matching: ElementPredicateTemplate, limit: Int)
    case repeatUntil(predicate: AccessibilityPredicate, timeout: Double)
    case invoke(path: HeistInvocationPath, argument: HeistArgument)
    case heist(name: String?)
    case warn(message: String)
    case fail(message: String)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case command
        case predicate
        case timeout
        case parameter
        case count
        case matching
        case limit
        case path
        case argument
        case name
        case message
    }

    private enum IntentType: String, Codable {
        case action
        case wait
        case conditional
        case forEachString = "for_each_string"
        case forEachElement = "for_each_element"
        case repeatUntil = "repeat_until"
        case invoke
        case heist
        case warn
        case fail
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist step intent")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(IntentType.self, forKey: .type)
        let typeName = "\(type.rawValue) heist step intent"
        switch type {
        case .action:
            try container.rejectIncompatibleFields(allowing: [.type, .command], typeName: typeName)
            self = .action(command: try container.decode(HeistActionCommand.self, forKey: .command))
        case .wait:
            try container.rejectIncompatibleFields(allowing: [.type, .predicate, .timeout], typeName: typeName)
            self = .wait(
                predicate: try container.decode(AccessibilityPredicate.self, forKey: .predicate),
                timeout: try container.decode(Double.self, forKey: .timeout)
            )
        case .conditional:
            try container.rejectIncompatibleFields(allowing: [.type], typeName: typeName)
            self = .conditional
        case .forEachString:
            try container.rejectIncompatibleFields(allowing: [.type, .parameter, .count], typeName: typeName)
            self = .forEachString(
                parameter: try container.decode(HeistReferenceName.self, forKey: .parameter),
                count: try container.decode(Int.self, forKey: .count)
            )
        case .forEachElement:
            try container.rejectIncompatibleFields(
                allowing: [.type, .parameter, .matching, .limit],
                typeName: typeName
            )
            self = .forEachElement(
                parameter: try container.decode(HeistReferenceName.self, forKey: .parameter),
                matching: try container.decode(ElementPredicateTemplate.self, forKey: .matching),
                limit: try container.decode(Int.self, forKey: .limit)
            )
        case .repeatUntil:
            try container.rejectIncompatibleFields(allowing: [.type, .predicate, .timeout], typeName: typeName)
            self = .repeatUntil(
                predicate: try container.decode(AccessibilityPredicate.self, forKey: .predicate),
                timeout: try container.decode(Double.self, forKey: .timeout)
            )
        case .invoke:
            try container.rejectIncompatibleFields(allowing: [.type, .path, .argument], typeName: typeName)
            let components = try container.decode([String].self, forKey: .path)
            do {
                self = .invoke(
                    path: try HeistInvocationPath(components: components),
                    argument: try container.decode(HeistArgument.self, forKey: .argument)
                )
            } catch let error as HeistInvocationPath.ValidationError {
                throw DecodingError.dataCorruptedError(
                    forKey: .path,
                    in: container,
                    debugDescription: error.description
                )
            }
        case .heist:
            try container.rejectIncompatibleFields(allowing: [.type, .name], typeName: typeName)
            self = .heist(name: try container.decodeIfPresent(String.self, forKey: .name))
        case .warn:
            try container.rejectIncompatibleFields(allowing: [.type, .message], typeName: typeName)
            self = .warn(message: try container.decode(String.self, forKey: .message))
        case .fail:
            try container.rejectIncompatibleFields(allowing: [.type, .message], typeName: typeName)
            self = .fail(message: try container.decode(String.self, forKey: .message))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .action(let command):
            try container.encode(IntentType.action, forKey: .type)
            try container.encode(command, forKey: .command)
        case .wait(let predicate, let timeout):
            try container.encode(IntentType.wait, forKey: .type)
            try container.encode(predicate, forKey: .predicate)
            try container.encode(timeout, forKey: .timeout)
        case .conditional:
            try container.encode(IntentType.conditional, forKey: .type)
        case .forEachString(let parameter, let count):
            try container.encode(IntentType.forEachString, forKey: .type)
            try container.encode(parameter, forKey: .parameter)
            try container.encode(count, forKey: .count)
        case .forEachElement(let parameter, let matching, let limit):
            try container.encode(IntentType.forEachElement, forKey: .type)
            try container.encode(parameter, forKey: .parameter)
            try container.encode(matching, forKey: .matching)
            try container.encode(limit, forKey: .limit)
        case .repeatUntil(let predicate, let timeout):
            try container.encode(IntentType.repeatUntil, forKey: .type)
            try container.encode(predicate, forKey: .predicate)
            try container.encode(timeout, forKey: .timeout)
        case .invoke(let path, let argument):
            try container.encode(IntentType.invoke, forKey: .type)
            try container.encode(path.components, forKey: .path)
            try container.encode(argument, forKey: .argument)
        case .heist(let name):
            try container.encode(IntentType.heist, forKey: .type)
            try container.encodeIfPresent(name, forKey: .name)
        case .warn(let message):
            try container.encode(IntentType.warn, forKey: .type)
            try container.encode(message, forKey: .message)
        case .fail(let message):
            try container.encode(IntentType.fail, forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }

}
