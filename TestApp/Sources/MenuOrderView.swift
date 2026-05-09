import SwiftUI

// MARK: - Models

enum PortionSize: String, CaseIterable, Identifiable {
    case small = "Small"
    case regular = "Regular"
    case large = "Large"

    var id: String { rawValue }

    var priceMultiplier: Decimal {
        switch self {
        case .small: Decimal(75) / Decimal(100)
        case .regular: 1
        case .large: Decimal(135) / Decimal(100)
        }
    }

    var label: String { rawValue }
}

struct MenuItem: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let price: Decimal
    let emoji: String
    let color: Color
    let options: [ItemOption]
    var quantity: Int = 0
    var selectedSize: PortionSize = .regular
    var activeOptions: Set<String> = []

    init(
        id: String,
        name: String,
        detail: String,
        price: Decimal,
        emoji: String,
        color: Color = .secondary,
        options: [ItemOption] = []
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.price = price
        self.emoji = emoji
        self.color = color
        self.options = options
    }

    var effectivePrice: Decimal {
        let base = price * selectedSize.priceMultiplier
        let optionsCost = options
            .filter { activeOptions.contains($0.id) }
            .reduce(Decimal.zero) { $0 + $1.extraPrice }
        return base + optionsCost
    }

    var lineTotal: Decimal { effectivePrice * Decimal(quantity) }
}

struct ItemOption: Identifiable, Equatable {
    let id: String
    let label: String
    let extraPrice: Decimal
}

struct MenuCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    var items: [MenuItem]
}

// MARK: - Menu Order View

struct MenuOrderView: View {
    enum CheckoutPhase {
        case browsing
        case reviewing
        case processing
        case confirmed(orderNumber: String)
    }

    @State private var categories = MenuCategory.defaultMenu
    @State private var expandedItemId: String?
    @State private var checkoutPhase: CheckoutPhase = .browsing

    private var allItems: [MenuItem] {
        categories.flatMap(\.items)
    }

    private var orderedItems: [MenuItem] {
        allItems.filter { $0.quantity > 0 }
    }

    private var totalQuantity: Int {
        allItems.reduce(0) { $0 + $1.quantity }
    }

    private var subtotal: Decimal {
        allItems.reduce(Decimal.zero) { $0 + $1.lineTotal }
    }

    private var tax: Decimal {
        subtotal * (Decimal(8) / Decimal(100))
    }

    private var total: Decimal {
        subtotal + tax
    }

    var body: some View {
        Group {
            switch checkoutPhase {
            case .browsing:
                menuList
            case .reviewing:
                checkoutReview
            case .processing:
                processingView
            case .confirmed(let orderNumber):
                confirmationView(orderNumber: orderNumber)
            }
        }
        .navigationTitle(checkoutTitle)
    }

    private var checkoutTitle: String {
        switch checkoutPhase {
        case .browsing: "Menu"
        case .reviewing: "Checkout"
        case .processing: "Processing"
        case .confirmed: "Order Confirmed"
        }
    }

    // MARK: - Menu List (browsing phase)

    private var menuList: some View {
        List {
            summarySection

            ForEach($categories) { $category in
                Section {
                    ForEach($category.items) { $item in
                        MenuItemRow(
                            item: $item,
                            isExpanded: expandedItemId == item.id,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    if expandedItemId == item.id {
                                        expandedItemId = nil
                                    } else {
                                        expandedItemId = item.id
                                    }
                                }
                            }
                        )
                    }
                } header: {
                    Label(category.name, systemImage: category.icon)
                }
            }

            orderActions
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Checkout Review

    private var checkoutReview: some View {
        List {
            Section("Your Order") {
                ForEach(orderedItems) { item in
                    HStack {
                        Text("\(item.emoji) \(item.name)")
                        if item.selectedSize != .regular {
                            Text("(\(item.selectedSize.label))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\u{00D7}\(item.quantity)")
                            .foregroundStyle(.secondary)
                        Text(item.lineTotal.usdFormatted)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section {
                HStack {
                    Text("Subtotal")
                    Spacer()
                    Text(subtotal.usdFormatted)
                }
                HStack {
                    Text("Tax (8%)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(tax.usdFormatted)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Total")
                        .fontWeight(.bold)
                    Spacer()
                    Text(total.usdFormatted)
                        .fontWeight(.bold)
                        .font(.title3)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(total.usdSpoken)
            }

            Section {
                Button {
                    checkoutPhase = .processing
                    Task {
                        let roll = Int.random(in: 1...100)
                        let delay: Double = switch roll {
                        case 1...80:  2.5
                        case 81...90: 5.0
                        case 91...95: 7.0
                        default:      10.0
                        }
                        do {
                            try await Task.sleep(for: .seconds(delay))
                        } catch {
                            return
                        }
                        let orderNumber = "ORD-\(Int.random(in: 1000...9999))"
                        checkoutPhase = .confirmed(orderNumber: orderNumber)
                    }
                } label: {
                    HStack {
                        Spacer()
                        Label("Confirm Payment — \(total.usdFormatted)", systemImage: "creditcard")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }

                Button("Back to Menu") {
                    checkoutPhase = .browsing
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
                .accessibilityLabel("Processing payment")
            Text("Processing payment…")
                .font(.headline)
            Text(total.usdFormatted)
                .font(.title2)
                .fontWeight(.bold)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Confirmation

    private func confirmationView(orderNumber: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Payment Successful")
                .font(.title2)
                .fontWeight(.bold)
            Text("Order \(orderNumber)")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(total.usdFormatted)
                .font(.title3)
            Text("\(totalQuantity) item\(totalQuantity == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            Spacer()
            Button("New Order") {
                resetOrder()
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Order Summary

    private var summarySection: some View {
        Section {
            HStack {
                Text("Items")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(totalQuantity)")
                    .fontWeight(.medium)
            }
            .accessibilityElement(children: .combine)

            HStack {
                Text("Subtotal")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(subtotal.usdFormatted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(subtotal.usdSpoken)

            HStack {
                Text("Tax (8%)")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(tax.usdFormatted)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(tax.usdSpoken)

            HStack {
                Text("Total")
                    .fontWeight(.semibold)
                Spacer()
                Text(total.usdFormatted)
                    .fontWeight(.semibold)
                    .font(.title3)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(total.usdSpoken)
        } header: {
            Text("Order Summary")
        }
    }

    // MARK: - Actions

    private var orderActions: some View {
        Section {
            Button {
                checkoutPhase = .reviewing
            } label: {
                HStack {
                    Spacer()
                    Label("Place Order", systemImage: "cart.fill")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(totalQuantity == 0)

            if totalQuantity > 0 {
                Button("Clear Order", role: .destructive) {
                    resetOrder()
                }
            }
        }
    }

    private func resetOrder() {
        for categoryIndex in categories.indices {
            for itemIndex in categories[categoryIndex].items.indices {
                categories[categoryIndex].items[itemIndex].quantity = 0
                categories[categoryIndex].items[itemIndex].activeOptions = []
                categories[categoryIndex].items[itemIndex].selectedSize = .regular
            }
        }
        expandedItemId = nil
        checkoutPhase = .browsing
    }

}

// MARK: - Menu Item Row

private struct MenuItemRow: View {
    @Binding var item: MenuItem
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible, tappable
            Button(action: onTap) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(item.color.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Text(item.emoji)
                            .font(.title2)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(item.name)
                                .font(.body.weight(.medium))
                            if item.quantity > 0 {
                                Text("\u{00D7}\(item.quantity)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(item.color.opacity(0.8), in: Capsule())
                            }
                            Spacer()
                            Text(item.effectivePrice.formatted(.currency(code: "USD")))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(isExpanded ? 3 : 1)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(isExpanded ? "Double tap to collapse" : "Double tap to configure")
            .accessibilityAddTraits(isExpanded ? .isSelected : [])

            // Expanded configuration section
            if isExpanded {
                configurationSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.25), value: isExpanded)
        .animation(.easeInOut(duration: 0.2), value: item.quantity)
    }

    // MARK: - Configuration Section

    @ViewBuilder
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.top, 8)

            // Size picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Size")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Size", selection: $item.selectedSize) {
                    ForEach(PortionSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Options (toggles)
            if !item.options.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Options")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(item.options) { option in
                        Toggle(isOn: Binding(
                            get: { item.activeOptions.contains(option.id) },
                            set: { enabled in
                                if enabled {
                                    item.activeOptions.insert(option.id)
                                } else {
                                    item.activeOptions.remove(option.id)
                                }
                            }
                        )) {
                            HStack {
                                Text(option.label)
                                    .font(.subheadline)
                                if option.extraPrice > 0 {
                                    Text("+\(option.extraPrice.formatted(.currency(code: "USD")))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(option.label)
                    }
                }
            }

            // Add to Cart / Quantity Stepper
            if item.quantity == 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        item.quantity = 1
                    }
                } label: {
                    HStack {
                        Spacer()
                        Label("Add to Cart", systemImage: "cart.badge.plus")
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(item.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .transition(.opacity.combined(with: .scale))
            } else {
                VStack(spacing: 8) {
                    Stepper(value: $item.quantity, in: 0...10) {
                        HStack {
                            Text("Qty")
                                .foregroundStyle(.secondary)
                            Text("\(item.quantity)")
                                .fontWeight(.medium)
                                .monospacedDigit()
                            Text("\u{00B7}")
                                .foregroundStyle(.tertiary)
                            Text(item.lineTotal.formatted(.currency(code: "USD")))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("\(item.name) quantity")
                    .accessibilityValue(String(item.quantity))

                    if item.quantity > 0 {
                        Button(role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                item.quantity = 0
                                item.activeOptions = []
                                item.selectedSize = .regular
                            }
                        } label: {
                            Text("Remove")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.top, 4)
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
                         price: Decimal(850) / Decimal(100), emoji: "\u{1FAD3}", color: .orange,
                         options: [
                            ItemOption(id: "extra-pita", label: "Extra pita", extraPrice: Decimal(150) / Decimal(100)),
                            ItemOption(id: "spicy-hummus", label: "Spicy hummus", extraPrice: 0),
                         ]),
                MenuItem(id: "falafel-plate", name: "Falafel Plate",
                         detail: "Crispy chickpea fritters with tahini",
                         price: Decimal(1000) / Decimal(100), emoji: "\u{1F9C6}", color: .brown,
                         options: [
                            ItemOption(id: "extra-tahini", label: "Extra tahini", extraPrice: Decimal(75) / Decimal(100)),
                            ItemOption(id: "pickled-turnip", label: "Pickled turnip", extraPrice: Decimal(100) / Decimal(100)),
                         ]),
                MenuItem(id: "greek-salad", name: "Greek Salad",
                         detail: "Tomato, cucumber, olives, and feta",
                         price: Decimal(950) / Decimal(100), emoji: "\u{1F957}", color: .green,
                         options: [
                            ItemOption(id: "extra-feta", label: "Extra feta", extraPrice: Decimal(150) / Decimal(100)),
                            ItemOption(id: "no-onion", label: "No onion", extraPrice: 0),
                         ]),
                MenuItem(id: "bruschetta", name: "Bruschetta",
                         detail: "Toasted bread with tomato and basil",
                         price: Decimal(800) / Decimal(100), emoji: "\u{1F35E}", color: .red),
                MenuItem(id: "soup-of-the-day", name: "Soup of the Day",
                         detail: "Ask your server for today's selection",
                         price: Decimal(700) / Decimal(100), emoji: "\u{1F372}", color: .orange,
                         options: [
                            ItemOption(id: "bread-side", label: "Side of bread", extraPrice: Decimal(200) / Decimal(100)),
                         ]),
            ]
        ),
        MenuCategory(
            id: "mains",
            name: "Mains",
            icon: "flame",
            items: [
                MenuItem(id: "margherita-pizza", name: "Margherita Pizza",
                         detail: "San Marzano tomato, mozzarella, basil",
                         price: Decimal(1400) / Decimal(100), emoji: "\u{1F355}", color: .red,
                         options: [
                            ItemOption(id: "extra-basil", label: "Extra basil", extraPrice: 0),
                            ItemOption(id: "truffle-oil", label: "Truffle oil drizzle", extraPrice: Decimal(300) / Decimal(100)),
                            ItemOption(id: "gluten-free-crust", label: "Gluten-free crust", extraPrice: Decimal(250) / Decimal(100)),
                         ]),
                MenuItem(id: "grilled-salmon", name: "Grilled Salmon",
                         detail: "Atlantic salmon with lemon herb butter",
                         price: Decimal(2200) / Decimal(100), emoji: "\u{1F41F}", color: .pink,
                         options: [
                            ItemOption(id: "extra-lemon", label: "Extra lemon butter", extraPrice: Decimal(100) / Decimal(100)),
                            ItemOption(id: "asparagus-side", label: "Grilled asparagus", extraPrice: Decimal(350) / Decimal(100)),
                         ]),
                MenuItem(id: "lamb-kebab", name: "Lamb Kebab",
                         detail: "Seasoned lamb skewers with yogurt sauce",
                         price: Decimal(1850) / Decimal(100), emoji: "\u{1F362}", color: .brown,
                         options: [
                            ItemOption(id: "extra-spicy", label: "Extra spicy", extraPrice: 0),
                            ItemOption(id: "extra-yogurt", label: "Extra yogurt sauce", extraPrice: Decimal(75) / Decimal(100)),
                            ItemOption(id: "rice-upgrade", label: "Upgrade to saffron rice", extraPrice: Decimal(200) / Decimal(100)),
                         ]),
                MenuItem(id: "chicken-shawarma", name: "Chicken Shawarma",
                         detail: "Slow-roasted chicken with pickled turnip",
                         price: Decimal(1600) / Decimal(100), emoji: "\u{1F32F}", color: .yellow,
                         options: [
                            ItemOption(id: "extra-garlic", label: "Extra garlic sauce", extraPrice: 0),
                            ItemOption(id: "wrap-style", label: "Wrap instead of plate", extraPrice: 0),
                         ]),
                MenuItem(id: "eggplant-parmesan", name: "Eggplant Parmesan",
                         detail: "Breaded eggplant with marinara and cheese",
                         price: Decimal(1500) / Decimal(100), emoji: "\u{1F346}", color: .purple,
                         options: [
                            ItemOption(id: "extra-cheese", label: "Extra mozzarella", extraPrice: Decimal(150) / Decimal(100)),
                            ItemOption(id: "side-pasta", label: "Side of spaghetti", extraPrice: Decimal(300) / Decimal(100)),
                         ]),
                MenuItem(id: "seafood-pasta", name: "Seafood Pasta",
                         detail: "Linguine with shrimp, mussels, and clam",
                         price: Decimal(2000) / Decimal(100), emoji: "\u{1F990}", color: .orange,
                         options: [
                            ItemOption(id: "white-wine", label: "White wine sauce", extraPrice: 0),
                            ItemOption(id: "extra-shrimp", label: "Extra shrimp", extraPrice: Decimal(400) / Decimal(100)),
                         ]),
            ]
        ),
        MenuCategory(
            id: "sides",
            name: "Sides",
            icon: "square.grid.2x2",
            items: [
                MenuItem(id: "garlic-bread", name: "Garlic Bread",
                         detail: "Oven-baked with herb butter",
                         price: Decimal(500) / Decimal(100), emoji: "\u{1F9C4}", color: .yellow,
                         options: [
                            ItemOption(id: "cheese-top", label: "Cheese topping", extraPrice: Decimal(150) / Decimal(100)),
                         ]),
                MenuItem(id: "sweet-potato-fries", name: "Sweet Potato Fries",
                         detail: "Crispy with chipotle aioli",
                         price: Decimal(650) / Decimal(100), emoji: "\u{1F360}", color: .orange,
                         options: [
                            ItemOption(id: "truffle-salt", label: "Truffle salt", extraPrice: Decimal(100) / Decimal(100)),
                         ]),
                MenuItem(id: "rice-pilaf", name: "Rice Pilaf",
                         detail: "Fluffy basmati with toasted almonds",
                         price: Decimal(450) / Decimal(100), emoji: "\u{1F35A}", color: .brown),
                MenuItem(id: "roasted-vegetables", name: "Roasted Vegetables",
                         detail: "Seasonal medley with olive oil",
                         price: Decimal(700) / Decimal(100), emoji: "\u{1F955}", color: .green,
                         options: [
                            ItemOption(id: "balsamic-glaze", label: "Balsamic glaze", extraPrice: Decimal(75) / Decimal(100)),
                         ]),
            ]
        ),
        MenuCategory(
            id: "desserts",
            name: "Desserts",
            icon: "birthday.cake",
            items: [
                MenuItem(id: "tiramisu", name: "Tiramisu",
                         detail: "Espresso-soaked ladyfingers with mascarpone",
                         price: Decimal(900) / Decimal(100), emoji: "\u{1F370}", color: .brown),
                MenuItem(id: "baklava", name: "Baklava",
                         detail: "Honey-walnut phyllo pastry",
                         price: Decimal(750) / Decimal(100), emoji: "\u{1F36F}", color: .yellow,
                         options: [
                            ItemOption(id: "pistachio", label: "Pistachio topping", extraPrice: Decimal(100) / Decimal(100)),
                         ]),
                MenuItem(id: "chocolate-lava-cake", name: "Chocolate Lava Cake",
                         detail: "Warm dark chocolate with molten center",
                         price: Decimal(1000) / Decimal(100), emoji: "\u{1F36B}", color: .brown,
                         options: [
                            ItemOption(id: "ice-cream", label: "Add ice cream", extraPrice: Decimal(250) / Decimal(100)),
                            ItemOption(id: "raspberry-coulis", label: "Raspberry coulis", extraPrice: Decimal(100) / Decimal(100)),
                         ]),
                MenuItem(id: "creme-brulee", name: "Crème Brûlée",
                         detail: "Vanilla custard with caramelized sugar",
                         price: Decimal(850) / Decimal(100), emoji: "\u{1F36E}", color: .yellow),
                MenuItem(id: "fruit-sorbet", name: "Fruit Sorbet",
                         detail: "Rotating seasonal fruit flavors",
                         price: Decimal(600) / Decimal(100), emoji: "\u{1F367}", color: .pink,
                         options: [
                            ItemOption(id: "double-scoop", label: "Double scoop", extraPrice: Decimal(200) / Decimal(100)),
                         ]),
            ]
        ),
        MenuCategory(
            id: "drinks",
            name: "Drinks",
            icon: "cup.and.saucer",
            items: [
                MenuItem(id: "sparkling-water", name: "Sparkling Water",
                         detail: "San Pellegrino 500ml",
                         price: Decimal(300) / Decimal(100), emoji: "\u{1F4A7}", color: .cyan),
                MenuItem(id: "fresh-lemonade", name: "Fresh Lemonade",
                         detail: "House-squeezed with honey",
                         price: Decimal(450) / Decimal(100), emoji: "\u{1F34B}", color: .yellow,
                         options: [
                            ItemOption(id: "add-mint", label: "Add mint", extraPrice: 0),
                            ItemOption(id: "less-sugar", label: "Less sugar", extraPrice: 0),
                         ]),
                MenuItem(id: "espresso", name: "Espresso",
                         detail: "Double shot, single origin",
                         price: Decimal(350) / Decimal(100), emoji: "\u{2615}", color: .brown,
                         options: [
                            ItemOption(id: "oat-milk", label: "Oat milk", extraPrice: Decimal(75) / Decimal(100)),
                            ItemOption(id: "extra-shot", label: "Extra shot", extraPrice: Decimal(100) / Decimal(100)),
                         ]),
                MenuItem(id: "mint-tea", name: "Mint Tea",
                         detail: "Fresh Moroccan-style mint tea",
                         price: Decimal(400) / Decimal(100), emoji: "\u{1F375}", color: .green),
                MenuItem(id: "house-red-wine", name: "House Red Wine",
                         detail: "Mediterranean blend, by the glass",
                         price: Decimal(900) / Decimal(100), emoji: "\u{1F377}", color: .red),
            ]
        ),
    ]
}

#Preview {
    NavigationStack {
        MenuOrderView()
    }
}
