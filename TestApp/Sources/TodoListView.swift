import SwiftUI

// MARK: - Model

enum TaskCategory: String, CaseIterable, Identifiable {
    case work = "Work"
    case personal = "Personal"
    case errands = "Errands"

    var id: String { rawValue }
}

enum TaskPriority: String, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}

struct TodoItem: Identifiable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var category: TaskCategory
    var priority: TaskPriority
    var notes: String
}

// MARK: - View

struct TodoListView: View {
    @Environment(AppSettings.self) private var settings
    @State private var items: [TodoItem] = Self.sampleItems
    @State private var newItemText = ""
    @State private var newItemCategory: TaskCategory = .work
    @State private var filter: TodoFilter = .all
    @State private var editingItem: TodoItem?
    @State private var showingEditSheet = false

    enum TodoFilter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case completed = "Completed"
    }

    private func itemsForCategory(_ category: TaskCategory) -> [TodoItem] {
        var result: [TodoItem]
        switch filter {
        case .all: result = items.filter { $0.category == category }
        case .active: result = items.filter { $0.category == category && !$0.isCompleted }
        case .completed: result = items.filter { $0.category == category && $0.isCompleted }
        }
        if !settings.showCompletedTodos {
            result = result.filter { !$0.isCompleted }
        }
        return result
    }

    private var activeCount: Int {
        items.filter { !$0.isCompleted }.count
    }

    private var hasCompleted: Bool {
        items.contains { $0.isCompleted }
    }

    var body: some View {
        Form {
            addSection
            filterSection

            ForEach(TaskCategory.allCases) { category in
                let categoryItems = itemsForCategory(category)
                if !categoryItems.isEmpty {
                    Section(category.rawValue) {
                        ForEach(categoryItems) { item in
                            TodoRowView(
                                item: item,
                                onToggle: { toggleItem(item) },
                                onEdit: { beginEditing(item) },
                                onMoveToCategory: { moveItem(item, to: $0) }
                            )
                            .accessibilityAction(named: "Delete") {
                                deleteItem(item)
                            }
                        }
                        .onDelete { offsets in
                            deleteCategoryItems(category: category, at: offsets)
                        }
                    }
                }
            }

            if hasCompleted {
                Section {
                    Button("Clear Completed", role: .destructive) {
                        clearCompleted()
                    }
                }
            }
        }
        .navigationTitle("Todo List")
        .sheet(isPresented: $showingEditSheet) {
            if let editingItem {
                TodoEditSheet(item: editingItem) { updatedItem in
                    applyEdit(updatedItem)
                }
            }
        }
    }

    // MARK: - Add Section

    private var addSection: some View {
        Section("Add Todo") {
            HStack {
                TextField("What needs to be done?", text: $newItemText)
                    .onSubmit(addItem)

                Button("Add") {
                    addItem()
                }
                .disabled(newItemText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Picker("Category", selection: $newItemCategory) {
                ForEach(TaskCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
        }
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        Section {
            Picker("Filter", selection: $filter) {
                ForEach(TodoFilter.allCases, id: \.self) { filterOption in
                    Text(filterOption.rawValue).tag(filterOption)
                }
            }
            .pickerStyle(.segmented)

            Text("\(activeCount) item\(activeCount == 1 ? "" : "s") remaining")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func addItem() {
        let text = newItemText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let item = TodoItem(
            id: UUID(), title: text, isCompleted: false,
            category: newItemCategory, priority: .medium, notes: ""
        )
        items.append(item)
        newItemText = ""
    }

    private func toggleItem(_ item: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isCompleted.toggle()
    }

    private func deleteItem(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
    }

    private func deleteCategoryItems(category: TaskCategory, at offsets: IndexSet) {
        let categoryItems = itemsForCategory(category)
        let idsToRemove = offsets.map { categoryItems[$0].id }
        items.removeAll { idsToRemove.contains($0.id) }
    }

    private func moveItem(_ item: TodoItem, to category: TaskCategory) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].category = category
    }

    private func beginEditing(_ item: TodoItem) {
        editingItem = item
        showingEditSheet = true
    }

    private func applyEdit(_ updatedItem: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == updatedItem.id }) else { return }
        items[index] = updatedItem
        showingEditSheet = false
        editingItem = nil
    }

    private func clearCompleted() {
        items.removeAll { $0.isCompleted }
    }

    // MARK: - Sample Data

    // Pre-populated with natural duplicates: "Review PR" appears in both Work
    // and Personal. "Buy groceries" appears twice in Errands (for two different
    // stores). Same legitimate task names across categories — a VoiceOver user
    // uses section context to distinguish them, the flat matcher cannot.
    static let sampleItems: [TodoItem] = [
        TodoItem(id: UUID(), title: "Review PR", isCompleted: false, category: .work, priority: .high, notes: "Backend API changes"),
        TodoItem(id: UUID(), title: "Fix bug", isCompleted: false, category: .work, priority: .high, notes: "Login crash on iOS 17"),
        TodoItem(id: UUID(), title: "Write tests", isCompleted: true, category: .work, priority: .medium, notes: ""),
        TodoItem(id: UUID(), title: "Fix bug", isCompleted: false, category: .work, priority: .low, notes: "Dark mode color issue"),
        TodoItem(id: UUID(), title: "Review PR", isCompleted: false, category: .personal, priority: .medium, notes: "Friend's open source project"),
        TodoItem(id: UUID(), title: "Buy groceries", isCompleted: false, category: .personal, priority: .high, notes: "Trader Joe's list"),
        TodoItem(id: UUID(), title: "Call dentist", isCompleted: true, category: .personal, priority: .low, notes: ""),
        TodoItem(id: UUID(), title: "Buy groceries", isCompleted: false, category: .errands, priority: .medium, notes: "Costco run"),
        TodoItem(id: UUID(), title: "Pick up dry cleaning", isCompleted: false, category: .errands, priority: .low, notes: ""),
        TodoItem(id: UUID(), title: "Fix bug", isCompleted: true, category: .errands, priority: .medium, notes: "Garage door opener"),
    ]
}

// MARK: - Row View

struct TodoRowView: View {
    let item: TodoItem
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onMoveToCategory: (TaskCategory) -> Void

    var body: some View {
        rowContent
            .accessibilityElement(children: .combine)
            .accessibilityLabel(rowLabel)
            .accessibilityValue(rowValue)
            .accessibilityAddTraits(item.isCompleted ? .isSelected : [])
            .accessibilityAction(named: "Toggle") { onToggle() }
            .accessibilityAction(named: "Edit") { onEdit() }
            .modifier(MoveActionsModifier(currentCategory: item.category, onMove: onMoveToCategory))
    }

    private var rowContent: some View {
        HStack {
            toggleButton
            titleStack
            Spacer()
            editButton
            moveMenu
        }
    }

    private var toggleButton: some View {
        Button(action: onToggle) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.isCompleted ? .green : .secondary)
        }
        .accessibilityLabel(item.isCompleted ? "Mark incomplete" : "Mark complete")
        .accessibilityHint(item.title)
    }

    private var titleStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)

            Text(item.priority.rawValue)
                .font(.caption)
                .foregroundStyle(priorityColor)
        }
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Image(systemName: "pencil")
        }
        .accessibilityLabel("Edit")
        .accessibilityHint(item.title)
    }

    private var moveMenu: some View {
        Menu {
            ForEach(TaskCategory.allCases.filter { $0 != item.category }) { category in
                Button("Move to \(category.rawValue)") {
                    onMoveToCategory(category)
                }
            }
        } label: {
            Image(systemName: "arrow.right.circle")
        }
        .accessibilityLabel("Move")
        .accessibilityHint(item.title)
    }

    private var rowLabel: String {
        "\(item.title), \(item.priority.rawValue) priority"
    }

    private var rowValue: String {
        item.isCompleted ? "Completed" : "Active"
    }

    private var priorityColor: Color {
        switch item.priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .secondary
        }
    }
}

// MARK: - Move Actions Modifier

private struct MoveActionsModifier: ViewModifier {
    let currentCategory: TaskCategory
    let onMove: (TaskCategory) -> Void

    func body(content: Content) -> some View {
        let targets = TaskCategory.allCases.filter { $0 != currentCategory }
        switch targets.count {
        case 0:
            content
        case 1:
            content.accessibilityAction(named: "Move to \(targets[0].rawValue)") { onMove(targets[0]) }
        default:
            content
                .accessibilityAction(named: "Move to \(targets[0].rawValue)") { onMove(targets[0]) }
                .accessibilityAction(named: "Move to \(targets[1].rawValue)") { onMove(targets[1]) }
        }
    }
}

// MARK: - Edit Sheet

struct TodoEditSheet: View {
    @State private var title: String
    @State private var notes: String
    @State private var priority: TaskPriority
    @State private var category: TaskCategory
    @Environment(\.dismiss) private var dismiss
    let item: TodoItem
    let onSave: (TodoItem) -> Void

    init(item: TodoItem, onSave: @escaping (TodoItem) -> Void) {
        self.item = item
        self.onSave = onSave
        _title = State(initialValue: item.title)
        _notes = State(initialValue: item.notes)
        _priority = State(initialValue: item.priority)
        _category = State(initialValue: item.category)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Details") {
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { priorityOption in
                            Text(priorityOption.rawValue).tag(priorityOption)
                        }
                    }

                    Picker("Category", selection: $category) {
                        ForEach(TaskCategory.allCases) { categoryOption in
                            Text(categoryOption.rawValue).tag(categoryOption)
                        }
                    }
                }
            }
            .navigationTitle("Edit Todo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = item
                        updated.title = title
                        updated.notes = notes
                        updated.priority = priority
                        updated.category = category
                        onSave(updated)
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        TodoListView()
    }
    .environment(AppSettings())
}
