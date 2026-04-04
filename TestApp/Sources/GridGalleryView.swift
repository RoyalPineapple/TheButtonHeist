import SwiftUI

/// A grid gallery backed by UICollectionView (via LazyVGrid in a ScrollView).
/// Tests two-axis scrolling, grid layout, and mixed content types for
/// accessibility element discovery and scroll-to-visible operations.
struct GridGalleryView: View {
    @State private var selectedItems: Set<Int> = []
    @State private var searchText = ""

    private let items: [GalleryItem] = (0..<120).map { GalleryItem(index: $0) }

    private var filteredItems: [GalleryItem] {
        if searchText.isEmpty { return items }
        return items.filter { item in
            item.title.localizedCaseInsensitiveContains(searchText)
            || item.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(filteredItems) { item in
                    GridCell(
                        item: item,
                        isSelected: selectedItems.contains(item.index)
                    ) {
                        toggleSelection(item.index)
                    }
                }
            }
            .padding(.horizontal, 12)

            // Footer with count
            Text("\(filteredItems.count) items · \(selectedItems.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
        .navigationTitle("Grid Gallery")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Filter photos")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    selectedItems.removeAll()
                }
                .disabled(selectedItems.isEmpty)
            }
        }
    }

    private func toggleSelection(_ index: Int) {
        if selectedItems.contains(index) {
            selectedItems.remove(index)
        } else {
            selectedItems.insert(index)
        }
    }
}

// MARK: - Grid Cell

private struct GridCell: View {
    let item: GalleryItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(item.color.opacity(0.15))
                        .frame(height: 100)

                    Image(systemName: item.icon)
                        .font(.system(size: 32))
                        .foregroundStyle(item.color)

                    if isSelected {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.white, .blue)
                                    .font(.title3)
                                    .padding(6)
                            }
                            Spacer()
                        }
                    }
                }

                Text(item.title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(item.category)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityValue(isSelected ? "selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Double tap to deselect" : "Double tap to select")
        .accessibilityAction(named: "Toggle Selection") {
            onTap()
        }
    }
}

// MARK: - Data Model

struct GalleryItem: Identifiable {
    let index: Int
    var id: Int { index }

    var title: String {
        let names = ["Sunset", "Mountain", "Ocean", "Forest", "Desert",
                     "River", "Lake", "Canyon", "Glacier", "Meadow",
                     "Volcano", "Waterfall"]
        return "\(names[index % names.count]) \(index)"
    }

    var category: String {
        let categories = ["Nature", "Landscape", "Aerial", "Macro", "Wildlife", "Urban"]
        return categories[index % categories.count]
    }

    var icon: String {
        let icons = ["photo", "mountain.2", "water.waves", "leaf", "sun.max",
                     "drop", "camera", "sparkles", "star", "heart",
                     "flame", "bolt"]
        return icons[index % icons.count]
    }

    var color: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .teal,
                                .indigo, .pink, .mint, .cyan, .brown, .yellow]
        return colors[index % colors.count]
    }
}
