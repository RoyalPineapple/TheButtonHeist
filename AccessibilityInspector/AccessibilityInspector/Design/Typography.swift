import SwiftUI

extension Font {
    struct Tree {
        static let elementLabel = Font.system(size: 13, weight: .regular)
        static let elementTrait = Font.system(size: 11, weight: .regular, design: .monospaced)
        static let searchInput = Font.system(size: 14, weight: .regular)
        static let detailSectionTitle = Font.caption
        static let detailValue = Font.system(.body, design: .monospaced)
    }
}
