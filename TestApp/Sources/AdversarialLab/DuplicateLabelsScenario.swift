import SwiftUI

internal struct DuplicateLabelsScenarioView: View {
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
    @State private var mutationCount = 0

    var body: some View {
        List {
            Section {
                Text("Task mutation count")
                    .accessibilityValue(String(mutationCount))
            }

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
                }
            }
        }
        .navigationTitle("Duplicate Labels")
        .onAppear {
            completedIDs = []
            mutationCount = 0
        }
    }

    private func toggle(_ id: String) {
        mutationCount += 1
        if completedIDs.contains(id) {
            completedIDs.remove(id)
        } else {
            completedIDs.insert(id)
        }
    }
}
