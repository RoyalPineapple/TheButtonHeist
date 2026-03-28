import Foundation

extension Error {
    /// Extract the best available user-facing error message.
    /// Prefers `LocalizedError.errorDescription`, falls back to `localizedDescription`.
    public var displayMessage: String {
        if let localized = self as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return localizedDescription
    }
}
