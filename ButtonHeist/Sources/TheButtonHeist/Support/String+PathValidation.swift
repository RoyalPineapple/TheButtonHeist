import Foundation

extension String {
    /// Validate this string as an output file path. Returns the standardized URL,
    /// or nil if the path is empty, contains directory traversal (`..`), or
    /// includes control characters.
    func validatedOutputURL() -> URL? {
        guard !isEmpty else { return nil }
        guard !unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0)
        }) else { return nil }
        let components = split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains("..") else { return nil }
        return URL(fileURLWithPath: self).standardized
    }
}
