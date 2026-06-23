import SwiftUI

// MARK: - Model

struct DictionaryEntry: Identifiable, Hashable {
    let id: Int
    let term: String

    var componentCount: Int {
        term.split(separator: " ").count
    }

    var isPhrase: Bool {
        componentCount > 1
    }

    var kind: String {
        isPhrase ? "phrase" : "word"
    }

    var sectionTitle: String {
        guard let first = term.first else { return "#" }
        let title = String(first).uppercased()
        return title.range(of: "[A-Z]", options: .regularExpression) == nil ? "#" : title
    }

    var detailSummary: String {
        let format = componentCount == 1 ? "single word" : "\(componentCount)-word phrase"
        return "\(format), \(term.count) character\(term.count == 1 ? "" : "s")"
    }

}

struct DictionarySection: Identifiable {
    let title: String
    let entries: [DictionaryEntry]

    var id: String { title }
}

enum DictionaryFilter: String, CaseIterable, Identifiable {
    case all
    case words
    case phrases

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .words: return "Words"
        case .phrases: return "Phrases"
        }
    }

    func includes(_ entry: DictionaryEntry) -> Bool {
        switch self {
        case .all:
            return true
        case .words:
            return !entry.isPhrase
        case .phrases:
            return entry.isPhrase
        }
    }
}

// MARK: - Data

enum DictionaryData {
    static let entries: [DictionaryEntry] = loadEntries()
    static let sections: [DictionarySection] = makeSections(from: entries)
    static let phraseCount = entries.filter(\.isPhrase).count

    static func sections(matching searchText: String, filter: DictionaryFilter) -> [DictionarySection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredEntries = entries.filter { entry in
            filter.includes(entry) && (
                query.isEmpty || entry.term.localizedCaseInsensitiveContains(query)
            )
        }

        guard filter != .all || !query.isEmpty else { return sections }
        return makeSections(from: filteredEntries)
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
    @State private var filter = DictionaryFilter.all

    private var visibleSections: [DictionarySection] {
        DictionaryData.sections(matching: searchText, filter: filter)
    }

    private var visibleEntryCount: Int {
        visibleSections.reduce(0) { $0 + $1.entries.count }
    }

    private var isSearchMode: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isFilteredMode: Bool {
        isSearchMode || filter != .all
    }

    var body: some View {
        List {
            Section {
                DictionaryOverviewView(
                    totalWordCount: DictionaryData.entries.count,
                    sectionCount: DictionaryData.sections.count,
                    phraseCount: DictionaryData.phraseCount,
                    visibleWordCount: visibleEntryCount,
                    filter: filter,
                    isSearchMode: isSearchMode
                )

                Picker("Word Type", selection: $filter) {
                    ForEach(DictionaryFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }

            if isFilteredMode {
                Section {
                    if visibleSections.isEmpty {
                        ContentUnavailableView {
                            Label("No Matches", systemImage: "magnifyingglass")
                        } description: {
                            Text(emptyResultMessage)
                        }
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
        let noun = visibleEntryCount == 1 ? "entry" : "entries"
        if isSearchMode {
            return "\(visibleEntryCount) matching \(noun) of \(total) total"
        }
        return "\(visibleEntryCount) \(filter.title.lowercased()) \(noun) of \(total) total"
    }

    private var emptyResultMessage: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return "No \(filter.title.lowercased()) are available."
        }
        return "No \(filter.title.lowercased()) contain \(query)."
    }
}

private struct DictionaryOverviewView: View {
    let totalWordCount: Int
    let sectionCount: Int
    let phraseCount: Int
    let visibleWordCount: Int
    let filter: DictionaryFilter
    let isSearchMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DictionaryMetricView(title: "Entries", value: totalWordCount.formatted())
                DictionaryMetricView(title: "Sections", value: sectionCount.formatted())
                DictionaryMetricView(
                    title: isSearchMode || filter != .all ? "Results" : "Phrases",
                    value: (isSearchMode || filter != .all ? visibleWordCount : phraseCount).formatted()
                )
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Words overview")
        .accessibilityValue(accessibilityValue)
    }

    private var description: String {
        if isSearchMode {
            return "Search results from the bundled word list."
        }
        if filter != .all {
            return "Showing \(filter.title.lowercased()) from the bundled word list."
        }
        return "Bundled word list with sectioned browsing and substring search."
    }

    private var accessibilityValue: String {
        if isSearchMode || filter != .all {
            return "\(visibleWordCount) visible entries, \(totalWordCount) total entries, \(sectionCount) sections"
        }
        return "\(totalWordCount) total entries, \(sectionCount) sections, \(phraseCount) phrases"
    }
}

private struct DictionaryMetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                LabeledContent("Type", value: entry.kind.capitalized)
                LabeledContent("Words", value: "\(entry.componentCount)")
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
