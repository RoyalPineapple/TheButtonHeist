import ArgumentParser
import Foundation

// MARK: - Output Helpers

/// Write to stderr (status messages)
func logStatus(_ message: String) {
    fputs("\(message)\n", stderr)
}

/// Write to stdout (data output)
func writeOutput(_ message: String) {
    print(message)
    fflush(stdout)
}

// MARK: - JSON Array Loading

/// Parse a JSON array from either an inline string or a file path.
/// Exactly one of `inline` or `fromFile` must be supplied.
///
/// Used by commands that take a structured array payload (`run_batch`'s
/// steps, `draw_path`'s points, `draw_bezier`'s segments) to keep the
/// file-vs-inline decision uniform across the CLI surface. Throws
/// `ValidationError` on missing, ambiguous, unreadable, or malformed
/// input so the error surfaces through ArgumentParser rather than as a
/// generic crash.
func loadJSONArray(
    inline: String?,
    fromFile path: String?,
    optionName: String
) throws -> [Any] {
    switch (inline, path) {
    case (nil, nil):
        throw ValidationError("Must supply either --\(optionName) or --\(optionName)-from-file")
    case (.some, .some):
        throw ValidationError("--\(optionName) and --\(optionName)-from-file are mutually exclusive")
    case (.some(let literal), nil):
        return try parseJSONArray(from: Data(literal.utf8), source: "--\(optionName)")
    case (nil, .some(let filePath)):
        let expanded = (filePath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ValidationError("Failed to read \(filePath): \(error.localizedDescription)")
        }
        return try parseJSONArray(from: data, source: filePath)
    }
}

private func parseJSONArray(from data: Data, source: String) throws -> [Any] {
    let parsed: Any
    do {
        parsed = try JSONSerialization.jsonObject(with: data, options: [])
    } catch {
        throw ValidationError("\(source) is not valid JSON: \(error.localizedDescription)")
    }
    guard let array = parsed as? [Any] else {
        throw ValidationError("\(source) must be a JSON array")
    }
    return array
}
