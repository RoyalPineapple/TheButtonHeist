import ArgumentParser
import ButtonHeist
import Foundation

enum ExpectationArgumentParser {
    static func parse(_ rawValue: String) throws -> HeistValue {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let shorthand = shorthandType(for: trimmed) {
            return .object([FenceParameterKey.type.rawValue: .string(shorthand)])
        }

        guard trimmed.first == "{" else {
            throw ValidationError("Expected expectation shorthand screen_changed/elements_changed or a JSON object")
        }

        do {
            let data = Data(trimmed.utf8)
            let value = try JSONDecoder().decode(HeistValue.self, from: data)
            guard case .object = value else {
                throw ValidationError("Expected expectation JSON to decode as an object")
            }
            return value
        } catch let error as ValidationError {
            throw error
        } catch {
            throw ValidationError("Invalid expectation JSON: \(error.localizedDescription)")
        }
    }

    private static func shorthandType(for value: String) -> String? {
        switch value {
        case "screen_changed":
            return "screen_changed"
        case "elements_changed":
            return "elements_changed"
        default:
            return nil
        }
    }
}
