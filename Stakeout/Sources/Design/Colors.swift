import SwiftUI

extension Color {
    struct Tree {
        static let background = Color(nsColor: .windowBackgroundColor)
        static let rowHover = Color.primary.opacity(0.04)
        static let rowSelected = Color.accentColor.opacity(0.15)
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.primary.opacity(0.3)
        static let divider = Color.primary.opacity(0.1)
    }
}
