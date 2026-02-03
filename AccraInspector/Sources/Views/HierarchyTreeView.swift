import SwiftUI
import AccraCore

// MARK: - Tree Display Model

struct TreeDisplayNode: Identifiable {
    let id: String
    let isContainer: Bool
    let containerData: AccessibilityContainerData?
    let element: AccessibilityElementData?
    var children: [TreeDisplayNode]

    var displayLabel: String {
        if let element = element {
            return element.label ?? element.description
        }
        if let container = containerData {
            if let label = container.label, !label.isEmpty {
                return label
            }
            return ElementStyling.displayName(forContainerType: container.containerType)
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
        from tree: [AccessibilityHierarchyNode],
        elements: [AccessibilityElementData]
    ) -> [TreeDisplayNode] {
        let elementMap = Dictionary(uniqueKeysWithValues: elements.map { ($0.traversalIndex, $0) })
        return tree.map { convertNode($0, elementMap: elementMap) }
    }

    private static func convertNode(
        _ node: AccessibilityHierarchyNode,
        elementMap: [Int: AccessibilityElementData]
    ) -> TreeDisplayNode {
        switch node {
        case .element(let traversalIndex):
            let element = elementMap[traversalIndex]
            return TreeDisplayNode(
                id: "element-\(traversalIndex)",
                isContainer: false,
                containerData: nil,
                element: element,
                children: []
            )
        case .container(let containerData, let children):
            let childNodes = children.map { convertNode($0, elementMap: elementMap) }
            let id = "container-\(containerData.containerType)-\(containerData.frameX)-\(containerData.frameY)"
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
    let tree: [AccessibilityHierarchyNode]
    let elements: [AccessibilityElementData]
    @Binding var selectedElement: AccessibilityElementData?

    private var displayNodes: [TreeDisplayNode] {
        TreeBuilder.buildDisplayNodes(from: tree, elements: elements)
    }

    var body: some View {
        List(displayNodes, id: \.id, children: \.optionalChildren, selection: Binding(
            get: { selectedElement.map { "element-\($0.traversalIndex)" } },
            set: { newValue in
                if let id = newValue, id.hasPrefix("element-") {
                    let indexString = id.dropFirst("element-".count)
                    if let index = Int(indexString) {
                        selectedElement = elements.first { $0.traversalIndex == index }
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
            Image(systemName: ElementStyling.iconName(forContainerType: container.containerType))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ElementStyling.color(forContainerType: container.containerType))
                .frame(width: 16)

            Text(node.displayLabel)
                .font(.Tree.elementLabel)
                .fontWeight(.medium)
                .foregroundColor(Color.Tree.textPrimary)
                .lineLimit(1)

            if container.traits.contains("tabBar") {
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
    @Previewable @State var selectedElement: AccessibilityElementData? = nil
    let sampleElements = [
        AccessibilityElementData(
            traversalIndex: 0,
            description: "Home",
            label: "Home",
            value: nil,
            traits: ["button", "selected"],
            identifier: nil,
            hint: nil,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            activationPointX: 50, activationPointY: 22,
            customActions: []
        ),
        AccessibilityElementData(
            traversalIndex: 1,
            description: "Search",
            label: "Search",
            value: nil,
            traits: ["button"],
            identifier: nil,
            hint: nil,
            frameX: 100, frameY: 0, frameWidth: 100, frameHeight: 44,
            activationPointX: 150, activationPointY: 22,
            customActions: []
        ),
        AccessibilityElementData(
            traversalIndex: 2,
            description: "Welcome",
            label: "Welcome to the app",
            value: nil,
            traits: ["header"],
            identifier: nil,
            hint: nil,
            frameX: 0, frameY: 100, frameWidth: 300, frameHeight: 44,
            activationPointX: 150, activationPointY: 122,
            customActions: []
        )
    ]
    let sampleTree: [AccessibilityHierarchyNode] = [
        .container(
            AccessibilityContainerData(
                containerType: "semanticGroup",
                label: "Tab Bar",
                value: nil,
                identifier: nil,
                frameX: 0, frameY: 0, frameWidth: 400, frameHeight: 50,
                traits: ["tabBar"]
            ),
            children: [
                .element(traversalIndex: 0),
                .element(traversalIndex: 1)
            ]
        ),
        .container(
            AccessibilityContainerData(
                containerType: "landmark",
                label: "Main Content",
                value: nil,
                identifier: nil,
                frameX: 0, frameY: 50, frameWidth: 400, frameHeight: 600,
                traits: []
            ),
            children: [
                .element(traversalIndex: 2)
            ]
        )
    ]

    HierarchyTreeView(
        tree: sampleTree,
        elements: sampleElements,
        selectedElement: $selectedElement
    )
}
