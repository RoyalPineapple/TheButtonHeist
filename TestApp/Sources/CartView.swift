import SwiftUI

struct CartView: View {
    @State private var items: [CartItem] = CartItem.defaultCart
    @State private var addedExtras: Set<String> = []

    private var subtotal: Decimal {
        items.reduce(0) { $0 + $1.lineTotal }
    }

    private var tax: Decimal {
        subtotal * (Decimal(85) / Decimal(1000))
    }

    private var total: Decimal {
        subtotal + tax
    }

    private var canAddItem: Bool {
        addedExtras.count < CartItem.extras.count
    }

    var body: some View {
        List {
            if !items.isEmpty {
                summarySection
                itemsSection
                actionsSection
            } else {
                emptySection
            }
        }
        .navigationTitle("Cart")
        .animation(.default, value: items.count)
    }

    private var summarySection: some View {
        Section {
            HStack {
                Text("Items")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(items.reduce(0) { $0 + $1.quantity })")
            }

            HStack {
                Text("Subtotal")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatPrice(subtotal))
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(spokenPrice(subtotal))

            HStack {
                Text("Tax (8.5%)")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatPrice(tax))
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(spokenPrice(tax))

            HStack {
                Text("Total")
                    .fontWeight(.semibold)
                Spacer()
                Text(formatPrice(total))
                    .fontWeight(.semibold)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(spokenPrice(total))
        }
    }

    private var itemsSection: some View {
        Section("Order") {
            ForEach($items) { $item in
                CartItemRow(item: item) { newQuantity in
                    updateQuantity(itemID: item.id, quantity: newQuantity)
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                addRandomItem()
            } label: {
                Label("Add Item", systemImage: "plus.circle.fill")
            }
            .disabled(!canAddItem)

            Button(role: .destructive) {
                clearCart()
            } label: {
                Label("Clear Cart", systemImage: "trash")
            }
        }
    }

    private var emptySection: some View {
        Section {
            ContentUnavailableView {
                Label("Your Cart is Empty", systemImage: "cart")
            } description: {
                Text("Add something tasty.")
            } actions: {
                Button("Add Something") {
                    addRandomItem()
                }
            }
        }
    }

    private func updateQuantity(itemID: UUID, quantity: Int) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }

        if quantity <= 0 {
            items.remove(at: idx)
        } else {
            items[idx].quantity = quantity
        }
    }

    private func addRandomItem() {
        let available = CartItem.extras.filter { extra in
            !addedExtras.contains(extra.name) && !items.contains { $0.name == extra.name }
        }
        guard let pick = available.randomElement() else { return }
        let item = CartItem(
            name: pick.name,
            price: pick.price,
            icon: pick.icon,
            color: pick.color,
            quantity: 1
        )
        items.append(item)
        addedExtras.insert(pick.name)
    }

    private func clearCart() {
        items.removeAll()
    }

    private func formatPrice(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD"))
    }

    private func spokenPrice(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD").presentation(.fullName))
    }
}

// MARK: - Cart Item Row

private struct CartItemRow: View {
    let item: CartItem
    let onQuantityChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(item.color.gradient)
                    .frame(width: 44, height: 44)
                Image(systemName: item.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                Text(item.unitPriceFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(item.lineTotalFormatted)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Stepper(
                value: Binding(
                    get: { item.quantity },
                    set: { onQuantityChange($0) }
                ),
                in: 0...10
            ) {
                Text("\(item.quantity)")
                    .monospacedDigit()
                    .frame(minWidth: 20, alignment: .center)
            }
            .accessibilityValue("\(item.quantity)")
        }
    }
}

// MARK: - Model

private struct CartItem: Identifiable, Equatable {
    let id: UUID
    let name: String
    let price: Decimal
    let icon: String
    let color: Color
    var quantity: Int

    init(name: String, price: Decimal, icon: String, color: Color, quantity: Int) {
        self.id = UUID()
        self.name = name
        self.price = price
        self.icon = icon
        self.color = color
        self.quantity = quantity
    }

    var lineTotal: Decimal { price * Decimal(quantity) }

    var unitPriceFormatted: String {
        price.formatted(.currency(code: "USD"))
    }

    var lineTotalFormatted: String {
        lineTotal.formatted(.currency(code: "USD"))
    }

    static let defaultCart: [CartItem] = [
        CartItem(name: "Espresso", price: Decimal(450) / Decimal(100), icon: "cup.and.saucer.fill", color: .brown, quantity: 1),
        CartItem(name: "Croissant", price: Decimal(375) / Decimal(100), icon: "birthday.cake.fill", color: .orange, quantity: 2),
        CartItem(name: "Orange Juice", price: Decimal(500) / Decimal(100), icon: "mug.fill", color: .orange, quantity: 1),
        CartItem(name: "Avocado Toast", price: Decimal(1200) / Decimal(100), icon: "leaf.fill", color: .green, quantity: 1),
        CartItem(name: "Blueberry Muffin", price: Decimal(425) / Decimal(100), icon: "circle.grid.cross.fill", color: .purple, quantity: 1),
    ]

    static let extras: [(name: String, price: Decimal, icon: String, color: Color)] = [
        (name: "Matcha Latte", price: Decimal(550) / Decimal(100), icon: "leaf.circle.fill", color: .green),
        (name: "Banana Bread", price: Decimal(400) / Decimal(100), icon: "rectangle.split.1x2.fill", color: .yellow),
        (name: "Cold Brew", price: Decimal(525) / Decimal(100), icon: "snowflake", color: .cyan),
        (name: "Açaí Bowl", price: Decimal(950) / Decimal(100), icon: "circle.hexagongrid.fill", color: .indigo),
    ]

    static func == (lhs: CartItem, rhs: CartItem) -> Bool {
        lhs.id == rhs.id && lhs.quantity == rhs.quantity
    }
}

#Preview {
    NavigationStack {
        CartView()
    }
    .environment(AppSettings())
}
