import SwiftUI

// MARK: - Models

struct Album: Identifiable {
    let id: String
    let title: String
    let artist: String
    let symbol: String
    let year: Int
}

struct Genre: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let albums: [Album]
}

// MARK: - Albums View

struct AlbumFlowView: View {
    @State private var playback: PlaybackState = .idle
    @State private var queue: [Album] = []
    @State private var favorites: Set<String> = []

    enum PlaybackState {
        case idle
        case playing(Album)
        case paused(Album)

        var currentAlbum: Album? {
            switch self {
            case .idle: return nil
            case .playing(let album), .paused(let album): return album
            }
        }

        var isPlaying: Bool {
            if case .playing = self { return true }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 28) {
                    featuredSection
                    ForEach(Genre.catalog) { genre in
                        genreSection(genre)
                    }
                    Spacer(minLength: 20)
                }
                .padding(.top, 8)
            }

            if playback.currentAlbum != nil || !queue.isEmpty {
                miniPlayer
            }
        }
        .navigationTitle("Albums")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    // MARK: - Featured

    private var featuredSection: some View {
        let featured = Genre.catalog[2].albums[0] // Binary Sunset - Last Light Protocol

        return Button {
            playback = .playing(featured)
            NSLog("[Albums] Selected: %@ by %@", featured.title, featured.artist)
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(albumColor(featured).gradient)
                    .frame(height: 200)
                    .overlay(alignment: .trailing) {
                        Image(systemName: featured.symbol)
                            .font(.system(size: 80))
                            .foregroundStyle(.white.opacity(0.15))
                            .padding(.trailing, 24)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("FEATURED")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(featured.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text(featured.artist)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(20)
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Featured: \(featured.title) by \(featured.artist)")
    }

    // MARK: - Genre Section

    private func genreSection(_ genre: Genre) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(genre.name, systemImage: genre.symbol)
                    .font(.title3.bold())
                Spacer()
            }
            .padding(.horizontal)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(genre.albums) { album in
                        albumCard(album)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Album Card

    private func albumCard(_ album: Album) -> some View {
        let isSelected = playback.currentAlbum?.id == album.id
        let isQueued = queue.contains { $0.id == album.id }

        return Button {
            playback = .playing(album)
            NSLog("[Albums] Selected: %@ by %@", album.title, album.artist)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(albumColor(album).gradient)
                        .frame(width: 150, height: 150)
                        .shadow(color: albumColor(album).opacity(0.3), radius: 8, y: 4)

                    Image(systemName: album.symbol)
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                )

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(album.title)
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(album.artist)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Menu {
                        Button {
                            if isQueued {
                                queue.removeAll { $0.id == album.id }
                                NSLog("[Albums] Removed from queue: %@", album.title)
                            } else {
                                queue.append(album)
                                NSLog("[Albums] Added to queue: %@", album.title)
                            }
                        } label: {
                            Label(
                                isQueued ? "Remove from Queue" : "Add to Queue",
                                systemImage: isQueued ? "minus.circle" : "text.badge.plus"
                            )
                        }
                        Button {
                            if favorites.contains(album.id) {
                                favorites.remove(album.id)
                                NSLog("[Albums] Unfavorited: %@", album.title)
                            } else {
                                favorites.insert(album.id)
                                NSLog("[Albums] Favorited: %@", album.title)
                            }
                        } label: {
                            Label(
                                favorites.contains(album.id) ? "Remove from Favorites" : "Add to Favorites",
                                systemImage: favorites.contains(album.id) ? "heart.slash" : "heart"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .accessibilityHidden(true)
                }
            }
            .frame(width: 150)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(album.title) by \(album.artist)")
        .accessibilityValue(isQueued ? "in queue" : "")
        .accessibilityAction(named: isQueued ? "Remove from Queue" : "Add to Queue") {
            if isQueued {
                queue.removeAll { $0.id == album.id }
                NSLog("[Albums] Removed from queue: %@", album.title)
            } else {
                queue.append(album)
                NSLog("[Albums] Added to queue: %@", album.title)
            }
        }
        .accessibilityAction(named: favorites.contains(album.id) ? "Remove from Favorites" : "Add to Favorites") {
            if favorites.contains(album.id) {
                favorites.remove(album.id)
                NSLog("[Albums] Unfavorited: %@", album.title)
            } else {
                favorites.insert(album.id)
                NSLog("[Albums] Favorited: %@", album.title)
            }
        }
    }

    // MARK: - Mini Player

    private var miniPlayer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if let album = playback.currentAlbum {
                    Image(systemName: album.symbol)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(albumColor(album).gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(album.title)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(album.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if !queue.isEmpty {
                                Text("·")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text("\(queue.count) in queue")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                } else if let next = queue.first {
                    Image(systemName: next.symbol)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(albumColor(next).gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Up Next")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(next.title)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                    }
                }

                Spacer()

                HStack(spacing: 20) {
                    Button {
                        switch playback {
                        case .idle: break
                        case .playing(let album): playback = .paused(album)
                        case .paused(let album): playback = .playing(album)
                        }
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }

                    Button {
                        if let next = queue.first {
                            queue.removeFirst()
                            playback = .playing(next)
                            NSLog("[Albums] Skipped to: %@ by %@", next.title, next.artist)
                        }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                    }
                    .disabled(queue.isEmpty)
                }
                .foregroundStyle(.primary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - Helpers

    private func albumColor(_ album: Album) -> Color {
        let hash = album.id.utf8.reduce(0) { $0 &+ Int($1) }
        return Color(
            hue: Double(hash % 360) / 360.0,
            saturation: 0.5,
            brightness: 0.75
        )
    }
}

// MARK: - Album Catalog

extension Genre {
    static let catalog: [Genre] = [
        Genre(id: "rock", name: "Rock", symbol: "guitars", albums: [
            Album(id: "shattered-glass", title: "Shattered Glass", artist: "Velvet Hammer", symbol: "guitars", year: 2024),
            Album(id: "iron-dawn", title: "Iron Dawn", artist: "The Rust Prophets", symbol: "bolt.fill", year: 2023),
            Album(id: "static-bloom", title: "Static Bloom", artist: "Crimson Voltage", symbol: "bolt.horizontal", year: 2025),
            Album(id: "eclipse-theory", title: "Eclipse Theory", artist: "Hollow Sun", symbol: "moon.fill", year: 2022),
            Album(id: "tidal-reckoning", title: "Tidal Reckoning", artist: "Black Fjord", symbol: "water.waves", year: 2024),
            Album(id: "wired-alive", title: "Wired Alive", artist: "The Amber Circuit", symbol: "cable.connector", year: 2023),
            Album(id: "fault-lines", title: "Fault Lines", artist: "Stone Meridian", symbol: "mountain.2.fill", year: 2025),
            Album(id: "midnight-frequency", title: "Midnight Frequency", artist: "Neon Wolves", symbol: "antenna.radiowaves.left.and.right", year: 2024),
            Album(id: "cathedral-of-noise", title: "Cathedral of Noise", artist: "The Obsidian Choir", symbol: "speaker.wave.3.fill", year: 2022),
            Album(id: "vanishing-point", title: "Vanishing Point", artist: "Phantom Ridge", symbol: "eye.slash.fill", year: 2023),
            Album(id: "orbit-decay", title: "Orbit Decay", artist: "Solar Debris", symbol: "sun.max.fill", year: 2025),
            Album(id: "thermal-drift", title: "Thermal Drift", artist: "The Glass Engines", symbol: "flame.fill", year: 2024),
        ]),
        Genre(id: "hiphop", name: "Hip Hop", symbol: "music.mic", albums: [
            Album(id: "depth-of-field", title: "Depth of Field", artist: "DJ Parallax", symbol: "camera.aperture", year: 2024),
            Album(id: "mosaic-state", title: "Mosaic State", artist: "MC Tessera", symbol: "square.grid.3x3.fill", year: 2023),
            Album(id: "urban-algorithm", title: "Urban Algorithm", artist: "The Cipher Collective", symbol: "number", year: 2025),
            Album(id: "pressure-system", title: "Pressure System", artist: "Lyric Storm", symbol: "cloud.bolt.fill", year: 2022),
            Album(id: "minted", title: "Minted", artist: "Gold Standard", symbol: "dollarsign.circle.fill", year: 2024),
            Album(id: "bedrock", title: "Bedrock", artist: "The Foundation", symbol: "building.columns.fill", year: 2023),
            Album(id: "blueprint", title: "Blueprint", artist: "Verbal Architect", symbol: "ruler.fill", year: 2025),
            Album(id: "runtime", title: "Runtime", artist: "Syntax Error", symbol: "chevron.left.forwardslash.chevron.right", year: 2024),
            Album(id: "coronation", title: "Coronation", artist: "Crown Theory", symbol: "crown.fill", year: 2022),
            Album(id: "full-spectrum", title: "Full Spectrum", artist: "The Bandwidth", symbol: "waveform", year: 2023),
            Album(id: "measured", title: "Measured", artist: "Metric System", symbol: "ruler", year: 2025),
            Album(id: "warmth", title: "Warmth", artist: "Analog Soul", symbol: "waveform.path.ecg", year: 2024),
        ]),
        Genre(id: "electronic", name: "Electronic", symbol: "waveform", albums: [
            Album(id: "last-light-protocol", title: "Last Light Protocol", artist: "Binary Sunset", symbol: "sunset.fill", year: 2024),
            Album(id: "charge-cycle", title: "Charge Cycle", artist: "The Capacitors", symbol: "battery.100.bolt", year: 2023),
            Album(id: "oscillation", title: "Oscillation", artist: "Waveform", symbol: "waveform.path", year: 2025),
            Album(id: "resolution", title: "Resolution", artist: "Pixel Drift", symbol: "rectangle.split.3x3", year: 2022),
            Album(id: "compound", title: "Compound", artist: "The Synthesis", symbol: "atom", year: 2024),
            Album(id: "entangled", title: "Entangled", artist: "Quantum Loop", symbol: "infinity", year: 2023),
            Album(id: "dataflood", title: "Dataflood", artist: "Digital Monsoon", symbol: "cloud.rain.fill", year: 2025),
            Album(id: "hertz-so-good", title: "Hertz So Good", artist: "The Frequency", symbol: "waveform.circle.fill", year: 2024),
            Album(id: "overload", title: "Overload", artist: "Circuit Breaker", symbol: "bolt.trianglebadge.exclamationmark.fill", year: 2022),
            Album(id: "modulation", title: "Modulation", artist: "Pulse Width", symbol: "slider.horizontal.3", year: 2023),
            Album(id: "artifact", title: "Artifact", artist: "The Glitch", symbol: "rectangle.on.rectangle.angled", year: 2025),
            Album(id: "absolute", title: "Absolute", artist: "Zero Kelvin", symbol: "snowflake", year: 2024),
        ]),
        Genre(id: "jazz", name: "Jazz", symbol: "music.note", albums: [
            Album(id: "sapphire-sessions", title: "Sapphire Sessions", artist: "The Indigo Quartet", symbol: "music.note.list", year: 2024),
            Album(id: "celestial-transit", title: "Celestial Transit", artist: "Miles Beyond", symbol: "moon.stars.fill", year: 2023),
            Album(id: "patina", title: "Patina", artist: "Copper Tone Trio", symbol: "circle.hexagongrid.fill", year: 2025),
            Album(id: "all-twelve", title: "All Twelve", artist: "The Chromatic Scale", symbol: "pianokeys", year: 2022),
            Album(id: "torque-and-swing", title: "Torque and Swing", artist: "Bebop Mechanics", symbol: "gearshape.2.fill", year: 2024),
            Album(id: "after-hours", title: "After Hours", artist: "Moonlit Standards", symbol: "moon.fill", year: 2023),
            Album(id: "diminished-returns", title: "Diminished Returns", artist: "The Blue Interval", symbol: "music.quarternote.3", year: 2025),
            Album(id: "mapped-out", title: "Mapped Out", artist: "Rhythm Cartography", symbol: "map.fill", year: 2024),
            Album(id: "woven", title: "Woven", artist: "Silk Thread Ensemble", symbol: "line.3.crossed.swirl.circle.fill", year: 2022),
            Album(id: "on-the-one", title: "On the One", artist: "The Downbeat", symbol: "metronome.fill", year: 2023),
            Album(id: "departure", title: "Departure", artist: "Modal Express", symbol: "airplane.departure", year: 2025),
            Album(id: "constellation", title: "Constellation", artist: "Astral Quartet", symbol: "sparkles", year: 2024),
        ]),
        Genre(id: "pop", name: "Pop", symbol: "star.fill", albums: [
            Album(id: "mirror-mirror", title: "Mirror Mirror", artist: "Crystal Gaze", symbol: "eye.fill", year: 2024),
            Album(id: "cloud-nine", title: "Cloud Nine", artist: "The Daydreamers", symbol: "cloud.fill", year: 2023),
            Album(id: "glitter-bomb", title: "Glitter Bomb", artist: "Spark & Shine", symbol: "sparkle", year: 2025),
            Album(id: "new-moon-rising", title: "New Moon Rising", artist: "Luna Nova", symbol: "moonphase.waxing.crescent", year: 2022),
            Album(id: "sugar-rush", title: "Sugar Rush", artist: "Candy Voltage", symbol: "bolt.heart.fill", year: 2024),
            Album(id: "refracted", title: "Refracted", artist: "Prism Effect", symbol: "rainbow", year: 2023),
            Album(id: "best-of-never", title: "Best of Never", artist: "The Highlights", symbol: "highlighter", year: 2025),
            Album(id: "metamorphosis", title: "Metamorphosis", artist: "Neon Butterfly", symbol: "ladybug.fill", year: 2024),
            Album(id: "reverb", title: "Reverb", artist: "The Echo Chamber", symbol: "waveform.and.magnifyingglass", year: 2022),
            Album(id: "highway-glow", title: "Highway Glow", artist: "Starlight Drive", symbol: "car.fill", year: 2023),
            Album(id: "pop-goes", title: "Pop Goes", artist: "Bubblegum Crisis", symbol: "bubble.fill", year: 2025),
            Album(id: "kaleidoscope", title: "Kaleidoscope", artist: "Chroma", symbol: "circle.hexagongrid", year: 2024),
        ]),
        Genre(id: "country", name: "Country", symbol: "leaf.fill", albums: [
            Album(id: "red-dirt-road", title: "Red Dirt Road", artist: "Dusty Horizon", symbol: "road.lanes", year: 2024),
            Album(id: "barbed-wire-ballads", title: "Barbed Wire Ballads", artist: "The Fence Post Poets", symbol: "music.note.tv.fill", year: 2023),
            Album(id: "valley-song", title: "Valley Song", artist: "Canyon Echo", symbol: "mountain.2.fill", year: 2025),
            Album(id: "barn-dance", title: "Barn Dance", artist: "Rustic Steel", symbol: "guitars.fill", year: 2022),
            Album(id: "harvest-moon", title: "Harvest Moon", artist: "The Hay Bale Prophets", symbol: "moon.haze.fill", year: 2024),
            Album(id: "trails-end", title: "Trail's End", artist: "Broken Spur", symbol: "figure.hiking", year: 2023),
            Album(id: "bloom-season", title: "Bloom Season", artist: "Wildflower Highway", symbol: "camera.macro", year: 2025),
            Album(id: "open-range", title: "Open Range", artist: "The Cattle Call", symbol: "wind", year: 2024),
            Album(id: "downstream", title: "Downstream", artist: "Timber Creek", symbol: "drop.fill", year: 2022),
            Album(id: "high-country", title: "High Country", artist: "Saddle Ridge", symbol: "sun.and.horizon.fill", year: 2023),
            Album(id: "evening-hymns", title: "Evening Hymns", artist: "The Porch Swing", symbol: "moon.stars", year: 2025),
            Album(id: "mining-songs", title: "Mining Songs", artist: "Copper Creek Band", symbol: "hammer.fill", year: 2024),
        ]),
        Genre(id: "classical", name: "Classical", symbol: "pianokeys", albums: [
            Album(id: "adagio-in-d", title: "Adagio in D", artist: "The Metropolitan Strings", symbol: "music.note", year: 2024),
            Album(id: "resonance", title: "Resonance", artist: "Chamber of Echoes", symbol: "waveform.badge.magnifyingglass", year: 2023),
            Album(id: "clockwork", title: "Clockwork", artist: "The Baroque Machine", symbol: "gearshape.fill", year: 2025),
            Album(id: "midnight-sonata", title: "Midnight Sonata", artist: "Nocturne Ensemble", symbol: "moon.zzz.fill", year: 2022),
            Album(id: "phantom-opus", title: "Phantom Opus", artist: "The Philharmonic Ghost", symbol: "theatermask.and.paintbrush.fill", year: 2024),
            Album(id: "last-movement", title: "Last Movement", artist: "Requiem for Strings", symbol: "music.note.list", year: 2023),
            Album(id: "etude-collection", title: "Etude Collection", artist: "The Ivory Tower", symbol: "pianokeys.inverse", year: 2025),
            Album(id: "new-world", title: "New World", artist: "Sinfonia Nova", symbol: "globe.americas.fill", year: 2024),
            Album(id: "fragile", title: "Fragile", artist: "The Glass Harmonica", symbol: "drop.degreesign.fill", year: 2022),
            Album(id: "grand-design", title: "Grand Design", artist: "Opus Magnum", symbol: "building.columns", year: 2023),
            Album(id: "unheard", title: "Unheard", artist: "The Silent Orchestra", symbol: "speaker.slash.fill", year: 2025),
            Album(id: "first-light", title: "First Light", artist: "Prelude Collective", symbol: "sunrise.fill", year: 2024),
        ]),
        Genre(id: "rnb", name: "R&B", symbol: "headphones", albums: [
            Album(id: "golden-hour", title: "Golden Hour", artist: "Silk Horizon", symbol: "sun.max.fill", year: 2024),
            Album(id: "velvet-touch", title: "Velvet Touch", artist: "The Smooth Operators", symbol: "hand.raised.fingers.spread.fill", year: 2023),
            Album(id: "slow-drip", title: "Slow Drip", artist: "Midnight Honey", symbol: "drop.fill", year: 2025),
            Album(id: "undertow", title: "Undertow", artist: "The Currents", symbol: "water.waves", year: 2022),
            Album(id: "threadcount", title: "Threadcount", artist: "Satin Groove", symbol: "waveform.path.ecg.rectangle.fill", year: 2024),
            Album(id: "heat-shimmer", title: "Heat Shimmer", artist: "Amber Waves", symbol: "flame.fill", year: 2023),
            Album(id: "underground", title: "Underground", artist: "The Basement Tapes", symbol: "arrow.down.circle.fill", year: 2025),
            Album(id: "body-language", title: "Body Language", artist: "Warm Frequency", symbol: "person.fill", year: 2024),
            Album(id: "distilled", title: "Distilled", artist: "The Essence", symbol: "testtube.2", year: 2022),
            Album(id: "soft", title: "Soft", artist: "Cocoa Butter", symbol: "heart.fill", year: 2023),
            Album(id: "late-edition", title: "Late Edition", artist: "Evening Standard", symbol: "newspaper.fill", year: 2025),
            Album(id: "verified", title: "Verified", artist: "The Vibe Check", symbol: "checkmark.seal.fill", year: 2024),
        ]),
    ]
}

#Preview {
    NavigationStack {
        AlbumFlowView()
    }
}
