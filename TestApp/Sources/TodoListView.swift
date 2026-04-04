import SwiftUI

struct TodoItem: Identifiable {
    let id: UUID
    var title: String
    var isCompleted: Bool
}

struct TodoListView: View {
    @Environment(AppSettings.self) private var settings
    @State private var items: [TodoItem] = []
    @State private var newItemText = ""
    @State private var filter: TodoFilter = .all

    enum TodoFilter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case completed = "Completed"
    }

    private var filteredItems: [TodoItem] {
        var result: [TodoItem]
        switch filter {
        case .all: result = items
        case .active: result = items.filter { !$0.isCompleted }
        case .completed: result = items.filter { $0.isCompleted }
        }
        if !settings.showCompletedTodos {
            result = result.filter { !$0.isCompleted }
        }
        return result
    }

    private var activeCount: Int {
        items.count(where: { !$0.isCompleted })
    }

    private var hasCompleted: Bool {
        items.contains { $0.isCompleted }
    }

    var body: some View {
        Form {
            Section("Add Todo") {
                HStack {
                    TextField("What needs to be done?", text: $newItemText)
                        .onSubmit(addItem)

                    Button("Add") {
                        addItem()
                    }
                    .disabled(newItemText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(TodoFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)

                Text("\(activeCount) item\(activeCount == 1 ? "" : "s") remaining")
                    .foregroundStyle(.secondary)
            }

            Section("Todos") {
                if filteredItems.isEmpty {
                    Text(items.isEmpty ? "No todos yet" : "No \(filter.rawValue.lowercased()) todos")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredItems) { item in
                        TodoRowView(item: item) {
                            toggleItem(item)
                        }
                        .accessibilityAction(named: "Delete") {
                            deleteItem(item)
                        }
                    }
                    .onDelete { offsets in
                        deleteFilteredItems(at: offsets)
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
    }

    private func addItem() {
        let text = newItemText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let item = TodoItem(id: UUID(), title: text, isCompleted: false)
        items.append(item)
        newItemText = ""
        NSLog("[TodoList] Added: \"%@\" (total: %d)", text, items.count)
    }

    private func toggleItem(_ item: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isCompleted.toggle()
        NSLog("[TodoList] Toggled: \"%@\" -> %@", items[index].title, items[index].isCompleted ? "completed" : "active")
    }

    private func deleteItem(_ item: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let title = items[index].title
        items.remove(at: index)
        NSLog("[TodoList] Deleted: \"%@\" (remaining: %d)", title, items.count)
    }

    private func deleteFilteredItems(at offsets: IndexSet) {
        let filtered = filteredItems
        let idsToRemove = offsets.map { filtered[$0].id }
        for id in idsToRemove {
            if let index = items.firstIndex(where: { $0.id == id }) {
                NSLog("[TodoList] Deleted: \"%@\"", items[index].title)
                items.remove(at: index)
            }
        }
    }

    private func clearCompleted() {
        let count = items.count(where: { $0.isCompleted })
        items.removeAll { $0.isCompleted }
        NSLog("[TodoList] Cleared %d completed items (remaining: %d)", count, items.count)
    }
}

struct TodoRowView: View {
    let item: TodoItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? .green : .secondary)

                Text(item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
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
