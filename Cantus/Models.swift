import Foundation

enum PlaylistSource: String, Codable {
    case appleMusic
    case local

    var label: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .local: return "Local"
        }
    }

    var systemImage: String {
        switch self {
        case .appleMusic: return "music.note.list"
        case .local: return "externaldrive"
        }
    }
}

struct PlaylistCategory: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
}

struct LoopItem: Identifiable {
    let id = UUID()
    let title: String
    let isBookmarked: Bool
}

struct SFXItem: Identifiable {
    let id = UUID()
    let title: String
    let isBookmarked: Bool
}

@MainActor
final class BookmarksStore: ObservableObject {
    private let loopKey = "bookmarkedLoops"
    private let sfxKey = "bookmarkedSFX"
    private let playlistKey = "bookmarkedPlaylists"
    private let defaults = UserDefaults.standard
    private var isApplyingRemoteState = false

    @Published private(set) var loopBookmarks: Set<String> = []
    @Published private(set) var sfxBookmarks: Set<String> = []
    @Published private(set) var playlistBookmarks: Set<String> = []
    @Published private(set) var loopBookmarkOrder: [String] = []
    @Published private(set) var sfxBookmarkOrder: [String] = []
    @Published private(set) var playlistBookmarkOrder: [String] = []

    init() {
        loopBookmarkOrder = defaults.array(forKey: loopKey) as? [String] ?? []
        sfxBookmarkOrder = defaults.array(forKey: sfxKey) as? [String] ?? []
        playlistBookmarkOrder = defaults.array(forKey: playlistKey) as? [String] ?? []
        loopBookmarks = Set(loopBookmarkOrder)
        sfxBookmarks = Set(sfxBookmarkOrder)
        playlistBookmarks = Set(playlistBookmarkOrder)
    }

    func isLoopBookmarked(_ title: String) -> Bool {
        loopBookmarks.contains(title)
    }

    func isSFXBookmarked(_ title: String) -> Bool {
        sfxBookmarks.contains(title)
    }

    func isPlaylistBookmarked(_ title: String) -> Bool {
        playlistBookmarks.contains(title)
    }

    func toggleLoop(_ title: String) {
        if loopBookmarks.contains(title) {
            loopBookmarks.remove(title)
            loopBookmarkOrder.removeAll { $0 == title }
        } else {
            loopBookmarks.insert(title)
            if !loopBookmarkOrder.contains(title) {
                loopBookmarkOrder.append(title)
            }
        }
        defaults.set(loopBookmarkOrder, forKey: loopKey)
        markUserStateDirty()
    }

    func renameLoop(from oldTitle: String, to newTitle: String) {
        guard oldTitle != newTitle else { return }
        let wasBookmarked = loopBookmarks.contains(oldTitle)
        loopBookmarks.remove(oldTitle)
        loopBookmarkOrder.removeAll { $0 == oldTitle }
        if wasBookmarked {
            loopBookmarks.insert(newTitle)
            if !loopBookmarkOrder.contains(newTitle) {
                loopBookmarkOrder.append(newTitle)
            }
        }
        defaults.set(loopBookmarkOrder, forKey: loopKey)
        markUserStateDirty()
    }

    func renameSFX(from oldTitle: String, to newTitle: String) {
        guard oldTitle != newTitle else { return }
        let wasBookmarked = sfxBookmarks.contains(oldTitle)
        sfxBookmarks.remove(oldTitle)
        sfxBookmarkOrder.removeAll { $0 == oldTitle }
        if wasBookmarked {
            sfxBookmarks.insert(newTitle)
            if !sfxBookmarkOrder.contains(newTitle) {
                sfxBookmarkOrder.append(newTitle)
            }
        }
        defaults.set(sfxBookmarkOrder, forKey: sfxKey)
        markUserStateDirty()
    }

    func removeLoopBookmark(_ title: String) {
        guard loopBookmarks.contains(title) else { return }
        loopBookmarks.remove(title)
        loopBookmarkOrder.removeAll { $0 == title }
        defaults.set(loopBookmarkOrder, forKey: loopKey)
        markUserStateDirty()
    }

    func removeSFXBookmark(_ title: String) {
        guard sfxBookmarks.contains(title) else { return }
        sfxBookmarks.remove(title)
        sfxBookmarkOrder.removeAll { $0 == title }
        defaults.set(sfxBookmarkOrder, forKey: sfxKey)
        markUserStateDirty()
    }

    func toggleSFX(_ title: String) {
        if sfxBookmarks.contains(title) {
            sfxBookmarks.remove(title)
            sfxBookmarkOrder.removeAll { $0 == title }
        } else {
            sfxBookmarks.insert(title)
            if !sfxBookmarkOrder.contains(title) {
                sfxBookmarkOrder.append(title)
            }
        }
        defaults.set(sfxBookmarkOrder, forKey: sfxKey)
        markUserStateDirty()
    }

    func togglePlaylist(_ title: String) {
        if playlistBookmarks.contains(title) {
            playlistBookmarks.remove(title)
            playlistBookmarkOrder.removeAll { $0 == title }
        } else {
            playlistBookmarks.insert(title)
            if !playlistBookmarkOrder.contains(title) {
                playlistBookmarkOrder.append(title)
            }
        }
        defaults.set(playlistBookmarkOrder, forKey: playlistKey)
        markUserStateDirty()
    }

    func setInitialBookmarks(
        playlists: [String],
        atmospheres: [String],
        soundEffects: [String]
    ) {
        playlistBookmarkOrder = uniquePreservingOrder(playlists)
        loopBookmarkOrder = uniquePreservingOrder(atmospheres)
        sfxBookmarkOrder = uniquePreservingOrder(soundEffects)

        playlistBookmarks = Set(playlistBookmarkOrder)
        loopBookmarks = Set(loopBookmarkOrder)
        sfxBookmarks = Set(sfxBookmarkOrder)

        defaults.set(playlistBookmarkOrder, forKey: playlistKey)
        defaults.set(loopBookmarkOrder, forKey: loopKey)
        defaults.set(sfxBookmarkOrder, forKey: sfxKey)
        markUserStateDirty()
    }

    var loopBookmarkList: [String] {
        loopBookmarkOrder
    }

    var sfxBookmarkList: [String] {
        sfxBookmarkOrder
    }

    var playlistBookmarkList: [String] {
        playlistBookmarkOrder
    }

    func moveLoopBookmark(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              loopBookmarkOrder.indices.contains(sourceIndex) else {
            return
        }
        let item = loopBookmarkOrder.remove(at: sourceIndex)
        let targetIndex = min(max(0, destinationIndex), loopBookmarkOrder.count)
        loopBookmarkOrder.insert(item, at: targetIndex)
        defaults.set(loopBookmarkOrder, forKey: loopKey)
        markUserStateDirty()
    }

    func moveLoopBookmarks(fromOffsets offsets: IndexSet, toOffset destinationIndex: Int) {
        loopBookmarkOrder.move(fromOffsets: offsets, toOffset: destinationIndex)
        defaults.set(loopBookmarkOrder, forKey: loopKey)
        markUserStateDirty()
    }

    func moveSFXBookmarks(fromOffsets offsets: IndexSet, toOffset destinationIndex: Int) {
        sfxBookmarkOrder.move(fromOffsets: offsets, toOffset: destinationIndex)
        defaults.set(sfxBookmarkOrder, forKey: sfxKey)
        markUserStateDirty()
    }

    func movePlaylistBookmarks(fromOffsets offsets: IndexSet, toOffset destinationIndex: Int) {
        playlistBookmarkOrder.move(fromOffsets: offsets, toOffset: destinationIndex)
        defaults.set(playlistBookmarkOrder, forKey: playlistKey)
        markUserStateDirty()
    }

    func removePlaylistBookmark(_ title: String) {
        guard playlistBookmarks.contains(title) else { return }
        playlistBookmarks.remove(title)
        playlistBookmarkOrder.removeAll { $0 == title }
        defaults.set(playlistBookmarkOrder, forKey: playlistKey)
        markUserStateDirty()
    }

    func renamePlaylist(from oldTitle: String, to newTitle: String) {
        guard oldTitle != newTitle else { return }
        let wasBookmarked = playlistBookmarks.contains(oldTitle)
        playlistBookmarks.remove(oldTitle)
        playlistBookmarkOrder.removeAll { $0 == oldTitle }
        if wasBookmarked {
            playlistBookmarks.insert(newTitle)
            if !playlistBookmarkOrder.contains(newTitle) {
                playlistBookmarkOrder.append(newTitle)
            }
        }
        defaults.set(playlistBookmarkOrder, forKey: playlistKey)
        markUserStateDirty()
    }

    func applyExport(loopBookmarks: [String], sfxBookmarks: [String]) {
        isApplyingRemoteState = true
        loopBookmarkOrder = loopBookmarks
        sfxBookmarkOrder = sfxBookmarks
        self.loopBookmarks = Set(loopBookmarkOrder)
        self.sfxBookmarks = Set(sfxBookmarkOrder)
        defaults.set(loopBookmarkOrder, forKey: loopKey)
        defaults.set(sfxBookmarkOrder, forKey: sfxKey)
        isApplyingRemoteState = false
    }

    private func markUserStateDirty() {
        guard !isApplyingRemoteState else { return }
    }

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for value in values {
            guard !seen.contains(value) else { continue }
            seen.insert(value)
            output.append(value)
        }
        return output
    }
}

@MainActor
final class PlaybackStateStore: ObservableObject {
    private let recentLoopsKey = "recentLoopHistory"
    private let recentSFXKey = "recentSFXHistory"
    private let recentPlaylistsKey = "recentPlaylistHistory"
    private let lastPlayedLoopsKey = "lastPlayedLoops"
    private let lastPlayedSFXKey = "lastPlayedSFX"
    private let lastPlayedPlaylistsKey = "lastPlayedPlaylists"
    private let masterVolumeKey = "masterVolume"
    private let musicVolumeKey = "musicVolume"
    private let atmosphereVolumeKey = "atmosphereVolume"
    private let sfxVolumeKey = "sfxVolume"
    private let sfxDuckingEnabledKey = "sfxDuckingEnabled"
    private let defaults = UserDefaults.standard
    private var isApplyingRemoteState = false

    @Published private(set) var playingLoops: Set<String> = []
    @Published private(set) var playingSFX: Set<String> = []
    @Published private(set) var recentLoops: [String] = []
    @Published private(set) var recentSFX: [String] = []
    @Published private(set) var recentPlaylists: [String] = []
    @Published private(set) var lastPlayedLoops: [String: Date] = [:]
    @Published private(set) var lastPlayedSFX: [String: Date] = [:]
    @Published private(set) var lastPlayedPlaylists: [String: Date] = [:]
    @Published var musicVolume: Double {
        didSet {
            defaults.set(musicVolume, forKey: musicVolumeKey)
        }
    }
    @Published var masterVolume: Double {
        didSet {
            defaults.set(masterVolume, forKey: masterVolumeKey)
        }
    }
    @Published var atmosphereVolume: Double {
        didSet {
            defaults.set(atmosphereVolume, forKey: atmosphereVolumeKey)
        }
    }
    @Published var sfxVolume: Double {
        didSet {
            defaults.set(sfxVolume, forKey: sfxVolumeKey)
        }
    }
    @Published var sfxDuckingEnabled: Bool {
        didSet {
            defaults.set(sfxDuckingEnabled, forKey: sfxDuckingEnabledKey)
        }
    }

    init() {
        isApplyingRemoteState = true
        masterVolume = 0.9
        musicVolume = 0.72
        atmosphereVolume = 0.56
        sfxVolume = 0.48
        sfxDuckingEnabled = true
        recentLoops = defaults.array(forKey: recentLoopsKey) as? [String] ?? []
        recentSFX = defaults.array(forKey: recentSFXKey) as? [String] ?? []
        recentPlaylists = defaults.array(forKey: recentPlaylistsKey) as? [String] ?? []
        lastPlayedLoops = loadLastPlayed(forKey: lastPlayedLoopsKey)
        lastPlayedSFX = loadLastPlayed(forKey: lastPlayedSFXKey)
        lastPlayedPlaylists = loadLastPlayed(forKey: lastPlayedPlaylistsKey)
        masterVolume = loadVolume(forKey: masterVolumeKey, defaultValue: 0.9)
        musicVolume = loadVolume(forKey: musicVolumeKey, defaultValue: 0.72)
        atmosphereVolume = loadVolume(forKey: atmosphereVolumeKey, defaultValue: 0.56)
        sfxVolume = loadVolume(forKey: sfxVolumeKey, defaultValue: 0.48)
        sfxDuckingEnabled = defaults.object(forKey: sfxDuckingEnabledKey) as? Bool ?? true
        NotificationCenter.default.addObserver(
            forName: AudioPlaybackManager.sfxDidFinishNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let title = notification.object as? String else { return }
            Task { @MainActor in
                self?.playingSFX.remove(title)
            }
        }
        NotificationCenter.default.addObserver(
            forName: MusicPlaybackStore.playlistDidStartNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let title = notification.object as? String else { return }
            Task { @MainActor in
                self?.addRecentPlaylist(title)
            }
        }
        isApplyingRemoteState = false
    }

    func isLoopPlaying(_ title: String) -> Bool {
        playingLoops.contains(title)
    }

    func isSFXPlaying(_ title: String) -> Bool {
        playingSFX.contains(title)
    }

    func toggleLoop(_ title: String) {
        if playingLoops.contains(title) {
            playingLoops.remove(title)
        } else {
            playingLoops.insert(title)
            updateRecentLoops(with: title)
            recordLoopPlayed(title)
        }
    }

    func toggleSFX(_ title: String) {
        if playingSFX.contains(title) {
            playingSFX.remove(title)
        } else {
            playingSFX.insert(title)
            updateRecentSFX(with: title)
            recordSFXPlayed(title)
        }
    }

    func stopAllLoops() {
        playingLoops.removeAll()
    }

    func stopAllSFX() {
        playingSFX.removeAll()
    }

    private func updateRecentLoops(with title: String) {
        recentLoops.removeAll { $0 == title }
        recentLoops.insert(title, at: 0)
        if recentLoops.count > 20 {
            recentLoops = Array(recentLoops.prefix(20))
        }
        defaults.set(recentLoops, forKey: recentLoopsKey)
        markUserStateDirty()
    }

    func addRecentLoop(_ title: String) {
        updateRecentLoops(with: title)
        recordLoopPlayed(title)
    }

    func renameLoop(from oldTitle: String, to newTitle: String) {
        guard oldTitle != newTitle else { return }
        if playingLoops.remove(oldTitle) != nil {
            playingLoops.insert(newTitle)
        }
        if let index = recentLoops.firstIndex(of: oldTitle) {
            recentLoops.removeAll { $0 == newTitle || $0 == oldTitle }
            recentLoops.insert(newTitle, at: min(index, recentLoops.count))
            defaults.set(recentLoops, forKey: recentLoopsKey)
        }
        if let date = lastPlayedLoops.removeValue(forKey: oldTitle) {
            lastPlayedLoops[newTitle] = date
            storeLastPlayed(lastPlayedLoops, key: lastPlayedLoopsKey)
        }
        markUserStateDirty()
    }

    func removeRecentLoop(_ title: String) {
        recentLoops.removeAll { $0 == title }
        defaults.set(recentLoops, forKey: recentLoopsKey)
        markUserStateDirty()
    }

    private func updateRecentSFX(with title: String) {
        recentSFX.removeAll { $0 == title }
        recentSFX.insert(title, at: 0)
        if recentSFX.count > 20 {
            recentSFX = Array(recentSFX.prefix(20))
        }
        defaults.set(recentSFX, forKey: recentSFXKey)
        markUserStateDirty()
    }

    private func updateRecentPlaylists(with title: String) {
        recentPlaylists.removeAll { $0 == title }
        recentPlaylists.insert(title, at: 0)
        if recentPlaylists.count > 20 {
            recentPlaylists = Array(recentPlaylists.prefix(20))
        }
        defaults.set(recentPlaylists, forKey: recentPlaylistsKey)
        markUserStateDirty()
    }

    func addRecentSFX(_ title: String) {
        updateRecentSFX(with: title)
        recordSFXPlayed(title)
    }

    func addRecentPlaylist(_ title: String) {
        updateRecentPlaylists(with: title)
        recordPlaylistPlayed(title)
    }

    func renameSFX(from oldTitle: String, to newTitle: String) {
        guard oldTitle != newTitle else { return }
        if playingSFX.remove(oldTitle) != nil {
            playingSFX.insert(newTitle)
        }
        if let index = recentSFX.firstIndex(of: oldTitle) {
            recentSFX.removeAll { $0 == newTitle || $0 == oldTitle }
            recentSFX.insert(newTitle, at: min(index, recentSFX.count))
            defaults.set(recentSFX, forKey: recentSFXKey)
        }
        if let date = lastPlayedSFX.removeValue(forKey: oldTitle) {
            lastPlayedSFX[newTitle] = date
            storeLastPlayed(lastPlayedSFX, key: lastPlayedSFXKey)
        }
        markUserStateDirty()
    }

    func removeLoopState(_ title: String) {
        playingLoops.remove(title)
        recentLoops.removeAll { $0 == title }
        defaults.set(recentLoops, forKey: recentLoopsKey)
        if lastPlayedLoops.removeValue(forKey: title) != nil {
            storeLastPlayed(lastPlayedLoops, key: lastPlayedLoopsKey)
        }
        markUserStateDirty()
    }

    func removeSFXState(_ title: String) {
        playingSFX.remove(title)
        recentSFX.removeAll { $0 == title }
        defaults.set(recentSFX, forKey: recentSFXKey)
        if lastPlayedSFX.removeValue(forKey: title) != nil {
            storeLastPlayed(lastPlayedSFX, key: lastPlayedSFXKey)
        }
        markUserStateDirty()
    }

    func removeRecentSFX(_ title: String) {
        recentSFX.removeAll { $0 == title }
        defaults.set(recentSFX, forKey: recentSFXKey)
        markUserStateDirty()
    }

    func removeRecentPlaylist(_ title: String) {
        recentPlaylists.removeAll { $0 == title }
        defaults.set(recentPlaylists, forKey: recentPlaylistsKey)
        if lastPlayedPlaylists.removeValue(forKey: title) != nil {
            storeLastPlayed(lastPlayedPlaylists, key: lastPlayedPlaylistsKey)
        }
        markUserStateDirty()
    }

    private func loadVolume(forKey key: String, defaultValue: Double) -> Double {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.double(forKey: key)
    }

    private func loadLastPlayed(forKey key: String) -> [String: Date] {
        guard let stored = defaults.dictionary(forKey: key) as? [String: Double] else {
            return [:]
        }
        return stored.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private func recordLoopPlayed(_ title: String) {
        lastPlayedLoops[title] = Date()
        storeLastPlayed(lastPlayedLoops, key: lastPlayedLoopsKey)
        markUserStateDirty()
    }

    private func recordSFXPlayed(_ title: String) {
        lastPlayedSFX[title] = Date()
        storeLastPlayed(lastPlayedSFX, key: lastPlayedSFXKey)
        markUserStateDirty()
    }

    private func recordPlaylistPlayed(_ title: String) {
        lastPlayedPlaylists[title] = Date()
        storeLastPlayed(lastPlayedPlaylists, key: lastPlayedPlaylistsKey)
        markUserStateDirty()
    }

    func markPlaylistPlayed(_ title: String) {
        recordPlaylistPlayed(title)
    }

    private func storeLastPlayed(_ map: [String: Date], key: String) {
        let stored = map.mapValues { $0.timeIntervalSince1970 }
        defaults.set(stored, forKey: key)
    }

    func lastPlayedLoop(_ title: String) -> Date? {
        lastPlayedLoops[title]
    }

    func lastPlayedSFX(_ title: String) -> Date? {
        lastPlayedSFX[title]
    }

    func lastPlayedPlaylist(_ title: String) -> Date? {
        lastPlayedPlaylists[title]
    }

    func renamePlaylist(from oldTitle: String, to newTitle: String) {
        guard oldTitle != newTitle else { return }
        if let index = recentPlaylists.firstIndex(of: oldTitle) {
            recentPlaylists.removeAll { $0 == newTitle || $0 == oldTitle }
            recentPlaylists.insert(newTitle, at: min(index, recentPlaylists.count))
            defaults.set(recentPlaylists, forKey: recentPlaylistsKey)
        }
        if let date = lastPlayedPlaylists.removeValue(forKey: oldTitle) {
            lastPlayedPlaylists[newTitle] = date
            storeLastPlayed(lastPlayedPlaylists, key: lastPlayedPlaylistsKey)
        }
        markUserStateDirty()
    }

    func applyExportPreferences(master: Double, music: Double, atmosphere: Double, sfx: Double) {
        isApplyingRemoteState = true
        masterVolume = master
        musicVolume = music
        atmosphereVolume = atmosphere
        sfxVolume = sfx
        defaults.set(masterVolume, forKey: masterVolumeKey)
        defaults.set(musicVolume, forKey: musicVolumeKey)
        defaults.set(atmosphereVolume, forKey: atmosphereVolumeKey)
        defaults.set(sfxVolume, forKey: sfxVolumeKey)
        isApplyingRemoteState = false
    }

    private func markUserStateDirty() {
        guard !isApplyingRemoteState else { return }
    }
}

struct DemoData {
    static let playlistThemes = [
        PlaylistCategory(title: "Combat", icon: "sword"),
        PlaylistCategory(title: "Crafting", icon: "hammer"),
        PlaylistCategory(title: "Dwarves", icon: "helmet"),
        PlaylistCategory(title: "Elves", icon: "leaf"),
        PlaylistCategory(title: "Exploration", icon: "map"),
        PlaylistCategory(title: "Investigation", icon: "magnifyingglass"),
        PlaylistCategory(title: "Magic", icon: "wand.and.stars"),
        PlaylistCategory(title: "Merchants", icon: "cart"),
        PlaylistCategory(title: "Mystery", icon: "questionmark.circle"),
        PlaylistCategory(title: "Noble Court", icon: "crown"),
        PlaylistCategory(title: "Pirates", icon: "skull"),
        PlaylistCategory(title: "Stealth", icon: "eye.slash"),
        PlaylistCategory(title: "Travel", icon: "figure.walk"),
        PlaylistCategory(title: "Undead", icon: "bolt.heart"),
    ]

    static let atmosphereLoops = [
        LoopItem(title: "Bat Swarm", isBookmarked: false),
        LoopItem(title: "Cave Echoes", isBookmarked: false),
        LoopItem(title: "Chittering Skitter", isBookmarked: true),
        LoopItem(title: "Crystal Hum", isBookmarked: true),
        LoopItem(title: "Deepwater Drips", isBookmarked: true),
        LoopItem(title: "Distant Drums", isBookmarked: true),
        LoopItem(title: "Dungeon Drips", isBookmarked: true),
        LoopItem(title: "Fungal Spores", isBookmarked: true),
        LoopItem(title: "Howling Winds", isBookmarked: false),
        LoopItem(title: "Mindwhisper", isBookmarked: false),
        LoopItem(title: "Stone Groans", isBookmarked: false),
    ]

    static let soundboardSFX = [
        SFXItem(title: "Breath - Fire", isBookmarked: true),
        SFXItem(title: "Claw Swipe", isBookmarked: false),
        SFXItem(title: "Dragon Roar", isBookmarked: true),
        SFXItem(title: "Flight Wingbeats", isBookmarked: false),
        SFXItem(title: "Fireball Impact", isBookmarked: true),
        SFXItem(title: "Growl", isBookmarked: false),
        SFXItem(title: "Scales Rustling", isBookmarked: true),
        SFXItem(title: "Snarl", isBookmarked: false),
        SFXItem(title: "Tail Smash", isBookmarked: true),
        SFXItem(title: "Wings Flap", isBookmarked: true),
    ]

    static let playAtmospheres = [
        "Dungeon Drips",
        "Eerie Winds",
        "Crackling Fire",
        "Cave Echoes",
        "Chilling Mist",
        "Ancient Citadel",
    ]

    static let playSFX = [
        "Sword Clash",
        "Door Creak",
        "Magic Spell",
        "Arrow Shot",
        "Thunder",
        "Growl",
    ]
}
