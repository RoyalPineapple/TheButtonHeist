import SwiftUI
import ButtonHeist

struct HierarchyListView: View {
    let elements: [UIElement]
    @Binding var selectedElement: UIElement?
    @State private var searchQuery = ""

    private var filteredElements: [UIElement] {
        guard !searchQuery.isEmpty else { return elements }
        let query = searchQuery.lowercased()
        return elements.filter { element in
            element.label?.lowercased().contains(query) == true ||
            element.description.lowercased().contains(query) ||
            element.identifier?.lowercased().contains(query) == true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(query: $searchQuery)
                .padding(TreeSpacing.unit)

            Divider()

            if filteredElements.isEmpty && !searchQuery.isEmpty {
                emptySearchView
            } else {
                List(filteredElements, id: \.order, selection: $selectedElement) { element in
                    ElementRowView(element: element)
                        .tag(element)
                }
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
    let element: UIElement

    var body: some View {
        HStack(spacing: 6) {
            // Colored indicator dot
            Circle()
                .fill(ElementStyling.color(for: element))
                .frame(width: 8, height: 8)

            // Element type icon
            Image(systemName: ElementStyling.iconName(for: element))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ElementStyling.color(for: element))
                .frame(width: 16)

            // Label or description
            Text(displayLabel)
                .font(.Tree.elementLabel)
                .foregroundColor(Color.Tree.textPrimary)
                .lineLimit(1)

            Spacer()
        }
        .frame(height: TreeSpacing.rowHeight)
        .padding(.horizontal, TreeSpacing.rowHorizontalPadding)
    }

    private var displayLabel: String {
        element.label ?? element.description
    }
}

struct ElementDetailView: View {
    let element: UIElement

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

                // Frame
                DetailSection(title: "Frame") {
                    Text("(\(Int(element.frameX)), \(Int(element.frameY))) \(Int(element.frameWidth))×\(Int(element.frameHeight))")
                        .font(.system(.body, design: .monospaced))
                }

                // Identifier
                if let identifier = element.identifier, !identifier.isEmpty {
                    DetailSection(title: "Identifier") {
                        Text(identifier)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                // Actions
                if !element.actions.isEmpty {
                    DetailSection(title: "Actions") {
                        Text(element.actions.joined(separator: ", "))
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
    @Previewable @State var selectedElement: UIElement? = nil
    HierarchyListView(
        elements: [
            UIElement(
                order: 0,
                description: "Hello, World!",
                label: "Hello, World!",
                value: nil,
                identifier: nil,
                frameX: 0,
                frameY: 100,
                frameWidth: 393,
                frameHeight: 44,
                actions: []
            ),
            UIElement(
                order: 1,
                description: "Button",
                label: "Tap me",
                value: nil,
                identifier: "tapButton",
                frameX: 100,
                frameY: 200,
                frameWidth: 100,
                frameHeight: 44,
                actions: ["activate", "Delete", "Edit"]
            )
        ],
        selectedElement: $selectedElement
    )
}
