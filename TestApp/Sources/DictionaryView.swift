import SwiftUI

// MARK: - Model

struct DictionaryEntry: Identifiable, Hashable {
    let id: Int
    let term: String

    var sectionTitle: String {
        guard let first = term.first else { return "#" }
        let title = String(first).uppercased()
        return title.range(of: "[A-Z]", options: .regularExpression) == nil ? "#" : title
    }

    var detailSummary: String {
        let wordCount = term.split(separator: " ").count
        let format = wordCount == 1 ? "single word" : "\(wordCount)-word phrase"
        return "\(format), \(term.count) character\(term.count == 1 ? "" : "s")"
    }
}

struct DictionarySection: Identifiable {
    let title: String
    let entries: [DictionaryEntry]

    var id: String { title }
}

// MARK: - Data

enum DictionaryData {
    static let entries: [DictionaryEntry] = loadEntries()
    static let sections: [DictionarySection] = makeSections(from: entries)

    static func sections(matching searchText: String) -> [DictionarySection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sections }

        return makeSections(from: entries.filter { entry in
            entry.term.localizedCaseInsensitiveContains(query)
        })
    }

    static func neighbors(for entry: DictionaryEntry) -> [DictionaryEntry] {
        let lowerBound = max(entries.startIndex, entry.id - 2)
        let upperBound = min(entries.endIndex, entry.id + 3)
        return entries[lowerBound..<upperBound].filter { $0.id != entry.id }
    }

    private static func loadEntries() -> [DictionaryEntry] {
        guard
            let url = Bundle.main.url(forResource: "web2a", withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return fallbackTerms.enumerated().map { DictionaryEntry(id: $0.offset, term: $0.element) }
        }

        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { DictionaryEntry(id: $0.offset, term: $0.element) }
    }

    private static func makeSections(from entries: [DictionaryEntry]) -> [DictionarySection] {
        Dictionary(grouping: entries, by: \.sectionTitle)
            .map { DictionarySection(title: $0.key, entries: $0.value) }
            .sorted { lhs, rhs in
                if lhs.title == "#" { return false }
                if rhs.title == "#" { return true }
                return lhs.title < rhs.title
            }
    }

    private static let fallbackTerms = [
        "abacus",
        "able",
        "button",
        "calculator",
        "dictionary",
        "entry",
        "phrase book",
        "scroll",
        "search",
        "zither",
    ]
}

// MARK: - View

struct DictionaryView: View {
    @State private var searchText = ""

    private var visibleSections: [DictionarySection] {
        DictionaryData.sections(matching: searchText)
    }

    private var visibleEntryCount: Int {
        visibleSections.reduce(0) { $0 + $1.entries.count }
    }

    private var isSearchMode: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            if isSearchMode {
                Section {
                    if visibleSections.isEmpty {
                        Text("No substring matches")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visibleSections) { section in
                            DictionarySectionHeaderView(title: section.title, wordCount: section.entries.count)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            dictionaryRows(for: section)
                        }
                    }
                } header: {
                    DictionaryResultsHeaderView(summary: resultSummary)
                }
            } else {
                ForEach(visibleSections) { section in
                    Section {
                        dictionaryRows(for: section)
                    } header: {
                        DictionarySectionHeaderView(title: section.title, wordCount: section.entries.count)
                    }
                }
            }
        }
        .navigationTitle("Words")
        .searchable(text: $searchText, prompt: "Search words")
    }

    @ViewBuilder
    private func dictionaryRows(for section: DictionarySection) -> some View {
        ForEach(section.entries) { entry in
            NavigationLink {
                DictionaryDetailView(entry: entry)
            } label: {
                DictionaryRowView(entry: entry)
            }
            .accessibilityLabel(entry.term)
            .accessibilityValue(entry.detailSummary)
        }
    }

    private var resultSummary: String {
        let total = DictionaryData.entries.count
        return "\(visibleEntryCount) substring \(visibleEntryCount == 1 ? "match" : "matches") of \(total) words"
    }
}

private struct DictionaryResultsHeaderView: View {
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Results")
            Text(summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Results")
        .accessibilityValue(summary)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct DictionarySectionHeaderView: View {
    let title: String
    var wordCount: Int?

    var body: some View {
        Text(title)
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(.isHeader)
    }

    private var accessibilityLabel: String {
        if title == "Results" { return title }
        return title == "#" ? "Symbols" : "Section \(title)"
    }

    private var accessibilityValue: String {
        guard let wordCount else { return "" }
        return "\(wordCount) \(wordCount == 1 ? "word" : "words")"
    }
}

private struct DictionaryRowView: View {
    let entry: DictionaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.term)
                .font(.headline)

            Text(entry.detailSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct DictionaryDetailView: View {
    let entry: DictionaryEntry

    var body: some View {
        Form {
            Section("Word") {
                Text(entry.term)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)

                Text("Bundled Unix word list item")
                    .foregroundStyle(.secondary)
            }

            Section("Details") {
                LabeledContent("Characters", value: "\(entry.term.count)")
                LabeledContent("Words", value: "\(entry.term.split(separator: " ").count)")
                LabeledContent("Section", value: entry.sectionTitle)
                LabeledContent("Source", value: "web2a word list")
            }

            Section("Nearby Words") {
                ForEach(DictionaryData.neighbors(for: entry)) { relatedEntry in
                    Text(relatedEntry.term)
                }
            }
        }
        .navigationTitle(entry.term)
    }
}

#Preview {
    NavigationStack {
        DictionaryView()
    }
}
