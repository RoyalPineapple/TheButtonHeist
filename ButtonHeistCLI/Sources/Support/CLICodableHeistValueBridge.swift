import Foundation
@_spi(ButtonHeistTooling) import ButtonHeist

enum CLICodableHeistValueBridge {
    static func value<Payload: Encodable>(from payload: Payload) -> HeistValue {
        do {
            let data = try JSONEncoder().encode(payload)
            return try JSONDecoder().decode(HeistValue.self, from: data)
        } catch {
            preconditionFailure("Failed to encode \(Payload.self) as canonical HeistValue: \(error)")
        }
    }

    static func object<Payload: Encodable>(from payload: Payload) -> CLIRequestObject {
        guard case .object(let fields) = value(from: payload) else {
            preconditionFailure("Canonical \(Payload.self) payload did not encode as an object")
        }

        return CLIRequestObject(fields.map { rawKey, value in
            guard let key = FenceParameterKey(rawValue: rawKey) else {
                preconditionFailure("Canonical \(Payload.self) payload emitted unknown Fence parameter key \(rawKey)")
            }
            return (key, value)
        })
    }
}
