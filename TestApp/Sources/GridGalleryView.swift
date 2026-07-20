import SwiftUI

/// A grid gallery backed by UICollectionView (via LazyVGrid in a ScrollView).
/// Tests two-axis scrolling, grid layout, and mixed content types for
/// accessibility element discovery and scroll-to-visible operations.
/// Includes a looping carousel at the top to stress-test horizontal scroll
/// detection and infinite-scroll boundary handling.
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
            FeaturedCarousel()
                .padding(.bottom, 8)

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
    let onTap: @MainActor () -> Void

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
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelected ? "selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Double tap to deselect" : "Double tap to select")
        .accessibilityAction(named: "Toggle Selection") {
            onTap()
        }
    }
}

// MARK: - Looping Carousel

/// A horizontal carousel showing 3 cards at a time that loops infinitely.
/// The buffer array pads ghost copies of the cards at each end. When the
/// scroll position reaches the ghost region, it silently jumps back to the
/// corresponding real cards — creating the illusion of infinite scroll.
///
/// This stresses scroll detection harder than a single-page carousel because
/// 3 visible cards means the agent sees multiple elements at once, and the
/// ghost buffer is wider (3 cards on each side instead of 1).
private struct FeaturedCarousel: View {
    private static let cards = FeaturedCard.sampleCards
    private var cards: [FeaturedCard] { Self.cards }

    /// Number of ghost cards padded at each end — must be >= visible count
    /// so the user never sees the buffer boundary.
    private static let ghostCount = 3

    /// Buffer: [last N ghosts] + all cards + [first N ghosts]. Computed once
    /// at file scope since `cards` and `ghostCount` are static.
    private static let buffer: [BufferEntry] = {
        let leadingGhosts = cards.suffix(ghostCount).enumerated().map { index, card in
            BufferEntry(bufferID: index, card: card, logicalIndex: cards.count - ghostCount + index, isGhost: true)
        }
        let realCards = cards.enumerated().map { index, card in
            BufferEntry(bufferID: ghostCount + index, card: card, logicalIndex: index, isGhost: false)
        }
        let trailingGhosts = cards.prefix(ghostCount).enumerated().map { index, card in
            BufferEntry(bufferID: ghostCount + cards.count + index, card: card, logicalIndex: index, isGhost: true)
        }
        return leadingGhosts + realCards + trailingGhosts
    }()

    private var buffer: [BufferEntry] { Self.buffer }

    var body: some View {
        VStack(spacing: 8) {
            Text("Featured")
                .font(.caption2)
                .hidden()
                .accessibilityLabel("Featured carousel")
                .accessibilityValue("\(cards.count) featured cards")
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(buffer) { entry in
                        FeaturedCardView(
                            card: entry.card,
                            logicalIndex: entry.logicalIndex,
                            totalCards: cards.count
                        )
                        .frame(width: 120)
                        .id(entry.bufferID)
                        .accessibilityHidden(entry.isGhost)
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 100)

            HStack(spacing: 6) {
                ForEach(0..<cards.count, id: \.self) { index in
                    Circle()
                        .fill(index == 0 ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page indicator")
            .accessibilityValue("\(cards.count) cards")
        }
    }
}

private struct BufferEntry: Identifiable {
    let bufferID: Int
    let card: FeaturedCard
    let logicalIndex: Int
    let isGhost: Bool

    var id: Int { bufferID }
}

private struct FeaturedCardView: View {
    let card: FeaturedCard
    let logicalIndex: Int
    let totalCards: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(card.color.gradient)

            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: card.icon)
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.9))

                Text(card.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)

                Text(card.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("Page \(logicalIndex + 1) of \(totalCards)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Featured Card Data

private struct FeaturedCard {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    static let sampleCards: [FeaturedCard] = [
        FeaturedCard(title: "Editors' Choice", subtitle: "Top picks this week", icon: "star.fill", color: .blue),
        FeaturedCard(title: "New Arrivals", subtitle: "Fresh content daily", icon: "sparkles", color: .purple),
        FeaturedCard(title: "Collections", subtitle: "Curated sets for you", icon: "rectangle.stack.fill", color: .orange),
        FeaturedCard(title: "Trending Now", subtitle: "Most popular today", icon: "flame.fill", color: .red),
        FeaturedCard(title: "Staff Picks", subtitle: "Hand-selected favorites", icon: "heart.fill", color: .pink),
        FeaturedCard(title: "Seasonal", subtitle: "Spring photography", icon: "leaf.fill", color: .green),
    ]
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
