import Foundation

import TheScore

struct PublicInterfaceRendering: Encodable {
    let state: String
    let reasonCode: String?
    let observedElementCount: Int
    let renderedElementCount: Int
    let omittedElementCount: Int
    let visibleElementBudget: Int?
    let totalNodeBudget: Int?

    init(
        state: String,
        reasonCode: String?,
        observedElementCount: Int,
        renderedElementCount: Int,
        omittedElementCount: Int,
        visibleElementBudget: Int?,
        totalNodeBudget: Int?
    ) {
        self.state = state
        self.reasonCode = reasonCode
        self.observedElementCount = observedElementCount
        self.renderedElementCount = renderedElementCount
        self.omittedElementCount = omittedElementCount
        self.visibleElementBudget = visibleElementBudget
        self.totalNodeBudget = totalNodeBudget
    }

    init(projection: InterfaceRenderingProjection) {
        self.state = projection.state.rawValue
        self.reasonCode = projection.reason?.rawValue
        self.observedElementCount = projection.observedElementCount
        self.renderedElementCount = projection.renderedElementCount
        self.omittedElementCount = projection.omittedElementCount
        self.visibleElementBudget = projection.visibleElementBudget
        self.totalNodeBudget = projection.totalNodeBudget
    }
}

enum PublicTreeNode: Encodable {
    case element(PublicElement)
    case container(PublicContainer)

    private enum CodingKeys: String, CodingKey {
        case element
        case container
    }

    init(projection: InterfaceNodeProjection, detail: InterfaceDetail) {
        switch projection {
        case .element(let element):
            self = .element(PublicElement(
                element: element.element,
                detail: detail,
                order: element.order
            ))
        case .container(let container):
            self = .container(PublicContainer(projection: container, detail: detail))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .element(let element):
            try container.encode(element, forKey: .element)
        case .container(let node):
            try container.encode(node, forKey: .container)
        }
    }

    var elementCount: Int {
        switch self {
        case .element:
            return 1
        case .container(let container):
            return container.children.reduce(0) { $0 + $1.elementCount }
        }
    }
}
