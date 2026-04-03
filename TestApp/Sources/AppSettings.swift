import SwiftUI

@Observable
class AppSettings {
    var colorScheme: AppColorScheme = .system
    var accentColor: AppAccentColor = .blue
    var textSize: AppTextSize = .medium
    var username: String = ""
    var showCompletedTodos: Bool = true
    var compactMode: Bool = false

    enum AppColorScheme: String, CaseIterable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"

        var resolved: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    enum AppAccentColor: String, CaseIterable {
        case blue = "Blue"
        case purple = "Purple"
        case green = "Green"
        case orange = "Orange"

        var color: Color {
            switch self {
            case .blue: return .blue
            case .purple: return .purple
            case .green: return .green
            case .orange: return .orange
            }
        }
    }

    enum AppTextSize: String, CaseIterable {
        case small = "Small"
        case medium = "Medium"
        case large = "Large"

        var dynamicTypeSize: DynamicTypeSize {
            switch self {
            case .small: return .small
            case .medium: return .medium
            case .large: return .xLarge
            }
        }
    }
}
