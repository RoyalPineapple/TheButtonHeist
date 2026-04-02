import Foundation

/// Global actor that serializes all Button Heist operations onto a single cooperative thread.
@globalActor
public actor ButtonHeistActor {
    public static let shared = ButtonHeistActor()

    /// Execute a closure on the ButtonHeistActor.
    public static func run<T: Sendable>(
        resultType: T.Type = T.self,
        body: @ButtonHeistActor @Sendable () throws -> T
    ) async rethrows -> T {
        try await body()
    }
}
