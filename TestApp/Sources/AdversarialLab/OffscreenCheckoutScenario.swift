import SwiftUI

internal struct OffscreenCheckoutScenarioView: View {
    private struct Item: Identifiable {
        let id: String
        let name: String
    }

    private let items = [
        Item(id: "espresso", name: "Espresso"),
        Item(id: "tea", name: "Tea"),
        Item(id: "bagel", name: "Bagel"),
    ]
    private let filler = (1...36).map { "Checkout detail \($0)" }

    @State private var selectedItemIDs: Set<String> = []
    @State private var didCheckout = false

    private var canCheckout: Bool { !selectedItemIDs.isEmpty }

    var body: some View {
        List {
            Section {
                Text(didCheckout ? "Order placed" : "Cart ready")
            }

            Section("Menu") {
                ForEach(items) { item in
                    Button(selectedItemIDs.contains(item.id) ? "Remove \(item.name)" : "Add \(item.name)") {
                        if selectedItemIDs.contains(item.id) {
                            selectedItemIDs.remove(item.id)
                        } else {
                            selectedItemIDs.insert(item.id)
                        }
                    }
                }
            }

            Section("Details") {
                ForEach(filler, id: \.self) { detail in
                    Text(detail)
                }
            }

            Section("Checkout") {
                Button("Place order") {
                    didCheckout = true
                }
                .disabled(!canCheckout)
            }
        }
        .navigationTitle("Offscreen Checkout")
        .onAppear {
            selectedItemIDs = []
            didCheckout = false
        }
    }
}
