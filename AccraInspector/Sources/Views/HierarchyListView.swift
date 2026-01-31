import SwiftUI
import AccraCore

struct HierarchyListView: View {
    let elements: [AccessibilityElementData]
    @State private var selectedElement: AccessibilityElementData?
    @State private var searchQuery = ""

    private var filteredElements: [AccessibilityElementData] {
        guard !searchQuery.isEmpty else { return elements }
        let query = searchQuery.lowercased()
        return elements.filter { element in
            element.label?.lowercased().contains(query) == true ||
            element.description.lowercased().contains(query) ||
            element.traits.contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        HSplitView {
            // Element list with search
            VStack(spacing: 0) {
                SearchBar(query: $searchQuery)
                    .padding(TreeSpacing.unit)

                Divider()

                if filteredElements.isEmpty && !searchQuery.isEmpty {
                    emptySearchView
                } else {
                    List(filteredElements, id: \.traversalIndex, selection: $selectedElement) { element in
                        ElementRowView(element: element)
                    }
                }
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

    private var emptySearchView: some View {
        VStack(spacing: 8) {
            Text("No matches for \"\(searchQuery)\"")
                .font(.Tree.elementLabel)
                .foregroundColor(Color.Tree.textPrimary)
            Text("Try a different search term")
                .font(.Tree.elementTrait)
                .foregroundColor(Color.Tree.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SearchBar: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.Tree.textSecondary)

            TextField("Filter elements...", text: $query)
                .font(.Tree.searchInput)
                .textFieldStyle(.plain)

            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color.Tree.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Text("⌘F")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(Color.Tree.textTertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.Tree.textTertiary.opacity(0.2))
                .cornerRadius(3)
        }
        .padding(.horizontal, TreeSpacing.searchHorizontalPadding)
        .frame(height: TreeSpacing.searchHeight)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }
}

struct ElementRowView: View {
    let element: AccessibilityElementData

    var body: some View {
        HStack(spacing: 4) {
            // Primary trait (monospace, secondary)
            Text(primaryTrait)
                .font(.Tree.elementTrait)
                .foregroundColor(Color.Tree.textSecondary)

            // Label or description (quoted, primary)
            Text("\"\(displayLabel)\"")
                .font(.Tree.elementLabel)
                .foregroundColor(Color.Tree.textPrimary)
                .lineLimit(1)

            Spacer()
        }
        .frame(height: TreeSpacing.rowHeight)
        .padding(.horizontal, TreeSpacing.rowHorizontalPadding)
    }

    private var primaryTrait: String {
        element.traits.first ?? "element"
    }

    private var displayLabel: String {
        element.label ?? element.description
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
                        Text(element.traits.joined(separator: ", "))
                            .font(.Tree.elementTrait)
                            .foregroundColor(Color.Tree.textSecondary)
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
                        Text(element.customActions.joined(separator: ", "))
                            .font(.Tree.elementTrait)
                            .foregroundColor(Color.Tree.textSecondary)
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
                .font(.Tree.detailSectionTitle)
                .foregroundStyle(Color.Tree.textTertiary)
                .textCase(.uppercase)
            content()
        }
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
