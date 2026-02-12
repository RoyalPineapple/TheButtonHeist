import SwiftUI
import ButtonHeist

// MARK: - Tree Display Model

struct TreeDisplayNode: Identifiable {
    let id: String
    let isContainer: Bool
    let containerData: TheGoods.Group?
    let element: UIElement?
    var children: [TreeDisplayNode]

    var displayLabel: String {
        if let element = element {
            return element.label ?? element.description
        }
        if let container = containerData {
            if let label = container.label, !label.isEmpty {
                return label
            }
            return ElementStyling.displayName(forContainerType: container.type)
        }
        return "Unknown"
    }

    var optionalChildren: [TreeDisplayNode]? {
        children.isEmpty ? nil : children
    }
}

// MARK: - Tree Builder

enum TreeBuilder {
    static func buildDisplayNodes(
        from tree: [ElementNode],
        elements: [UIElement]
    ) -> [TreeDisplayNode] {
        let elementMap = Dictionary(uniqueKeysWithValues: elements.map { ($0.order, $0) })
        return tree.map { convertNode($0, elementMap: elementMap) }
    }

    private static func convertNode(
        _ node: ElementNode,
        elementMap: [Int: UIElement]
    ) -> TreeDisplayNode {
        switch node {
        case .element(let order):
            let element = elementMap[order]
            return TreeDisplayNode(
                id: "element-\(order)",
                isContainer: false,
                containerData: nil,
                element: element,
                children: []
            )
        case .container(let containerData, let children):
            let childNodes = children.map { convertNode($0, elementMap: elementMap) }
            let id = "container-\(containerData.type)-\(containerData.frameX)-\(containerData.frameY)"
            return TreeDisplayNode(
                id: id,
                isContainer: true,
                containerData: containerData,
                element: nil,
                children: childNodes
            )
        }
    }
}

// MARK: - Tree View

struct HierarchyTreeView: View {
    let tree: [ElementNode]
    let elements: [UIElement]
    @Binding var selectedElement: UIElement?

    private var displayNodes: [TreeDisplayNode] {
        TreeBuilder.buildDisplayNodes(from: tree, elements: elements)
    }

    var body: some View {
        List(displayNodes, id: \.id, children: \.optionalChildren, selection: Binding(
            get: { selectedElement.map { "element-\($0.order)" } },
            set: { newValue in
                if let id = newValue, id.hasPrefix("element-") {
                    let indexString = id.dropFirst("element-".count)
                    if let index = Int(indexString) {
                        selectedElement = elements.first { $0.order == index }
                    }
                } else {
                    selectedElement = nil
                }
            }
        )) { node in
            TreeRowView(node: node)
                .tag(node.id)
        }
    }
}

// MARK: - Row View

struct TreeRowView: View {
    let node: TreeDisplayNode

    var body: some View {
        HStack(spacing: 6) {
            if node.isContainer {
                containerContent
            } else {
                elementContent
            }
            Spacer()
        }
        .frame(height: TreeSpacing.rowHeight)
    }

    @ViewBuilder
    private var containerContent: some View {
        if let container = node.containerData {
            Image(systemName: ElementStyling.iconName(forContainerType: container.type))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ElementStyling.color(forContainerType: container.type))
                .frame(width: 16)

            Text(node.displayLabel)
                .font(.Tree.elementLabel)
                .fontWeight(.medium)
                .foregroundColor(Color.Tree.textPrimary)
                .lineLimit(1)

            if container.type == "tabBar" {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var elementContent: some View {
        if let element = node.element {
            Circle()
                .fill(ElementStyling.color(for: element))
                .frame(width: 8, height: 8)

            Image(systemName: ElementStyling.iconName(for: element))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ElementStyling.color(for: element))
                .frame(width: 16)

            Text(node.displayLabel)
                .font(.Tree.elementLabel)
                .foregroundColor(Color.Tree.textPrimary)
                .lineLimit(1)
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var selectedElement: UIElement? = nil
    let sampleElements = [
        UIElement(
            order: 0,
            description: "Home",
            label: "Home",
            value: nil,
            identifier: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: ["activate"]
        ),
        UIElement(
            order: 1,
            description: "Search",
            label: "Search",
            value: nil,
            identifier: nil,
            frameX: 100, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: ["activate"]
        ),
        UIElement(
            order: 2,
            description: "Welcome",
            label: "Welcome to the app",
            value: nil,
            identifier: nil,
            frameX: 0, frameY: 100, frameWidth: 300, frameHeight: 44,
            actions: []
        )
    ]
    let sampleTree: [ElementNode] = [
        .container(
            TheGoods.Group(
                type: "tabBar",
                label: "Tab Bar",
                value: nil,
                identifier: nil,
                frameX: 0, frameY: 0, frameWidth: 400, frameHeight: 50
            ),
            children: [
                .element(order: 0),
                .element(order: 1)
            ]
        ),
        .container(
            TheGoods.Group(
                type: "landmark",
                label: "Main Content",
                value: nil,
                identifier: nil,
                frameX: 0, frameY: 50, frameWidth: 400, frameHeight: 600
            ),
            children: [
                .element(order: 2)
            ]
        )
    ]

    HierarchyTreeView(
        tree: sampleTree,
        elements: sampleElements,
        selectedElement: $selectedElement
    )
}
