import SwiftUI

struct PhotosView: View {
    @State private var photos: [Photo] = Photo.defaultPhotos
    @State private var mode: BrowseMode = .browsing

    enum BrowseMode {
        case browsing
        case selecting(Set<UUID>)

        var isSelecting: Bool {
            if case .selecting = self { return true }
            return false
        }

        var selectedIDs: Set<UUID> {
            if case .selecting(let ids) = self { return ids }
            return []
        }
    }

    private var selectedCount: Int {
        mode.selectedIDs.count
    }

    private var allSelected: Bool {
        !photos.isEmpty && mode.selectedIDs.count == photos.count
    }

    var body: some View {
        Group {
            if photos.isEmpty {
                ContentUnavailableView {
                    Label("No Photos", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("Your photo library is empty.")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(photos) { photo in
                            PhotoCell(
                                photo: photo,
                                isSelecting: mode.isSelecting,
                                isSelected: mode.selectedIDs.contains(photo.id),
                                onTap: { cellTapped(photo) }
                            )
                            .accessibilityLabel(cellLabel(for: photo))
                            .accessibilityAddTraits(mode.isSelecting && mode.selectedIDs.contains(photo.id) ? .isSelected : [])
                            .accessibilityRemoveTraits(mode.isSelecting && !mode.selectedIDs.contains(photo.id) ? .isSelected : [])
                        }
                    }
                    .padding(8)
                }
            }
        }
        .navigationTitle("Photos")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if mode.isSelecting {
                    Button(allSelected ? "Deselect All" : "Select All") {
                        toggleSelectAll()
                    }

                    if selectedCount > 0 {
                        Button("Delete Selected (\(selectedCount))", role: .destructive) {
                            deleteSelected()
                        }
                    }
                }

                Button(mode.isSelecting ? "Cancel" : "Select") {
                    toggleSelectMode()
                }
            }
        }
        .animation(.default, value: photos.map(\.id))
        .animation(.default, value: mode.isSelecting)
    }

    private func cellTapped(_ photo: Photo) {
        switch mode {
        case .browsing:
            break
        case .selecting(var selected):
            if selected.contains(photo.id) {
                selected.remove(photo.id)
            } else {
                selected.insert(photo.id)
            }
            mode = .selecting(selected)
        }
    }

    private func toggleSelectMode() {
        switch mode {
        case .browsing:
            mode = .selecting([])
        case .selecting:
            mode = .browsing
        }
    }

    private func toggleSelectAll() {
        if allSelected {
            mode = .selecting([])
        } else {
            mode = .selecting(Set(photos.map(\.id)))
        }
    }

    private func deleteSelected() {
        photos.removeAll { mode.selectedIDs.contains($0.id) }
        mode = .browsing
    }

    private func cellLabel(for photo: Photo) -> String {
        if mode.isSelecting && mode.selectedIDs.contains(photo.id) {
            return "\(photo.name), selected"
        }
        return photo.name
    }
}

// MARK: - Subviews

private struct PhotoCell: View {
    let photo: Photo
    let isSelecting: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(photo.color.gradient)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            Image(systemName: photo.icon)
                                .font(.title)
                                .foregroundStyle(.white)
                        }

                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? .blue : .white.opacity(0.8))
                            .padding(6)
                    }
                }

                Text(photo.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Model

private struct Photo: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    let icon: String

    static let defaultPhotos: [Photo] = [
        Photo(name: "Mountain Sunset", color: .orange, icon: "mountain.2.fill"),
        Photo(name: "Ocean Waves", color: .blue, icon: "water.waves"),
        Photo(name: "Forest Trail", color: .green, icon: "tree.fill"),
        Photo(name: "Desert Dunes", color: .yellow, icon: "sun.max.fill"),
        Photo(name: "Snowy Peaks", color: .cyan, icon: "snowflake"),
        Photo(name: "City Lights", color: .purple, icon: "building.2.fill"),
        Photo(name: "Starry Night", color: .indigo, icon: "star.fill"),
        Photo(name: "Autumn Leaves", color: .red, icon: "leaf.fill"),
        Photo(name: "Coral Reef", color: .teal, icon: "fish.fill"),
        Photo(name: "Lavender Field", color: .mint, icon: "camera.macro"),
        Photo(name: "Thunderstorm", color: .gray, icon: "cloud.bolt.fill"),
        Photo(name: "Cherry Blossoms", color: .pink, icon: "camera.filters"),
        Photo(name: "Misty Lake", color: .cyan.opacity(0.7), icon: "drop.fill"),
        Photo(name: "Golden Hour", color: .orange.opacity(0.8), icon: "sun.haze.fill"),
        Photo(name: "Rainforest", color: .green.opacity(0.8), icon: "leaf.arrow.triangle.circlepath"),
        Photo(name: "Northern Lights", color: .green.opacity(0.6), icon: "sparkles"),
        Photo(name: "Volcanic Ash", color: .brown, icon: "flame.fill"),
        Photo(name: "Frozen Lake", color: .blue.opacity(0.5), icon: "snowflake.circle"),
        Photo(name: "Wildflowers", color: .pink.opacity(0.7), icon: "camera.macro"),
        Photo(name: "Canyon View", color: .red.opacity(0.7), icon: "mountain.2"),
    ]
}

#Preview {
    NavigationStack {
        PhotosView()
    }
    .environment(AppSettings())
}
