import SwiftUI

struct PlaylistView: View {
    @State private var songs: [Song] = []
    @State private var nextTrack = 1
    @State private var autoplay: AutoplayState = .off
    @State private var nowPlayingID: Song.ID?

    enum AutoplayState {
        case off
        case running(Timer)

        var isOn: Bool {
            if case .running = self { return true }
            return false
        }
    }

    private var nowPlaying: Song? { songs.first { $0.id == nowPlayingID } }

    var body: some View {
        List {
            if let playing = nowPlaying {
                Section {
                    NowPlayingRow(song: playing)
                }
            }

            Section {
                HStack(spacing: 12) {
                    Button { addSong() } label: {
                        Label("Add Song", systemImage: "plus.circle.fill")
                    }

                    Spacer()

                    Button { addAlbum() } label: {
                        Label("Add Album", systemImage: "rectangle.stack.badge.plus")
                    }
                }

                if !songs.isEmpty {
                    Button(role: .destructive) { clearPlaylist() } label: {
                        Label("Clear Playlist", systemImage: "trash")
                    }
                }

                Toggle(isOn: Binding(
                    get: { autoplay.isOn },
                    set: { newValue in
                        if newValue { startAutoplay() } else { stopAutoplay() }
                    }
                )) {
                    Label("Autoplay", systemImage: "infinity")
                }
            }

            Section(songs.isEmpty ? "Playlist" : "Playlist — \(songs.count) songs") {
                if songs.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing Queued", systemImage: "music.note.list")
                    } description: {
                        Text("Add some songs to get started.")
                    }
                } else {
                    ForEach(songs) { song in
                        SongRow(song: song, isPlaying: song.id == nowPlayingID) {
                            nowPlayingID = song.id
                        } onLike: {
                            toggleLike(song)
                        }
                        .accessibilityAction(named: "Remove from playlist") {
                            removeSong(song)
                        }
                    }
                    .onDelete { offsets in
                        let removed = offsets.map { songs[$0] }
                        songs.remove(atOffsets: offsets)
                        for s in removed {
                            if s.id == nowPlayingID { nowPlayingID = nil }
                        }
                    }
                    .onMove { from, to in
                        songs.move(fromOffsets: from, toOffset: to)
                    }
                }
            }
        }
        .navigationTitle("Playlist")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { shufflePlaylist() } label: {
                    Image(systemName: "shuffle")
                }
                .disabled(songs.count < 2)

                EditButton()
            }
        }
        .onDisappear { stopAutoplay() }
    }

    private var queueString: String {
        songs.map { String($0.track) }.joined(separator: ",")
    }

    // MARK: - Insert

    private func addSong() {
        let song = Song.random(track: nextTrack)
        songs.append(song)
        if nowPlayingID == nil { nowPlayingID = song.id }
        nextTrack += 1
    }

    private func addAlbum() {
        let count = Int.random(in: 3...5)
        for _ in 0..<count { addSong() }
    }

    // MARK: - Remove

    private func removeSong(_ song: Song) {
        songs.removeAll { $0.id == song.id }
        if song.id == nowPlayingID { nowPlayingID = songs.first?.id }
    }

    private func clearPlaylist() {
        songs.removeAll()
        nowPlayingID = nil
    }

    // MARK: - Reorder

    private func shufflePlaylist() {
        guard songs.count >= 2 else { return }
        let originalOrder = songs.map(\.id)
        songs.shuffle()
        if songs.map(\.id) == originalOrder {
            let first = songs.removeFirst()
            songs.append(first)
        }
    }

    private func toggleLike(_ song: Song) {
        guard let idx = songs.firstIndex(where: { $0.id == song.id }) else { return }
        songs[idx].isLiked.toggle()
    }

    // MARK: - Autoplay

    private func startAutoplay() {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                if songs.count >= 12 {
                    if let first = songs.first {
                        removeSong(first)
                    }
                } else {
                    addSong()
                }
            }
        }
        autoplay = .running(timer)
    }

    private func stopAutoplay() {
        if case .running(let timer) = autoplay {
            timer.invalidate()
        }
        autoplay = .off
    }
}

// MARK: - Song Row

private struct SongRow: View {
    let song: Song
    let isPlaying: Bool
    let onTap: () -> Void
    let onLike: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(song.color.gradient)
                        .frame(width: 44, height: 44)
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : song.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.body)
                        .foregroundStyle(isPlaying ? Color.accentColor : .primary)
                    Text(song.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(song.duration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button { onLike() } label: {
                    Image(systemName: song.isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(song.isLiked ? .red : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .buttonStyle(.plain)
        .accessibilityCustomContent(Text("Duration"), Text(song.duration))
    }
}

// MARK: - Now Playing Row

private struct NowPlayingRow: View {
    let song: Song

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(song.color.gradient)
                    .frame(width: 56, height: 56)
                Image(systemName: "speaker.wave.2.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Now Playing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(song.title)
                    .font(.headline)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityCustomContent(Text("Duration"), Text(song.duration))
    }
}

// MARK: - Model

private struct Song: Identifiable {
    let id = UUID()
    let track: Int
    let title: String
    let artist: String
    let durationSeconds: Int
    let icon: String
    let color: Color
    var isLiked: Bool = false

    var duration: String {
        let m = durationSeconds / 60
        let s = durationSeconds % 60
        return "\(m):\(String(format: "%02d", s))"
    }

    static func random(track: Int) -> Song {
        let pick = catalog.randomElement() ?? catalog[0]
        return Song(
            track: track,
            title: pick.title,
            artist: pick.artist,
            durationSeconds: Int.random(in: 140...320),
            icon: pick.icon,
            color: pick.color
        )
    }
}

private let catalog: [(title: String, artist: String, icon: String, color: Color)] = [
    ("Midnight Drive", "Neon Coast", "car.fill", .indigo),
    ("Golden Hour", "Saffron", "sun.max.fill", .orange),
    ("Paper Planes", "The Origami", "paperplane.fill", .cyan),
    ("Deep Water", "Marina Blue", "drop.fill", .blue),
    ("Wildfire", "Ember & Ash", "flame.fill", .red),
    ("Static", "Ghost Channel", "antenna.radiowaves.left.and.right", .gray),
    ("Bloom", "Ivy Park", "leaf.fill", .green),
    ("Retrograde", "Cassette Club", "recordingtape", .purple),
    ("Telescope", "Far Light", "sparkles", .yellow),
    ("Undertow", "Salt & Stone", "water.waves", .teal),
    ("Phantom", "Night Vinyl", "moon.stars.fill", .indigo),
    ("Clockwork", "Brass Automaton", "gearshape.2.fill", .brown),
    ("Daybreak", "Morning Ritual", "sunrise.fill", .orange),
    ("Echoes", "Canyon Wire", "waveform", .mint),
    ("Frostbite", "Polar Drift", "snowflake", .cyan),
]

#Preview {
    NavigationStack {
        PlaylistView()
    }
    .environment(AppSettings())
}
