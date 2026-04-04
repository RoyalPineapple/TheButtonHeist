import Foundation

/// Global actor that serializes all Button Heist operations onto a single cooperative thread.
@globalActor
public actor ButtonHeistActor {
    public static let shared = ButtonHeistActor()

    /// Execute a closure on the ButtonHeistActor.
    ///
    /// The generic `E` preserves the caller's typed error: if `body` throws `FenceError`,
    /// this method throws `FenceError` — not `any Error`. Callers that pass a non-throwing
    /// closure get a non-throwing call site automatically.
    public static func run<T: Sendable, E: Error>(
        resultType: T.Type = T.self,
        body: @ButtonHeistActor @Sendable () throws(E) -> T
    ) async throws(E) -> T {
        try await body()
    }
}
