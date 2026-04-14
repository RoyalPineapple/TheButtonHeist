import Foundation
import TheScore

/// Type-safe accessors for `[String: Any]` dictionaries from CLI/MCP argument parsing.
/// Converts loosely-typed JSON values (String, Int, Double, Bool) at the system boundary.
extension Dictionary where Key == String, Value == Any {

    func string(_ key: String) -> String? {
        self[key] as? String
    }

    func integer(_ key: String) -> Int? {
        if let value = self[key] as? Int { return value }
        if let value = self[key] as? Double { return Int(value) }
        if let value = self[key] as? String { return Int(value) }
        return nil
    }

    func boolean(_ key: String) -> Bool? {
        if let value = self[key] as? Bool { return value }
        if let value = self[key] as? Int { return value != 0 }
        if let value = self[key] as? String { return value == "true" || value == "1" }
        return nil
    }

    func number(_ key: String) -> Double? {
        number(self[key])
    }

    func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    func unitPoint(_ key: String) -> UnitPoint? {
        guard let dictionary = self[key] as? [String: Any],
              let x = dictionary.number("x"),
              let y = dictionary.number("y") else { return nil }
        return UnitPoint(x: x, y: y)
    }
}
