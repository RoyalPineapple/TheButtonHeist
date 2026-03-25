import SwiftUI

struct LongListView: View {
    @State private var searchText = ""
    @State private var selectedItem: String?
    @State private var orderedItems: [ListItem] = []

    private let items: [ListItem] = (0..<100).map { ListItem(index: $0) }

    private var filteredItems: [ListItem] {
        if searchText.isEmpty { return items }
        let query = searchText.lowercased()
        return items.filter {
            $0.title.lowercased().contains(query) ||
            $0.category.lowercased().contains(query)
        }
    }

    private func isOrdered(_ item: ListItem) -> Bool {
        orderedItems.contains { $0.id == item.id }
    }

    var body: some View {
        List {
            if !orderedItems.isEmpty {
                Section {
                    ForEach(orderedItems) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                Text(item.category)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .accessibilityIdentifier("buttonheist.longList.ordered-\(item.index)")
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                orderedItems.removeAll { $0.id == item.id }
                            } label: {
                                Label("Remove from Order", systemImage: "minus.circle")
                            }
                        }
                        .accessibilityAction(named: "Remove from Order") {
                            orderedItems.removeAll { $0.id == item.id }
                        }
                    }
                } header: {
                    Text("Order (\(orderedItems.count))")
                        .accessibilityIdentifier("buttonheist.longList.orderHeader")
                }
            }

            Section {
                ForEach(filteredItems) { item in
                    Button {
                        selectedItem = item.title
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(item.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier(item.identifier)
                    .swipeActions(edge: .trailing) {
                        if isOrdered(item) {
                            Button(role: .destructive) {
                                orderedItems.removeAll { $0.id == item.id }
                            } label: {
                                Label("Remove from Order", systemImage: "minus.circle")
                            }
                        } else {
                            Button {
                                orderedItems.append(item)
                            } label: {
                                Label("Add to Order", systemImage: "plus.circle")
                            }
                            .tint(.green)
                        }
                    }
                    .accessibilityAction(named: isOrdered(item) ? "Remove from Order" : "Add to Order") {
                        if isOrdered(item) {
                            orderedItems.removeAll { $0.id == item.id }
                        } else {
                            orderedItems.append(item)
                        }
                    }
                }
            } header: {
                if !orderedItems.isEmpty {
                    Text("All Items")
                }
            }
        }
        .accessibilityIdentifier("buttonheist.longList.list")
        .searchable(text: $searchText, prompt: "Search items")
        .navigationTitle("Long List")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("\(filteredItems.count) items")
                    .accessibilityIdentifier("buttonheist.longList.count")
                if !orderedItems.isEmpty {
                    Text("·")
                    Text("\(orderedItems.count) ordered")
                        .accessibilityIdentifier("buttonheist.longList.orderCount")
                }
                if let selectedItem {
                    Spacer()
                    Text("Selected: \(selectedItem)")
                        .accessibilityIdentifier("buttonheist.longList.selected")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }
}

private struct ListItem: Identifiable {
    let index: Int
    let title: String
    let category: String

    var id: Int { index }

    var identifier: String {
        switch index {
        case 0:  "buttonheist.longList.first"
        case 99: "buttonheist.longList.last"
        default: "buttonheist.longList.item-\(index)"
        }
    }

    init(index: Int) {
        self.index = index
        self.title = Self.titles[index % Self.titles.count] + " \(index)"
        self.category = Self.categories[index % Self.categories.count]
    }

    private static let titles = [
        "Widget", "Gadget", "Sprocket", "Gizmo", "Thingamajig",
        "Doohickey", "Contraption", "Apparatus", "Mechanism", "Device",
    ]

    private static let categories = [
        "Hardware", "Software", "Electrical", "Mechanical", "Optical",
    ]
}
