import Foundation

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
    let frameX: Double?
    let frameY: Double?
    let frameWidth: Double?
    let frameHeight: Double?
    let activationPointX: Double?
    let activationPointY: Double?
    let order: Int?

    init(element: HeistElement, detail: InterfaceDetail, order: Int? = nil) {
        self.traits = element.traits.map(\.rawValue)
        let meaningfulActions = FenceResponse.meaningfulActions(element)
        self.actions = meaningfulActions.isEmpty ? nil : meaningfulActions.map(\.description)
        self.rotors = element.rotors?.isEmpty == false ? element.rotors?.map { $0.name } : nil
        self.label = element.label
        self.value = element.value
        self.identifier = element.identifier
        self.order = order
        guard detail == .full else {
            self.hint = nil
            self.customContent = nil
            self.frameX = nil
            self.frameY = nil
            self.frameWidth = nil
            self.frameHeight = nil
            self.activationPointX = nil
            self.activationPointY = nil
            return
        }
        self.hint = element.hint
        self.customContent = element.customContent.map { PublicCustomContent(items: $0) }
        self.frameX = element.screenFrame?.x.value
        self.frameY = element.screenFrame?.y.value
        self.frameWidth = element.screenFrame?.width.value
        self.frameHeight = element.screenFrame?.height.value
        self.activationPointX = element.activationPointX
        self.activationPointY = element.activationPointY
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
