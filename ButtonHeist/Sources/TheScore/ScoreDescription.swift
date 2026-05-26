import Foundation

enum ScoreDescription {
    static func quoted(_ value: String) -> String {
        if let data = try? JSONEncoder().encode(value),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    static func stringField(_ name: String, _ value: String?) -> String? {
        nonEmpty(value).map { "\(name)=\(quoted($0))" }
    }

    static func valueField<T>(_ name: String, _ value: T?) -> String? {
        value.map { "\(name)=\($0)" }
    }

    static func listField<T>(_ name: String, _ values: [T]?) -> String? {
        guard let values, !values.isEmpty else { return nil }
        return "\(name)=\(list(values))"
    }

    static func quotedListField(_ name: String, _ values: [String]?) -> String? {
        guard let values, !values.isEmpty else { return nil }
        return "\(name)=\(quotedList(values))"
    }

    static func list<T>(_ values: [T]) -> String {
        "[\(values.map { String(describing: $0) }.joined(separator: ", "))]"
    }

    static func quotedList(_ values: [String]) -> String {
        "[\(values.map(quoted).joined(separator: ", "))]"
    }

    static func call(_ name: String, _ fields: [String]) -> String {
        fields.isEmpty ? "\(name)(*)" : "\(name)(\(fields.joined(separator: " ")))"
    }

    static func decimal(_ value: Double) -> String {
        guard value.isFinite else { return "\(value)" }
        let rounded = value.rounded()
        if abs(value - rounded) < 0.000_001 {
            return "\(Int(rounded))"
        }
        var text = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }
}
