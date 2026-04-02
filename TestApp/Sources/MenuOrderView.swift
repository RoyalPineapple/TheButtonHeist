import SwiftUI

// MARK: - Models

struct MenuItem: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let price: Decimal
    let icon: String
    let customization: String?
    var quantity: Int = 0
    var isCustomized: Bool = false

    init(
        id: String,
        name: String,
        detail: String,
        price: Decimal,
        icon: String,
        customization: String? = nil
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.price = price
        self.icon = icon
        self.customization = customization
    }

    var lineTotal: Decimal { price * Decimal(quantity) }
}

struct MenuCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    var items: [MenuItem]
}

// MARK: - Menu Order View

struct MenuOrderView: View {
    @State private var categories = MenuCategory.defaultMenu

    private var allItems: [MenuItem] {
        categories.flatMap(\.items)
    }

    private var totalQuantity: Int {
        allItems.reduce(0) { $0 + $1.quantity }
    }

    private var subtotal: Decimal {
        allItems.reduce(Decimal.zero) { $0 + $1.lineTotal }
    }

    private var tax: Decimal {
        subtotal * (Decimal(string: "0.08") ?? Decimal.zero)
    }

    private var total: Decimal {
        subtotal + tax
    }

    var body: some View {
        List {
            summarySection
            ForEach($categories) { $category in
                Section {
                    ForEach($category.items) { $item in
                        MenuItemRow(item: $item)
                    }
                } header: {
                    Label(category.name, systemImage: category.icon)
                        .accessibilityIdentifier("buttonheist.menu.section-\(category.id)")
                }
            }
            orderActions
        }
        .navigationTitle("Menu")
    }

    // MARK: - Order Summary

    private var summarySection: some View {
        Section {
            HStack {
                Text("Items")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(totalQuantity)")
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("buttonheist.menu.itemCount")

            HStack {
                Text("Subtotal")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatPrice(subtotal))
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(spokenPrice(subtotal))
            .accessibilityIdentifier("buttonheist.menu.subtotal")

            HStack {
                Text("Tax (8%)")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatPrice(tax))
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(spokenPrice(tax))
            .accessibilityIdentifier("buttonheist.menu.tax")

            HStack {
                Text("Total")
                    .fontWeight(.semibold)
                Spacer()
                Text(formatPrice(total))
                    .fontWeight(.semibold)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(spokenPrice(total))
            .accessibilityIdentifier("buttonheist.menu.total")
        } header: {
            Text("Order Summary")
        }
    }

    // MARK: - Actions

    private var orderActions: some View {
        Section {
            Button {
                NSLog("[Menu] Order placed: %d items, %@", totalQuantity, formatPrice(total))
            } label: {
                HStack {
                    Spacer()
                    Text("Place Order")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .accessibilityIdentifier("buttonheist.menu.placeOrder")
            .disabled(totalQuantity == 0)

            if totalQuantity > 0 {
                Button("Clear Order", role: .destructive) {
                    for categoryIndex in categories.indices {
                        for itemIndex in categories[categoryIndex].items.indices {
                            categories[categoryIndex].items[itemIndex].quantity = 0
                            categories[categoryIndex].items[itemIndex].isCustomized = false
                        }
                    }
                    NSLog("[Menu] Order cleared")
                }
                .accessibilityIdentifier("buttonheist.menu.clearOrder")
            }
        }
    }

    // MARK: - Formatting

    private func formatPrice(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD"))
    }

    private func spokenPrice(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD").presentation(.fullName))
    }
}

// MARK: - Menu Item Row

private struct MenuItemRow: View {
    @Binding var item: MenuItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(item.icon)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.headline)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(item.price.formatted(.currency(code: "USD")))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("buttonheist.menu.item-\(item.id)")

            Stepper(value: $item.quantity, in: 0...10) {
                Text("Qty: \(item.quantity)")
                    .monospacedDigit()
            }
            .accessibilityIdentifier("buttonheist.menu.qty-\(item.id)")
            .accessibilityLabel("\(item.name) quantity")
            .accessibilityValue(String(item.quantity))
            .onChange(of: item.quantity) { _, newValue in
                NSLog("[Menu] %@ quantity: %d", item.name, newValue)
                if newValue == 0 {
                    item.isCustomized = false
                }
            }

            if item.quantity > 0, let customization = item.customization {
                Toggle(customization, isOn: $item.isCustomized)
                    .accessibilityIdentifier("buttonheist.menu.custom-\(item.id)")
                    .onChange(of: item.isCustomized) { _, newValue in
                        NSLog("[Menu] %@ %@: %@", item.name, customization, newValue ? "on" : "off")
                    }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Default Menu Data

extension MenuCategory {
    static let defaultMenu: [MenuCategory] = [
        MenuCategory(
            id: "starters",
            name: "Starters",
            icon: "leaf",
            items: [
                MenuItem(id: "hummus-pita", name: "Hummus & Pita",
                         detail: "Creamy chickpea dip with warm flatbread",
                         price: Decimal(string: "8.50") ?? 0, icon: "\u{1FAD3}"),
                MenuItem(id: "falafel-plate", name: "Falafel Plate",
                         detail: "Crispy chickpea fritters with tahini",
                         price: Decimal(string: "10.00") ?? 0, icon: "\u{1F9C6}",
                         customization: "Extra tahini"),
                MenuItem(id: "greek-salad", name: "Greek Salad",
                         detail: "Tomato, cucumber, olives, and feta",
                         price: Decimal(string: "9.50") ?? 0, icon: "\u{1F957}"),
                MenuItem(id: "bruschetta", name: "Bruschetta",
                         detail: "Toasted bread with tomato and basil",
                         price: Decimal(string: "8.00") ?? 0, icon: "\u{1F35E}"),
                MenuItem(id: "soup-of-the-day", name: "Soup of the Day",
                         detail: "Ask your server for today's selection",
                         price: Decimal(string: "7.00") ?? 0, icon: "\u{1F372}"),
            ]
        ),
        MenuCategory(
            id: "mains",
            name: "Mains",
            icon: "flame",
            items: [
                MenuItem(id: "margherita-pizza", name: "Margherita Pizza",
                         detail: "San Marzano tomato, mozzarella, basil",
                         price: Decimal(string: "14.00") ?? 0, icon: "\u{1F355}",
                         customization: "Add extra basil"),
                MenuItem(id: "grilled-salmon", name: "Grilled Salmon",
                         detail: "Atlantic salmon with lemon herb butter",
                         price: Decimal(string: "22.00") ?? 0, icon: "\u{1F41F}"),
                MenuItem(id: "lamb-kebab", name: "Lamb Kebab",
                         detail: "Seasoned lamb skewers with yogurt sauce",
                         price: Decimal(string: "18.50") ?? 0, icon: "\u{1F362}",
                         customization: "Extra spicy"),
                MenuItem(id: "chicken-shawarma", name: "Chicken Shawarma",
                         detail: "Slow-roasted chicken with pickled turnip",
                         price: Decimal(string: "16.00") ?? 0, icon: "\u{1F32F}",
                         customization: "Extra garlic sauce"),
                MenuItem(id: "eggplant-parmesan", name: "Eggplant Parmesan",
                         detail: "Breaded eggplant with marinara and cheese",
                         price: Decimal(string: "15.00") ?? 0, icon: "\u{1F346}"),
                MenuItem(id: "seafood-pasta", name: "Seafood Pasta",
                         detail: "Linguine with shrimp, mussels, and clam",
                         price: Decimal(string: "20.00") ?? 0, icon: "\u{1F990}"),
            ]
        ),
        MenuCategory(
            id: "sides",
            name: "Sides",
            icon: "square.grid.2x2",
            items: [
                MenuItem(id: "garlic-bread", name: "Garlic Bread",
                         detail: "Oven-baked with herb butter",
                         price: Decimal(string: "5.00") ?? 0, icon: "\u{1F9C4}"),
                MenuItem(id: "sweet-potato-fries", name: "Sweet Potato Fries",
                         detail: "Crispy with chipotle aioli",
                         price: Decimal(string: "6.50") ?? 0, icon: "\u{1F360}"),
                MenuItem(id: "rice-pilaf", name: "Rice Pilaf",
                         detail: "Fluffy basmati with toasted almonds",
                         price: Decimal(string: "4.50") ?? 0, icon: "\u{1F35A}"),
                MenuItem(id: "roasted-vegetables", name: "Roasted Vegetables",
                         detail: "Seasonal medley with olive oil",
                         price: Decimal(string: "7.00") ?? 0, icon: "\u{1F955}"),
            ]
        ),
        MenuCategory(
            id: "desserts",
            name: "Desserts",
            icon: "birthday.cake",
            items: [
                MenuItem(id: "tiramisu", name: "Tiramisu",
                         detail: "Espresso-soaked ladyfingers with mascarpone",
                         price: Decimal(string: "9.00") ?? 0, icon: "\u{1F370}"),
                MenuItem(id: "baklava", name: "Baklava",
                         detail: "Honey-walnut phyllo pastry",
                         price: Decimal(string: "7.50") ?? 0, icon: "\u{1F36F}"),
                MenuItem(id: "chocolate-lava-cake", name: "Chocolate Lava Cake",
                         detail: "Warm dark chocolate with molten center",
                         price: Decimal(string: "10.00") ?? 0, icon: "\u{1F36B}",
                         customization: "Add ice cream"),
                MenuItem(id: "creme-brulee", name: "Crème Brûlée",
                         detail: "Vanilla custard with caramelized sugar",
                         price: Decimal(string: "8.50") ?? 0, icon: "\u{1F36E}"),
                MenuItem(id: "fruit-sorbet", name: "Fruit Sorbet",
                         detail: "Rotating seasonal fruit flavors",
                         price: Decimal(string: "6.00") ?? 0, icon: "\u{1F367}"),
            ]
        ),
        MenuCategory(
            id: "drinks",
            name: "Drinks",
            icon: "cup.and.saucer",
            items: [
                MenuItem(id: "sparkling-water", name: "Sparkling Water",
                         detail: "San Pellegrino 500ml",
                         price: Decimal(string: "3.00") ?? 0, icon: "\u{1F4A7}"),
                MenuItem(id: "fresh-lemonade", name: "Fresh Lemonade",
                         detail: "House-squeezed with honey",
                         price: Decimal(string: "4.50") ?? 0, icon: "\u{1F34B}",
                         customization: "Add mint"),
                MenuItem(id: "espresso", name: "Espresso",
                         detail: "Double shot, single origin",
                         price: Decimal(string: "3.50") ?? 0, icon: "\u{2615}"),
                MenuItem(id: "mint-tea", name: "Mint Tea",
                         detail: "Fresh Moroccan-style mint tea",
                         price: Decimal(string: "4.00") ?? 0, icon: "\u{1F375}"),
                MenuItem(id: "house-red-wine", name: "House Red Wine",
                         detail: "Mediterranean blend, by the glass",
                         price: Decimal(string: "9.00") ?? 0, icon: "\u{1F377}"),
            ]
        ),
    ]
}

#Preview {
    NavigationStack {
        MenuOrderView()
    }
}
