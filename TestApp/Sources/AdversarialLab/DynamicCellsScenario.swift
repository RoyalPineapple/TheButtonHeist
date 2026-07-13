import SwiftUI

internal struct DynamicCellsScenarioView: View {
    private struct MenuItem: Identifiable {
        let id: String
        let name: String
        let category: String
        let detail: String
        let unitPrice: String
        let sku: String
        let generation: Int
        let slot: String
    }

    @State private var items: [MenuItem] = DynamicCellsScenarioView.makeMenuItems()
    @State private var quantities: [String: Int] = [:]
    @State private var actionCounts: [String: Int] = [:]
    @State private var didChurn = false

    var body: some View {
        List {
            Section {
                Button("Churn menu") { churnMenu() }
                Text(didChurn ? "Menu churned" : "Menu stable")
            }

            Section("Menu") {
                ForEach(items) { item in
                    menuRow(item)
                }
            }
        }
        .navigationTitle("Dynamic Cells")
        .onAppear {
            items = Self.makeMenuItems()
            quantities = [:]
            actionCounts = [:]
            didChurn = false
        }
    }

    private static func makeMenuItems() -> [MenuItem] {
        (1...80).map { index in
            if index == 72 {
                MenuItem(
                    id: "dish-\(index)",
                    name: "Nebula Noodles",
                    category: "Mains",
                    detail: "Black garlic and sesame",
                    unitPrice: "$18.00",
                    sku: "SKU-72",
                    generation: 1,
                    slot: "deep target"
                )
            } else {
                MenuItem(
                    id: "dish-\(index)",
                    name: "Rotating Special \(index % 12)",
                    category: index.isMultiple(of: 5) ? "Drinks" : "Mains",
                    detail: "Batch \(index % 9) fixture",
                    unitPrice: "$\(8 + index % 17).00",
                    sku: "SKU-\(index)",
                    generation: 1,
                    slot: index < 18 ? "front shelf" : index < 60 ? "middle shelf" : "deep shelf"
                )
            }
        }
    }

    private func churnMenu() {
        guard !didChurn else { return }
        var nextItems = items.filter {
            !["dish-4", "dish-11", "dish-23", "dish-38", "dish-67", "dish-79"].contains($0.id)
        }
        let inserts = [
            (
                index: 0,
                item: MenuItem(
                    id: "dish-insert-front",
                    name: "Flash Insert Bao",
                    category: "Specials",
                    detail: "Inserted during churn",
                    unitPrice: "$12.00",
                    sku: "SKU-new-front",
                    generation: 2,
                    slot: "front insert"
                )
            ),
            (
                index: 34,
                item: MenuItem(
                    id: "dish-insert-middle",
                    name: "Rotating Special 3",
                    category: "Specials",
                    detail: "Middle insert reusing a common label",
                    unitPrice: "$13.00",
                    sku: "SKU-new-middle",
                    generation: 2,
                    slot: "middle insert"
                )
            ),
            (
                index: 70,
                item: MenuItem(
                    id: "dish-insert-deep",
                    name: "Rotating Special 8",
                    category: "Mains",
                    detail: "Deep insert reusing a common label",
                    unitPrice: "$16.00",
                    sku: "SKU-new-deep",
                    generation: 2,
                    slot: "deep insert"
                )
            ),
        ]
        inserts.forEach { nextItems.insert($0.item, at: $0.index) }

        let pivot = 24
        items = Array(nextItems.suffix(pivot)) + Array(nextItems.dropLast(pivot))

        guard let targetIndex = items.firstIndex(where: { $0.id == "dish-72" }) else { return }
        items.remove(at: targetIndex)
        items.append(MenuItem(
            id: "dish-72-generation-2",
            name: "Nebula Noodles",
            category: "Mains",
            detail: "Black garlic, sesame, and chili oil",
            unitPrice: "$18.00",
            sku: "SKU-72",
            generation: 2,
            slot: "deep target after churn"
        ))
        let liveIDs = Set(items.map(\.id))
        quantities = quantities.filter { liveIDs.contains($0.key) }
        actionCounts = actionCounts.filter { liveIDs.contains($0.key) }
        didChurn = true
    }

    private func menuRow(_ item: MenuItem) -> some View {
        let quantity = quantities[item.id, default: 0]
        let actionCount = actionCounts[item.id, default: 0]
        return VStack(alignment: .leading) {
            Text(item.name)
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(quantity == 0 ? "Quantity 0" : "Quantity \(quantity)")
        .accessibilityCustomContent(Text("Category"), Text(item.category), importance: .high)
        .accessibilityCustomContent(Text("Detail"), Text(item.detail))
        .accessibilityCustomContent(Text("SKU"), Text(item.sku), importance: .high)
        .accessibilityCustomContent(Text("Generation"), Text("\(item.generation)"), importance: .high)
        .accessibilityCustomContent(Text("Action Count"), Text("\(actionCount)"), importance: .high)
        .accessibilityCustomContent(Text("Menu Slot"), Text(item.slot))
        .accessibilityCustomContent(Text("Unit Price"), Text(item.unitPrice), importance: .high)
        .accessibilityCustomContent(Text("Quantity"), Text("\(quantity)"), importance: .high)
        .accessibilityCustomContent(Text("Line Total"), Text(lineTotal(unitPrice: item.unitPrice, quantity: quantity)))
        .accessibilityAction(named: quantity == 0 ? "Add to Cart" : "Remove from Cart") {
            actionCounts[item.id, default: 0] += 1
            quantities[item.id] = quantity == 0 ? 1 : 0
        }
    }

    private func lineTotal(unitPrice: String, quantity: Int) -> String {
        guard quantity > 0 else { return "$0.00" }
        return unitPrice
    }
}
