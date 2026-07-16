import Foundation

enum HeistRuntimePayloadContractValidator {
    static func validate<T: Codable>(_ payload: T) throws {
        let data = try JSONEncoder().encode(payload)
        _ = try JSONDecoder().decode(T.self, from: data)
    }
}
