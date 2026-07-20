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

    func resultNoun(count: Int) -> String {
        switch self {
        case .all:
            return count == 1 ? "entry" : "entries"
        case .words:
            return count == 1 ? "word" : "words"
        case .phrases:
            return count == 1 ? "phrase" : "phrases"
        }
    }
}

// MARK: - Data

enum DictionaryData {
    static let entries: [DictionaryEntry] = makeEntries()
    static let sections: [DictionarySection] = makeSections(from: entries)
    static let phraseCount = entries.filter(\.isPhrase).count

    static func sections(matching searchText: String, filter: DictionaryFilter) -> [DictionarySection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard filter != .all || !query.isEmpty else { return sections }

        let filteredEntries = entries.filter { entry in
            filter.includes(entry) && (
                query.isEmpty || entry.term.localizedCaseInsensitiveContains(query)
            )
        }

        return makeSections(from: filteredEntries)
    }

    static func neighbors(for entry: DictionaryEntry) -> [DictionaryEntry] {
        let lowerBound = max(entries.startIndex, entry.id - 2)
        let upperBound = min(entries.endIndex, entry.id + 3)
        return entries[lowerBound..<upperBound].filter { $0.id != entry.id }
    }

    private static func makeEntries() -> [DictionaryEntry] {
        seedTerms
            .flatMap { seed in
                [seed] + (1...24).map { index in
                    index.isMultiple(of: 5) ? "\(seed) phrase \(index)" : "\(seed)-\(index)"
                }
            }
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

    private static let seedTerms = [
        "abacus",
        "blueprint",
        "cipher",
        "drift",
        "ember",
        "fable",
        "glyph",
        "harbor",
        "index",
        "jigsaw",
        "keystone",
        "lantern",
        "matrix",
        "notebook",
        "oracle",
        "puzzle",
        "quartz",
        "ribbon",
        "signal",
        "tangent",
        "utopia",
        "vector",
        "waypoint",
        "xylophone",
        "yonder",
        "zymurgy",
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
                    totalEntryCount: DictionaryData.entries.count,
                    sectionCount: DictionaryData.sections.count,
                    phraseCount: DictionaryData.phraseCount,
                    visibleEntryCount: visibleEntryCount,
                    filter: filter,
                    isSearchMode: isSearchMode
                )

                Picker("Entry Type", selection: $filter) {
                    ForEach(DictionaryFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }

            if isFilteredMode {
                Section {
                    if visibleSections.isEmpty {
                        UnavailablePlaceholderView(
                            title: "No Matches",
                            systemImage: "magnifyingglass",
                            description: emptyResultMessage
                        )
                    } else {
                        ForEach(visibleSections) { section in
                            DictionarySectionHeaderView(title: section.title, entryCount: section.entries.count)
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
                        DictionarySectionHeaderView(title: section.title, entryCount: section.entries.count)
                    }
                }
            }
        }
        .navigationTitle("Words")
        .searchable(text: $searchText, prompt: "Search entries")
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
        let noun = filter.resultNoun(count: visibleEntryCount)
        if isSearchMode {
            return "\(visibleEntryCount) matching \(noun) of \(total) total"
        }
        return "\(visibleEntryCount) \(noun) of \(total) total"
    }

    private var emptyResultMessage: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let noun = filter.resultNoun(count: 2)
        if query.isEmpty {
            return "No \(noun) are available."
        }
        return "No \(noun) contain \(query)."
    }
}

private struct DictionaryOverviewView: View {
    let totalEntryCount: Int
    let sectionCount: Int
    let phraseCount: Int
    let visibleEntryCount: Int
    let filter: DictionaryFilter
    let isSearchMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DictionaryMetricView(title: "Entries", value: totalEntryCount.formatted())
                DictionaryMetricView(title: "Sections", value: sectionCount.formatted())
                DictionaryMetricView(
                    title: isSearchMode || filter != .all ? "Results" : "Phrases",
                    value: (isSearchMode || filter != .all ? visibleEntryCount : phraseCount).formatted()
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
        return "Browse entries by section, search by substring, or filter by type."
    }

    private var accessibilityValue: String {
        if isSearchMode || filter != .all {
            return "\(visibleEntryCount) visible entries, \(totalEntryCount) total entries, \(sectionCount) sections"
        }
        return "\(totalEntryCount) total entries, \(sectionCount) sections, \(phraseCount) phrases"
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
    var entryCount: Int?

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
        guard let entryCount else { return "" }
        return "\(entryCount) \(entryCount == 1 ? "entry" : "entries")"
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
            Section("Entry") {
                Text(entry.term)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)

                Text("Entry from the word list")
                    .foregroundStyle(.secondary)
            }

            Section("Details") {
                LabeledContent("Characters", value: "\(entry.term.count)")
                LabeledContent("Type", value: entry.kind.capitalized)
                LabeledContent("Words", value: "\(entry.componentCount)")
                LabeledContent("Section", value: entry.sectionTitle)
                LabeledContent("Source", value: "Word list")
            }

            Section("Nearby Entries") {
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
