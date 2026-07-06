import SwiftUI
import UIKit

enum AdversarialScenario: String, CaseIterable, Identifiable {
    case asyncReveal = "/async-reveal"
    case offscreenCheckout = "/offscreen-checkout"
    case duplicateLabels = "/duplicate-labels"
    case dynamicCells = "/dynamic-cells"
    case textFieldFallback = "/text-field-fallback"
    case staleLiveObject = "/stale-live-object"
    case modalObstruction = "/modal-obstruction"
    case nestedScroll = "/nested-scroll"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .asyncReveal: "Async Reveal"
        case .offscreenCheckout: "Offscreen Checkout"
        case .duplicateLabels: "Duplicate Labels"
        case .dynamicCells: "Dynamic Cells"
        case .textFieldFallback: "Text Field Fallback"
        case .staleLiveObject: "Stale Live Object"
        case .modalObstruction: "Modal Obstruction"
        case .nestedScroll: "Nested Scroll"
        }
    }
}

struct AdversarialLabView: View {
    var body: some View {
        List(AdversarialScenario.allCases) { scenario in
            NavigationLink(scenario.title) {
                AdversarialScenarioView(scenario: scenario)
            }
        }
        .navigationTitle("Adversarial Lab")
    }
}

private struct AdversarialScenarioView: View {
    let scenario: AdversarialScenario

    var body: some View {
        switch scenario {
        case .asyncReveal:
            AsyncRevealScenarioView()
        case .offscreenCheckout:
            OffscreenCheckoutScenarioView()
        case .duplicateLabels:
            DuplicateLabelsScenarioView()
        case .dynamicCells:
            DynamicCellsScenarioView()
        case .textFieldFallback:
            TextFieldFallbackScenarioView()
        case .staleLiveObject:
            StaleLiveObjectScenarioView()
        case .modalObstruction:
            ModalObstructionScenarioView()
        case .nestedScroll:
            NestedScrollScenarioView()
        }
    }
}

// MARK: - Async Reveal

private struct AsyncRevealScenarioView: View {
    private enum Phase: Equatable {
        case idle
        case pending
        case revealed
    }

    @State private var phase: Phase = .idle
    @State private var revealTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                Button("Reveal with notification") { reveal(postNotification: true) }
                Button("Reveal silently") { reveal(postNotification: false) }
            }

            Section("Destination") {
                switch phase {
                case .idle:
                    Text("Destination hidden")
                case .pending:
                    Text("Waiting for destination")
                case .revealed:
                    Text("Delayed code: 7429")
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .navigationTitle("Async Reveal")
        .onAppear(perform: reset)
        .onDisappear {
            revealTask?.cancel()
            revealTask = nil
        }
    }

    private func reset() {
        revealTask?.cancel()
        revealTask = nil
        phase = .idle
    }

    private func reveal(postNotification: Bool) {
        revealTask?.cancel()
        phase = .pending
        revealTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(700))
            } catch {
                return
            }
            phase = .revealed
            if postNotification {
                UIAccessibility.post(notification: .screenChanged, argument: "Delayed code: 7429")
            }
        }
    }
}

// MARK: - Offscreen Checkout

private struct OffscreenCheckoutScenarioView: View {
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

// MARK: - Duplicate Labels

private struct DuplicateLabelsScenarioView: View {
    private struct Row: Identifiable {
        let id: String
        let title: String
        let category: String
        let priority: String
        let notes: String
    }

    private let rows = [
        Row(id: "work-high", title: "Review PR", category: "Work", priority: "High", notes: "Blocking release"),
        Row(id: "work-low", title: "Review PR", category: "Work", priority: "Low", notes: "Nice to have"),
        Row(id: "home-high", title: "Review PR", category: "Home", priority: "High", notes: "Personal admin"),
    ]

    @State private var completedIDs: Set<String> = []

    var body: some View {
        List {
            Section("Tasks") {
                ForEach(rows) { row in
                    VStack(alignment: .leading) {
                        Text(row.title)
                        Text("\(row.category), \(row.priority)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.title)
                    .accessibilityValue(completedIDs.contains(row.id) ? "Completed" : "Active")
                    .accessibilityAddTraits(completedIDs.contains(row.id) ? [.isSelected] : [])
                    .accessibilityCustomContent(Text("Category"), Text(row.category), importance: .high)
                    .accessibilityCustomContent(Text("Priority"), Text(row.priority), importance: .high)
                    .accessibilityCustomContent(Text("Notes"), Text(row.notes))
                    .accessibilityAction(named: "Toggle") { toggle(row.id) }
                    .accessibilityAction(named: "Delete") { completedIDs.remove(row.id) }
                }
            }
        }
        .navigationTitle("Duplicate Labels")
        .onAppear { completedIDs = [] }
    }

    private func toggle(_ id: String) {
        if completedIDs.contains(id) {
            completedIDs.remove(id)
        } else {
            completedIDs.insert(id)
        }
    }
}

// MARK: - Dynamic Cells

private struct DynamicCellsScenarioView: View {
    private struct MenuItem: Identifiable {
        let id: String
        var name: String
        let category: String
        let detail: String
        let unitPrice: String
    }

    @State private var items = [
        MenuItem(id: "pizza", name: "Margherita Pizza", category: "Mains", detail: "Tomato and mozzarella", unitPrice: "$14.00"),
        MenuItem(id: "salad", name: "Greek Salad", category: "Mains", detail: "Feta and olives", unitPrice: "$9.50"),
        MenuItem(id: "soda", name: "Coke", category: "Drinks", detail: "Bottle", unitPrice: "$3.00"),
    ]
    @State private var quantities: [String: Int] = [:]
    @State private var didReorder = false

    var body: some View {
        List {
            Section {
                Button("Reorder menu") {
                    items.reverse()
                    didReorder.toggle()
                }
                Text(didReorder ? "Menu reordered" : "Menu stable")
            }

            Section("Menu") {
                ForEach(items) { item in
                    menuRow(item)
                }
            }
        }
        .navigationTitle("Dynamic Cells")
        .onAppear {
            items = [
                MenuItem(id: "pizza", name: "Margherita Pizza", category: "Mains", detail: "Tomato and mozzarella", unitPrice: "$14.00"),
                MenuItem(id: "salad", name: "Greek Salad", category: "Mains", detail: "Feta and olives", unitPrice: "$9.50"),
                MenuItem(id: "soda", name: "Coke", category: "Drinks", detail: "Bottle", unitPrice: "$3.00"),
            ]
            quantities = [:]
            didReorder = false
        }
    }

    private func menuRow(_ item: MenuItem) -> some View {
        let quantity = quantities[item.id, default: 0]
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
        .accessibilityCustomContent(Text("Unit Price"), Text(item.unitPrice), importance: .high)
        .accessibilityCustomContent(Text("Quantity"), Text("\(quantity)"), importance: .high)
        .accessibilityCustomContent(Text("Line Total"), Text(lineTotal(unitPrice: item.unitPrice, quantity: quantity)))
        .accessibilityAction(named: quantity == 0 ? "Add to Cart" : "Remove from Cart") {
            quantities[item.id] = quantity == 0 ? 1 : 0
        }
    }

    private func lineTotal(unitPrice: String, quantity: Int) -> String {
        guard quantity > 0 else { return "$0.00" }
        return unitPrice
    }
}

// MARK: - Text Field Fallback

private struct TextFieldFallbackScenarioView: View {
    @State private var draft = ""

    var body: some View {
        Form {
            Section {
                FalseActivateTextField(text: $draft)
                    .frame(height: 44)
                Text(draft.isEmpty ? "Fallback field empty" : "Fallback field value: \(draft)")
            }
        }
        .navigationTitle("Text Field Fallback")
        .onAppear { draft = "" }
    }
}

private struct FalseActivateTextField: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextField {
        let field = RefusingActivationTextField(frame: .zero)
        field.borderStyle = .roundedRect
        field.placeholder = "Fallback field"
        field.accessibilityLabel = "Fallback field"
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.accessibilityValue = text.isEmpty ? nil : text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        @objc func changed(_ sender: UITextField) {
            text = sender.text ?? ""
        }
    }
}

private final class RefusingActivationTextField: UITextField {
    override func accessibilityActivate() -> Bool {
        false
    }
}

// MARK: - Stale Live Object

private struct StaleLiveObjectScenarioView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> StaleLiveObjectViewController {
        StaleLiveObjectViewController()
    }

    func updateUIViewController(_ uiViewController: StaleLiveObjectViewController, context: Context) {}
}

private final class StaleLiveObjectViewController: UIViewController {
    private let stack = UIStackView()
    private let resultLabel = UILabel()
    private var targetButton: UIButton?
    private var generation = 1
    private var showsDuplicate = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stale Live Object"
        view.backgroundColor = .systemGroupedBackground

        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let headingLabel = UILabel()
        headingLabel.text = "Stale Live Object"
        headingLabel.font = .preferredFont(forTextStyle: .title2)
        headingLabel.accessibilityTraits.insert(.header)
        stack.addArrangedSubview(headingLabel)

        let replaceButton = UIButton(type: .system)
        replaceButton.setTitle("Replace Target", for: .normal)
        replaceButton.addTarget(self, action: #selector(replaceTarget), for: .touchUpInside)
        stack.addArrangedSubview(replaceButton)

        let duplicateButton = UIButton(type: .system)
        duplicateButton.setTitle("Show Duplicate Target", for: .normal)
        duplicateButton.addTarget(self, action: #selector(showDuplicateTarget), for: .touchUpInside)
        stack.addArrangedSubview(duplicateButton)

        resultLabel.text = "Result: waiting"
        stack.addArrangedSubview(resultLabel)

        installTargetButton()

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
        ])
    }

    private func installTargetButton() {
        targetButton?.removeFromSuperview()
        let currentGeneration = generation
        let button = UIButton(type: .system)
        button.setTitle("Submit Order", for: .normal)
        button.accessibilityValue = "version \(currentGeneration)"
        button.addAction(UIAction { [weak self] _ in
            self?.resultLabel.text = "Result: submitted version \(currentGeneration)"
        }, for: .touchUpInside)
        targetButton = button
        stack.insertArrangedSubview(button, at: 3)
    }

    @objc private func replaceTarget() {
        generation = 2
        resultLabel.text = "Result: waiting"
        installTargetButton()
    }

    @objc private func showDuplicateTarget() {
        guard !showsDuplicate else { return }
        showsDuplicate = true
        let button = UIButton(type: .system)
        button.setTitle("Submit Order", for: .normal)
        button.accessibilityValue = "version duplicate"
        button.addAction(UIAction { [weak self] _ in
            self?.resultLabel.text = "Result: duplicate submitted"
        }, for: .touchUpInside)
        stack.addArrangedSubview(button)
    }
}

// MARK: - Modal Obstruction

private struct ModalObstructionScenarioView: View {
    @State private var showingReview = false
    @State private var lastAction = "None"

    var body: some View {
        List {
            Section {
                Button("Review order") { showingReview = true }
                Text("Status: \(lastAction)")
            }
            Section("Orders") {
                ForEach(1...100, id: \.self) { order in
                    Button("Archive order \(order)") {
                        lastAction = "Archived order \(order)"
                    }
                }
            }
        }
        .navigationTitle("Modal Obstruction")
        .sheet(isPresented: $showingReview) {
            NavigationStack {
                VStack(spacing: 16) {
                    Text("Order review")
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)
                    Text("Status: \(lastAction)")
                    Button("Confirm review") {
                        lastAction = "Review confirmed"
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Close") {
                        showingReview = false
                    }
                }
                .padding()
            }
        }
        .onAppear {
            showingReview = false
            lastAction = "None"
        }
    }
}

// MARK: - Nested Scroll

private struct NestedScrollScenarioView: View {
    private struct Album: Identifiable {
        let id: String
        let title: String
        let artist: String
    }

    private let sections: [(String, [Album])] = [
        ("Recently Played", (1...8).map { Album(id: "recent-\($0)", title: "Recent Track \($0)", artist: "Daily Mix") }),
        ("Recommended", (1...8).map { Album(id: "recommended-\($0)", title: "Recommended Track \($0)", artist: "Discovery") }),
        ("Deep Cuts", [
            Album(id: "deep-1", title: "Almost There", artist: "The Vibe Check"),
            Album(id: "deep-2", title: "Nearly Verified", artist: "The Vibe Check"),
            Album(id: "deep-3", title: "Verified by The Vibe Check", artist: "The Vibe Check"),
        ] + (4...12).map { Album(id: "deep-\($0)", title: "Deep Cut \($0)", artist: "Archive") }),
    ]

    @State private var selected: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                Text(selected.map { "Selected \($0)" } ?? "No nested selection")
                    .font(.headline)
                    .padding(.horizontal)

                ForEach(sections, id: \.0) { section, albums in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section)
                            .font(.title3.bold())
                            .accessibilityAddTraits(.isHeader)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(albums) { album in
                                    Button {
                                        selected = album.title == "Verified by The Vibe Check" ? "Verified" : album.title
                                    } label: {
                                        VStack(alignment: .leading) {
                                            Text(album.title)
                                                .lineLimit(2)
                                            Text(album.artist)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 180, height: 96, alignment: .leading)
                                        .padding()
                                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(album.title)
                                    .accessibilityValue(album.artist)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Nested Scroll")
        .onAppear { selected = nil }
    }
}
