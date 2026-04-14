import Foundation

extension String {
    /// Validate this string as an output file path. Returns the standardized URL,
    /// or nil if the path is empty or contains directory traversal (`..`).
    func validatedOutputURL() -> URL? {
        guard !isEmpty else { return nil }
        let components = split(separator: "/")
        guard !components.contains("..") else { return nil }
        return URL(fileURLWithPath: self).standardized
    }
}
