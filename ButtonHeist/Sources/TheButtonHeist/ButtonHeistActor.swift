import Foundation

/// Global actor that serializes all Button Heist operations onto a single cooperative thread.
@globalActor
public actor ButtonHeistActor {
    public static let shared = ButtonHeistActor()
}
