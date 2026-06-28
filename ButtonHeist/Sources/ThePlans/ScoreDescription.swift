import Foundation

package enum ScoreDescription {
    package static func quoted(_ value: String) -> String {
        // Boundary try?: display-only JSON string escaping, with a local
        // deterministic escape path when Foundation encoding cannot help.
        if let data = try? JSONEncoder().encode(value),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    package static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    package static func stringField(_ name: String, _ value: String?) -> String? {
        nonEmpty(value).map { "\(name)=\(quoted($0))" }
    }

    package static func stringMatchField(_ name: String, _ value: StringMatch<String>?) -> String? {
        guard let value, !value.value.isEmpty else { return nil }
        return "\(name)=\(stringMatch(value))"
    }

    package static func stringMatchFields(_ name: String, _ values: [StringMatch<String>]) -> String? {
        let fields = values.compactMap { value -> String? in
            guard !value.value.isEmpty else { return nil }
            return "\(name)=\(stringMatch(value))"
        }
        guard !fields.isEmpty else { return nil }
        return fields.joined(separator: " ")
    }

    package static func stringMatch(_ value: StringMatch<String>) -> String {
        switch value {
        case .exact(let string):
            return quoted(string)
        case .contains(let string):
            return "contains(\(quoted(string)))"
        case .prefix(let string):
            return "prefix(\(quoted(string)))"
        case .suffix(let string):
            return "suffix(\(quoted(string)))"
        }
    }

    package static func predicateCheckField(_ check: ElementPredicateCheck<String>) -> String? {
        switch check {
        case .label(let match):
            guard !match.value.isEmpty else { return nil }
            return "label=\(stringMatch(match))"
        case .identifier(let match):
            guard !match.value.isEmpty else { return nil }
            return "identifier=\(stringMatch(match))"
        case .value(let match):
            guard !match.value.isEmpty else { return nil }
            return "value=\(stringMatch(match))"
        case .traits(let traits):
            return listField("traits", traits.isEmpty ? nil : traits)
        case .excludeTraits(let traits):
            return listField("excludeTraits", traits.isEmpty ? nil : traits)
        }
    }

    package static func valueField<T>(_ name: String, _ value: T?) -> String? {
        value.map { "\(name)=\($0)" }
    }

    package static func listField<T>(_ name: String, _ values: [T]?) -> String? {
        guard let values, !values.isEmpty else { return nil }
        return "\(name)=\(list(values))"
    }

    package static func quotedListField(_ name: String, _ values: [String]?) -> String? {
        guard let values, !values.isEmpty else { return nil }
        return "\(name)=\(quotedList(values))"
    }

    package static func list<T>(_ values: [T]) -> String {
        "[\(values.map { String(describing: $0) }.joined(separator: ", "))]"
    }

    package static func quotedList(_ values: [String]) -> String {
        "[\(values.map(quoted).joined(separator: ", "))]"
    }

    package static func call(_ name: String, _ fields: [String]) -> String {
        fields.isEmpty ? "\(name)(*)" : "\(name)(\(fields.joined(separator: " ")))"
    }

    package static func decimal(_ value: Double) -> String {
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
