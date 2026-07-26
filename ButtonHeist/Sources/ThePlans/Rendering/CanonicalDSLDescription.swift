import Foundation

/// One value's DSL spelling, for the `description` of a type the DSL can write.
///
/// Anything authorable describes itself the way it was authored, so a failure
/// message names something you can paste back into a heist instead of a second
/// vocabulary invented for reports.
enum CanonicalDSLDescription {
    /// The renderer rejects a `.ref` whose name is unbound, which is how
    /// rendering a whole plan refuses to emit Swift that would not compile.
    /// Describing one value in isolation has no scope to bind against, so it
    /// renders under `.preservingReferences` — the policy that prints a
    /// reference as written — and the rejection cannot arise.
    ///
    /// The `catch` is therefore unreachable rather than merely unlikely, and it
    /// still has to say something: it names the type, which is the one fact a
    /// description always has and the one a reader needs to find the value.
    static func render<Value>(
        _ value: Value,
        _ body: (HeistCanonicalSwiftDSLRenderer, RenderEnvironment) throws -> String
    ) -> String {
        do {
            return try body(HeistCanonicalSwiftDSLRenderer(), .preservingReferences)
        } catch {
            return "<\(Value.self)>"
        }
    }
}
