import Foundation

extension HeistCanonicalSwiftDSLRenderer {
    func renderTraits(_ label: String, _ traits: [HeistTrait]) -> String? {
        guard !traits.isEmpty else { return nil }
        return "\(label): [\(traits.map { ".\($0.rawValue)" }.joined(separator: ", "))]"
    }

    func renderTimeout(_ timeout: Double) -> String {
        abs(timeout - defaultWaitTimeout) < 0.000_001 ? "" : ", timeout: .seconds(\(decimal(timeout)))"
    }

    func validateParameter(_ parameter: String) throws {
        guard HeistParameterName.isValid(parameter) else {
            throw HeistCanonicalSwiftDSLError.invalidParameter(parameter)
        }
    }

    func validateParameter(_ parameter: HeistReferenceName) throws {
        try validateParameter(parameter.rawValue)
    }

    func line(_ text: String, _ indent: Int) -> String {
        "\(String(repeating: "    ", count: indent))\(text)"
    }

    func quote(_ value: String) -> String {
        if let data = try? JSONEncoder().encode(value),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    func quote(_ value: HeistReferenceName) -> String {
        quote(value.rawValue)
    }

    func decimal(_ value: Double) -> String {
        guard value.isFinite else { return "\(value)" }
        let rounded = value.rounded()
        if abs(value - rounded) < 0.000_001 { return "\(Int(rounded))" }
        var text = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }
}
