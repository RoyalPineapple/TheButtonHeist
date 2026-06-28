import Foundation
import MCP
@_spi(ButtonHeistInternals) import ButtonHeist
import TheScore

enum MCPArgumentInputPreflight {
    static func validate(
        _ arguments: [String: Value]?,
        context: String = "MCP arguments",
        maxBytes: Int = PublicMachineInputLimits.maxRequestBytes,
        maxNestingDepth: Int = PublicMachineInputLimits.maxNestingDepth,
        maxTotalObjectKeys: Int = PublicMachineInputLimits.maxTotalObjectKeys
    ) throws {
        try PublicJSONValuePreflight.validateObject(
            arguments ?? [:],
            policy: PublicJSONInputPolicy(
                maxBytes: maxBytes,
                maxNestingDepth: maxNestingDepth,
                maxTotalObjectKeys: maxTotalObjectKeys
            ),
            context: context,
            node: jsonValueNode
        )
    }

    static func heistValues(_ arguments: [String: Value]?) throws -> [String: HeistValue] {
        try PublicJSONHeistValueConverter.convertObject(
            arguments ?? [:],
            policy: PublicJSONInputPolicy(
                maxBytes: PublicMachineInputLimits.maxRequestBytes,
                maxNestingDepth: PublicMachineInputLimits.maxNestingDepth,
                maxTotalObjectKeys: PublicMachineInputLimits.maxTotalObjectKeys
            ),
            context: "MCP arguments",
            node: jsonValueNode
        )
    }

    private static func jsonValueNode(_ value: Value) -> PublicJSONValueNode<Value> {
        switch value {
        case .null:
            return .null
        case .bool(let bool):
            return .bool(bool)
        case .int(let int):
            return .int(int)
        case .double(let double):
            return .double(double)
        case .string(let string):
            return .string(string)
        case let .data(mimeType, data):
            return .data(mimeType: mimeType, byteCount: data.count)
        case .array(let values):
            return .array(values)
        case .object(let object):
            return .object(object)
        }
    }
}
