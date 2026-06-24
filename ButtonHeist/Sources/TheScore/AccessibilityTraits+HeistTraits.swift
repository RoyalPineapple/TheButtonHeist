import ThePlans
import AccessibilitySnapshotModel

public extension AccessibilityTraits {
    static let alert = AccessibilityTraits(rawValue: UInt64(1) << 56)

    private static let heistKnownTraits: [(trait: AccessibilityTraits, name: String)] = [
        (.button, HeistTrait.button.rawValue),
        (.link, HeistTrait.link.rawValue),
        (.image, HeistTrait.image.rawValue),
        (.selected, HeistTrait.selected.rawValue),
        (.playsSound, HeistTrait.playsSound.rawValue),
        (.keyboardKey, HeistTrait.keyboardKey.rawValue),
        (.staticText, HeistTrait.staticText.rawValue),
        (.summaryElement, HeistTrait.summaryElement.rawValue),
        (.notEnabled, HeistTrait.notEnabled.rawValue),
        (.updatesFrequently, HeistTrait.updatesFrequently.rawValue),
        (.searchField, HeistTrait.searchField.rawValue),
        (.startsMediaSession, HeistTrait.startsMediaSession.rawValue),
        (.adjustable, HeistTrait.adjustable.rawValue),
        (.allowsDirectInteraction, HeistTrait.allowsDirectInteraction.rawValue),
        (.causesPageTurn, HeistTrait.causesPageTurn.rawValue),
        (.header, HeistTrait.header.rawValue),
        (.tabBar, HeistTrait.tabBar.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 17), HeistTrait.webContent.rawValue),
        (.textEntry, HeistTrait.textEntry.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 19), HeistTrait.pickerElement.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 20), HeistTrait.radioButton.rawValue),
        (.isEditing, HeistTrait.isEditing.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 22), HeistTrait.launchIcon.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 23), HeistTrait.statusBarElement.rawValue),
        (.secureTextField, HeistTrait.secureTextField.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 25), HeistTrait.inactive.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 26), HeistTrait.footer.rawValue),
        (.backButton, HeistTrait.backButton.rawValue),
        (.tabBarItem, HeistTrait.tabBarItem.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 29), HeistTrait.autoCorrectCandidate.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 30), HeistTrait.deleteKey.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 31), HeistTrait.selectionDismissesItem.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 32), HeistTrait.visited.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 34), HeistTrait.spacer.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 35), HeistTrait.tableIndex.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 36), HeistTrait.map.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 37), HeistTrait.textOperationsAvailable.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 38), HeistTrait.draggable.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 40), HeistTrait.popupButton.rawValue),
        (.textArea, HeistTrait.textArea.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 52), HeistTrait.menuItem.rawValue),
        (.switchButton, HeistTrait.switchButton.rawValue),
        (.alert, HeistTrait.alert.rawValue),
    ]

    static var knownTraitNames: Set<String> {
        Set(heistKnownTraits.map { $0.name })
    }

    static func fromNames(_ names: [String]) -> AccessibilityTraits {
        var value: UInt64 = 0
        for name in names {
            if let known = heistKnownTraits.first(where: { $0.name == name }) {
                value |= known.trait.rawValue
            }
        }
        return AccessibilityTraits(rawValue: value)
    }

    var heistTraits: [HeistTrait] {
        Self.heistKnownTraits.compactMap { contains($0.trait) ? HeistTrait(rawValue: $0.name) : nil }
    }

    var heistTraitNames: [String] {
        Self.heistKnownTraits.compactMap { contains($0.trait) ? $0.name : nil }
    }
}
