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
    @State private var scrolledID: Int?

    /// Suppresses handleScrollChange when advancePage is driving the scroll.
    @State private var suppressScrollHandler = false

    private let cards = FeaturedCard.sampleCards

    /// Number of ghost cards padded at each end — must be >= visible count
    /// so the user never sees the buffer boundary.
    private static let ghostCount = 3

    /// Buffer: [last N ghosts] + all cards + [first N ghosts].
    /// Each entry gets a unique buffer ID (offset) for scroll tracking.
    private var buffer: [BufferEntry] {
        let ghostCount = Self.ghostCount
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
    }

    /// The buffer ID of the first real card.
    private var firstRealID: Int { Self.ghostCount }

    /// The buffer ID of the last real card.
    private var lastRealID: Int { Self.ghostCount + cards.count - 1 }

    private var currentLogicalIndex: Int {
        guard let scrolledID else { return 0 }
        let entry = buffer.first { $0.bufferID == scrolledID }
        return entry?.logicalIndex ?? 0
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Featured")
                .font(.caption2)
                .hidden()
                .accessibilityLabel("Featured carousel")
                .accessibilityValue(carouselAccessibilityValue)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(buffer) { entry in
                        FeaturedCardView(
                            card: entry.card,
                            logicalIndex: entry.logicalIndex,
                            totalCards: cards.count
                        )
                        .containerRelativeFrame(.horizontal, count: 3, spacing: 8)
                        .id(entry.bufferID)
                        .accessibilityHidden(entry.isGhost)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolledID)
            .frame(height: 100)
            .onAppear {
                scrolledID = firstRealID
            }
            .onChange(of: scrolledID) { _, newValue in
                handleScrollChange(newValue)
            }

            HStack(spacing: 6) {
                ForEach(0..<cards.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentLogicalIndex ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page indicator")
            .accessibilityValue(carouselAccessibilityValue)
            .accessibilityHint("Swipe up or down to change page")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    advancePage(by: 1)
                case .decrement:
                    advancePage(by: -1)
                @unknown default:
                    break
                }
            }
        }
    }

    private var carouselAccessibilityValue: String {
        "Page \(currentLogicalIndex + 1) of \(cards.count)"
    }

    private func handleScrollChange(_ newID: Int?) {
        guard let newID else { return }
        if suppressScrollHandler {
            suppressScrollHandler = false
            return
        }

        // Scrolled into the leading ghost region → jump to real equivalent near the end
        if newID < firstRealID {
            let logicalIndex = buffer.first { $0.bufferID == newID }?.logicalIndex ?? 0
            let targetID = Self.ghostCount + logicalIndex
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                scrolledID = targetID
            }
        } else if newID > lastRealID {
            let logicalIndex = buffer.first { $0.bufferID == newID }?.logicalIndex ?? 0
            let targetID = Self.ghostCount + logicalIndex
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                scrolledID = targetID
            }
        }
    }

    private func advancePage(by offset: Int) {
        let newLogical = (currentLogicalIndex + offset + cards.count) % cards.count
        let targetBufferID = Self.ghostCount + newLogical
        suppressScrollHandler = true
        withAnimation { scrolledID = targetBufferID }
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
