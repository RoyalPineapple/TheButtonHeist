import SwiftUI
import AccessibilityBridgeProtocol

struct HierarchyListView: View {
    let elements: [AccessibilityElementData]
    @State private var selectedElement: AccessibilityElementData?

    var body: some View {
        HSplitView {
            // Element list
            List(elements, id: \.traversalIndex, selection: $selectedElement) { element in
                ElementRowView(element: element)
            }
            .frame(minWidth: 300)

            // Detail pane
            if let element = selectedElement {
                ElementDetailView(element: element)
                    .frame(minWidth: 250)
            } else {
                Text("Select an element")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct ElementRowView: View {
    let element: AccessibilityElementData

    var body: some View {
        HStack(spacing: 8) {
            Text("[\(element.traversalIndex)]")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(element.label ?? element.description)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if !element.traits.isEmpty {
                    Text(element.traits.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Show icon for primary trait
            if let icon = primaryTraitIcon {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 2)
    }

    private var primaryTraitIcon: String? {
        if element.traits.contains("button") { return "hand.tap" }
        if element.traits.contains("link") { return "link" }
        if element.traits.contains("image") { return "photo" }
        if element.traits.contains("header") { return "textformat.size.larger" }
        if element.traits.contains("adjustable") { return "slider.horizontal.3" }
        if element.traits.contains("searchField") { return "magnifyingglass" }
        if element.traits.contains("staticText") { return "text.alignleft" }
        return nil
    }
}

struct ElementDetailView: View {
    let element: AccessibilityElementData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Description
                DetailSection(title: "Description") {
                    Text(element.description)
                        .textSelection(.enabled)
                }

                // Label
                if let label = element.label {
                    DetailSection(title: "Label") {
                        Text(label)
                            .textSelection(.enabled)
                    }
                }

                // Value
                if let value = element.value {
                    DetailSection(title: "Value") {
                        Text(value)
                            .textSelection(.enabled)
                    }
                }

                // Hint
                if let hint = element.hint {
                    DetailSection(title: "Hint") {
                        Text(hint)
                            .textSelection(.enabled)
                    }
                }

                // Traits
                if !element.traits.isEmpty {
                    DetailSection(title: "Traits") {
                        FlowLayout(spacing: 4) {
                            ForEach(element.traits, id: \.self) { trait in
                                Text(trait)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                // Frame
                DetailSection(title: "Frame") {
                    Text("(\(Int(element.frameX)), \(Int(element.frameY))) \(Int(element.frameWidth))×\(Int(element.frameHeight))")
                        .font(.system(.body, design: .monospaced))
                }

                // Activation Point
                DetailSection(title: "Activation Point") {
                    Text("(\(Int(element.activationPointX)), \(Int(element.activationPointY)))")
                        .font(.system(.body, design: .monospaced))
                }

                // Identifier
                if let identifier = element.identifier, !identifier.isEmpty {
                    DetailSection(title: "Accessibility Identifier") {
                        Text(identifier)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                // Custom Actions
                if !element.customActions.isEmpty {
                    DetailSection(title: "Custom Actions") {
                        ForEach(element.customActions, id: \.self) { action in
                            Label(action, systemImage: "hand.tap")
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }
}

// Simple flow layout for traits
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}

#Preview {
    HierarchyListView(elements: [
        AccessibilityElementData(
            traversalIndex: 0,
            description: "Hello, World!",
            label: "Hello, World!",
            value: nil,
            traits: ["staticText"],
            identifier: nil,
            hint: nil,
            frameX: 0,
            frameY: 100,
            frameWidth: 393,
            frameHeight: 44,
            activationPointX: 196.5,
            activationPointY: 122,
            customActions: []
        ),
        AccessibilityElementData(
            traversalIndex: 1,
            description: "Button",
            label: "Tap me",
            value: nil,
            traits: ["button"],
            identifier: "tapButton",
            hint: "Double tap to activate",
            frameX: 100,
            frameY: 200,
            frameWidth: 100,
            frameHeight: 44,
            activationPointX: 150,
            activationPointY: 222,
            customActions: ["Delete", "Edit"]
        )
    ])
}
