import SwiftUI

struct NoteItem: Identifiable {
    let id: UUID
    var title: String
    var body: String
    let createdAt: Date
}

struct NotesView: View {
    @State private var notes: [NoteItem] = []
    @State private var newNoteTitle = ""

    var body: some View {
        Form {
            Section("Add Note") {
                HStack {
                    TextField("Note title", text: $newNoteTitle)
                        .onSubmit(addNote)

                    Button("Add") {
                        addNote()
                    }
                    .disabled(newNoteTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section {
                Text("\(notes.count) note\(notes.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }

            Section("Notes") {
                if notes.isEmpty {
                    Text("No notes yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(notes) { note in
                        NavigationLink {
                            NoteDetailView(note: note)
                        } label: {
                            NoteRowView(note: note)
                        }
                        .accessibilityAction(named: "Delete") {
                            deleteNote(note)
                        }
                    }
                    .onDelete { offsets in
                        deleteNotes(at: offsets)
                    }
                }
            }

            if !notes.isEmpty {
                Section {
                    Button("Clear All Notes", role: .destructive) {
                        clearAll()
                    }
                }
            }
        }
        .navigationTitle("Notes")
    }

    private func addNote() {
        let title = newNoteTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let note = NoteItem(id: UUID(), title: title, body: "", createdAt: Date())
        notes.append(note)
        newNoteTitle = ""
        NSLog("[Notes] Added: \"%@\" (total: %d)", title, notes.count)
    }

    private func deleteNote(_ note: NoteItem) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let title = notes[index].title
        notes.remove(at: index)
        NSLog("[Notes] Deleted: \"%@\" (remaining: %d)", title, notes.count)
    }

    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets.sorted().reversed() {
            NSLog("[Notes] Deleted: \"%@\"", notes[index].title)
            notes.remove(at: index)
        }
    }

    private func clearAll() {
        let count = notes.count
        notes.removeAll()
        NSLog("[Notes] Cleared %d notes", count)
    }
}

struct NoteRowView: View {
    let note: NoteItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title)
                .font(.headline)

            if !note.body.isEmpty {
                Text(note.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(note.createdAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

struct NoteDetailView: View {
    @State private var title: String
    @State private var content: String
    private let noteId: UUID
    @Environment(\.dismiss) private var dismiss

    init(note: NoteItem) {
        self.noteId = note.id
        self._title = State(initialValue: note.title)
        self._content = State(initialValue: note.body)
    }

    var body: some View {
        Form {
            Section("Title") {
                TextField("Note title", text: $title)
            }

            Section("Body") {
                TextEditor(text: $content)
                    .frame(minHeight: 200)
            }
        }
        .navigationTitle(title.isEmpty ? "Untitled" : title)
    }
}

#Preview {
    NavigationStack {
        NotesView()
    }
}
