import SwiftUI
import UIKit

internal struct NestedScrollScenarioView: View {
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
