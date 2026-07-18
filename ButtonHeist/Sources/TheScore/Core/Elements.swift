import ThePlans
import Foundation

// MARK: - Slugify

/// Slugify a string for use as a machine-readable identifier.
/// Lowercase, replace non-alphanumeric runs with `_`, trim underscores, cap at 24 characters.
/// Shared by heistId synthesis (TheVault) and screenId derivation (Interface, ActionResult).
public func slugify(_ text: String?) -> String? {
    guard let text, !text.isEmpty else { return nil }
    let slug = text.lowercased()
        .replacing(/[^a-z0-9]+/, with: "_")
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    guard !slug.isEmpty else { return nil }
    return String(slug.prefix(24))
}

// MARK: - Identifier Stability

/// Whether an accessibility identifier is stable (developer-assigned) vs runtime-generated.
/// Returns false for identifiers containing UUIDs — these are SwiftUI runtime artifacts
/// that change across app launches and should not be used for element identity.
/// Shared by heistId synthesis (TheVault) and evidence-based matcher suggestions.
public func isStableIdentifier(_ identifier: String) -> Bool {
    identifier.range(of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
                     options: .regularExpression) == nil
}
