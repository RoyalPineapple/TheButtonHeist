import Foundation

@globalActor
public actor ButtonHeistActor {
    public static let shared = ButtonHeistActor()

    public static func run<T: Sendable>(
        resultType: T.Type = T.self,
        body: @ButtonHeistActor @Sendable () throws -> T
    ) async rethrows -> T {
        try await body()
    }
}
