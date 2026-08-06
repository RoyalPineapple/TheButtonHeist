import Foundation

import ThePlans
import TheScore

struct PublicElement: Encodable {
    let traits: [String]
    let actions: [String]?
    let rotors: [String]?
    let label: String?
    let value: String?
    let identifier: String?
    let hint: String?
    let customContent: PublicCustomContent?
    let geometry: HeistElement.Geometry?
    let order: Int?
    let target: AccessibilityTarget?

    init(
        element: HeistElement,
        detail: InterfaceDetail,
        order: Int? = nil,
        target: AccessibilityTarget? = nil
    ) {
        let assertable = element.semantics.assertable
        self.traits = assertable.orderedTraits.map(\.rawValue)
        let meaningfulActions = FenceResponse.meaningfulActions(element)
        self.actions = meaningfulActions.isEmpty ? nil : meaningfulActions.map(\.description)
        self.rotors = assertable.rotors.isEmpty ? nil : assertable.orderedRotors.map(\.name)
        self.label = assertable.label
        self.value = assertable.value
        self.identifier = assertable.identifier
        self.order = order
        self.target = target
        guard detail == .full else {
            self.hint = nil
            self.customContent = nil
            self.geometry = nil
            return
        }
        self.hint = assertable.hint
        self.customContent = assertable.customContent.isEmpty
            ? nil
            : PublicCustomContent(items: assertable.orderedCustomContent)
        self.geometry = element.geometry
    }
}

struct PublicCustomContent: Encodable {
    let important: [PublicCustomContentEntry]?
    let `default`: [PublicCustomContentEntry]?

    init(items: [HeistCustomContent]) {
        let importantItems = items.filter(\.isImportant)
        let defaultItems = items.filter { !$0.isImportant }
        self.important = importantItems.isEmpty ? nil : importantItems.map { PublicCustomContentEntry(item: $0) }
        self.default = defaultItems.isEmpty ? nil : defaultItems.map { PublicCustomContentEntry(item: $0) }
    }
}

struct PublicCustomContentEntry: Encodable {
    let label: String?
    let value: String?

    init(item: HeistCustomContent) {
        self.label = item.label.isEmpty ? nil : item.label
        self.value = item.value.isEmpty ? nil : item.value
    }
}
