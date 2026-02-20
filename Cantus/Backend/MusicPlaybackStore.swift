import Foundation
import MusicKit
import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class PlaybackProgressModel: ObservableObject {
    struct Snapshot: Equatable {
        var time: TimeInterval
        var duration: TimeInterval
        var isPlaying: Bool
        var updatedAt: Date
    }

    @Published private(set) var snapshot = Snapshot(
        time: 0,
        duration: 0,
        isPlaying: false,
        updatedAt: .distantPast
    )

    func update(
        time: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool,
        at date: Date,
        force: Bool = false
    ) {
        let clampedDuration = max(0, duration)
        let upperBound = clampedDuration > 0 ? clampedDuration : max(0, time)
        let clampedTime = min(max(0, time), upperBound)
        var adjustedTime = clampedTime

        // Small drift is blended instead of snapped so progress stays visually smooth.
        if !force,
           snapshot.isPlaying,
           isPlaying,
           snapshot.updatedAt != .distantPast {
            let elapsed = max(0, date.timeIntervalSince(snapshot.updatedAt))
            let projectedDuration = max(snapshot.duration, clampedDuration)
            let projected = projectedDuration > 0
                ? min(projectedDuration, snapshot.time + elapsed)
                : snapshot.time + elapsed
            let drift = adjustedTime - projected
            if abs(drift) < 0.35 {
                adjustedTime = projected + (drift * 0.25)
            }
        }

        let next = Snapshot(
            time: adjustedTime,
            duration: clampedDuration,
            isPlaying: isPlaying,
            updatedAt: date
        )
        if next != snapshot {
            snapshot = next
        }
    }
}

enum PlaylistPlaybackMode: String, CaseIterable, Codable {
    case shuffle
    case repeatAll
    case repeatOne

    var iconName: String {
        switch self {
        case .shuffle:
            return "shuffle"
        case .repeatAll:
            return "repeat"
        case .repeatOne:
            return "repeat.1"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .shuffle:
            return "Shuffle Playlist"
        case .repeatAll:
            return "Repeat All Songs in Current Playlist"
        case .repeatOne:
            return "Repeat the Currently Playing Song"
        }
    }
}

@MainActor
final class MusicPlaybackStore: ObservableObject {
    static let playlistDidStartNotification = Notification.Name("Cantus.PlaylistDidStart")

    @Published private(set) var isPlaying = false {
        didSet {
            updateTimerIfNeeded()
            publishPlaybackProgress(force: true)
        }
    }
    @Published private(set) var title: String = "Not Playing"
    @Published private(set) var artist: String = ""
    @Published private(set) var playlistTitle: String = "Now Playing"
    @Published private(set) var duration: TimeInterval = 0 {
        didSet {
            publishPlaybackProgress(force: true)
        }
    }
    private(set) var playbackTime: TimeInterval = 0
    @Published private(set) var artworkImage: Image? = nil
    @Published private(set) var statusMessage: String? = nil
    @Published private(set) var currentPlaylistItemId: String? = nil
    @Published private(set) var isStartingPlayback: Bool = false
    @Published private(set) var playlistPlaybackMode: PlaylistPlaybackMode
    let playbackProgress = PlaybackProgressModel()

    private let player = ApplicationMusicPlayer.shared
    private let localCrossfadeDuration: TimeInterval = 6
    private let userStopFadeDuration: TimeInterval = 0.5
    private let activeTimerInterval: TimeInterval = 1.0 / 12.0
    private let scrubbingTimerInterval: TimeInterval = 1.0 / 20.0
    private let crossfadeTimerInterval: TimeInterval = 1.0 / 20.0
    private let idleTimerInterval: TimeInterval = 0.6
    private let stateRefreshInterval: TimeInterval = 1.0
    private let progressPublishInterval: TimeInterval = 0.2
    private var localMusicVolume: Float = 1.0
    private var masterVolume: Float = 1.0
    private var localMusicDuckingMultiplier: Float = 1.0
    private let sfxDuckingFactor: Float = 0.55
    private let localDuckingRampDuration: TimeInterval = 0.24
    private let localDuckingRampStepCount: Int = 12
    private var localDuckingRampTask: Task<Void, Never>?
    private var localPlayers: [AVAudioPlayer?] = [nil, nil]
    private var activeLocalPlayerIndex = 0
    private var localCurrentTrackIndex = 0
    private var localIsCrossfading = false
    private var localCrossfadeStart: Date?
    private var localNextTrackIndex: Int?
    private var lastLocalMetadataIndex: Int?
    private var localIsAdvancing = false
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0.5
    private var lastSyncDate: Date = .distantPast
    private var lastPlayerTime: TimeInterval = 0
    private var lastPlayerTimeDate: Date = .distantPast
    private var lastProgressPublishDate: Date = .distantPast
    private var isStateRefreshInFlight = false
    private var isScrubbing = false
    private var playlistCache: [String: Playlist] = [:]
    private var playlistEntriesCache: [String: MusicItemCollection<Playlist.Entry>] = [:]
    private var playlistSongCache: [String: [Song]] = [:]
    private var pendingPlaylistSelection: (id: String, title: String)?
    private var currentSource: PlaylistSource?
    private var localTracks: [LocalPlaylistTrack] = []
    private let localPauseFadeStepCount: Int = 20
    private var localPauseFadeTask: Task<Void, Never>?
    private var localPauseFadeGeneration: UInt64 = 0
    private var localArtworkCache: [String: Image] = [:]
    private var remoteArtworkCache: [URL: Image] = [:]
    private var lastArtworkKey: ArtworkKey?
    private var isRestartingAppleMusic = false
    private var supportsAppleMusicPlayback: Bool { true }
    private let playlistPlaybackModeKey = "cantus.playbackMode.v1"
    var isPlayingAppleMusic: Bool { isPlaying && currentSource == .appleMusic }

    init() {
        playlistPlaybackMode = PlaylistPlaybackMode(rawValue: UserDefaults.standard.string(forKey: playlistPlaybackModeKey) ?? "") ?? .repeatAll
        configureTransition()
        applyPlaylistPlaybackModeToAppleMusicPlayer()
        scheduleTimer(interval: timerInterval)
        publishPlaybackProgress(force: true)
    }

    deinit {
        timer?.invalidate()
        localDuckingRampTask?.cancel()
        localPauseFadeTask?.cancel()
    }

    private func configureTransition() {
#if os(iOS)
        if #available(iOS 18.0, *) {
            player.transition = .crossfade(duration: 6)
        }
#endif
    }

    private var effectiveLocalMusicVolume: Float {
        localMusicVolume * localMusicDuckingMultiplier * masterVolume
    }

    func setMusicVolume(_ volume: Double) {
        let clamped = Float(min(max(volume, 0), 1))
        localMusicVolume = clamped
        applyEffectiveLocalMusicVolume()
    }

    func setMasterVolume(_ volume: Double) {
        let clamped = Float(min(max(volume, 0), 1))
        masterVolume = clamped
        applyEffectiveLocalMusicVolume()
    }

    func setSFXDuckingActive(_ isActive: Bool) {
        setLocalMusicDuckingMultiplier(isActive ? sfxDuckingFactor : 1.0, animated: true)
    }

    func cyclePlaylistPlaybackMode() {
        let allModes = PlaylistPlaybackMode.allCases
        guard let currentIndex = allModes.firstIndex(of: playlistPlaybackMode) else {
            setPlaylistPlaybackMode(.shuffle)
            return
        }
        let nextIndex = (currentIndex + 1) % allModes.count
        setPlaylistPlaybackMode(allModes[nextIndex])
    }

    private func setPlaylistPlaybackMode(_ mode: PlaylistPlaybackMode) {
        guard playlistPlaybackMode != mode else { return }
        playlistPlaybackMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: playlistPlaybackModeKey)
        applyPlaylistPlaybackModeToAppleMusicPlayer()
    }

    private func applyPlaylistPlaybackModeToAppleMusicPlayer() {
        switch playlistPlaybackMode {
        case .shuffle:
            player.state.shuffleMode = .songs
            player.state.repeatMode = MusicPlayer.RepeatMode.none
        case .repeatAll:
            player.state.shuffleMode = .off
            player.state.repeatMode = .all
        case .repeatOne:
            player.state.shuffleMode = .off
            player.state.repeatMode = .one
        }
    }

    private func applyEffectiveLocalMusicVolume() {
        if localIsCrossfading,
           let active = activeLocalPlayer(),
           let inactive = inactiveLocalPlayer() {
            let total = max(active.volume + inactive.volume, 0.0001)
            let activeRatio = active.volume / total
            active.volume = activeRatio * effectiveLocalMusicVolume
            inactive.volume = (1 - activeRatio) * effectiveLocalMusicVolume
        } else {
            activeLocalPlayer()?.volume = effectiveLocalMusicVolume
        }
    }

    private func setLocalMusicDuckingMultiplier(_ multiplier: Float, animated: Bool) {
        let clamped = max(0, min(1, multiplier))
        guard animated else {
            localDuckingRampTask?.cancel()
            localDuckingRampTask = nil
            localMusicDuckingMultiplier = clamped
            applyEffectiveLocalMusicVolume()
            return
        }

        let start = localMusicDuckingMultiplier
        guard abs(start - clamped) > 0.0005 else {
            localDuckingRampTask?.cancel()
            localDuckingRampTask = nil
            localMusicDuckingMultiplier = clamped
            applyEffectiveLocalMusicVolume()
            return
        }

        localDuckingRampTask?.cancel()
        let steps = max(1, localDuckingRampStepCount)
        let stepDuration = max(localDuckingRampDuration / Double(steps), 0.01)
        localDuckingRampTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for step in 1...steps {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
                if Task.isCancelled { return }
                let progress = Float(step) / Float(steps)
                self.localMusicDuckingMultiplier = start + (clamped - start) * progress
                self.applyEffectiveLocalMusicVolume()
            }
            self.localDuckingRampTask = nil
        }
    }

    func refresh() async {
        if !supportsAppleMusicPlayback {
            return
        }
        if currentSource == .local {
            await refreshLocal()
            return
        }
        guard currentSource == .appleMusic else {
            return
        }
        if !PremiumStore.shared.isPremium {
            setStatus(title: "Premium Required", message: "Upgrade to Premium to play Apple Music playlists.")
            return
        }
        if MusicAuthorization.currentStatus != .authorized {
            setStatus(title: "Apple Music Access Needed", message: "Enable access in Settings to play music.")
            return
        }
        let state = player.state
        isPlaying = state.playbackStatus == .playing
        let now = Date()
        if !isScrubbing {
            setPlaybackTime(
                player.playbackTime,
                at: now,
                anchorsPlayerTime: true,
                forceProgressPublish: true
            )
        }
        lastSyncDate = now

        if let entry = player.queue.currentEntry {
            title = entry.title
            artist = entry.subtitle ?? ""
            duration = resolveDuration(for: entry)
            await updateArtworkIfNeeded(for: entry)
            statusMessage = nil
            if currentPlaylistItemId == nil, let item = entry.item {
                if case .song(let song) = item {
                    currentPlaylistItemId = song.id.rawValue
                }
            }
        } else {
            title = "Not Playing"
            artist = ""
            duration = 0
            setPlaybackTime(
                0,
                at: now,
                anchorsPlayerTime: true,
                forceProgressPublish: true
            )
            artworkImage = nil
            lastArtworkKey = nil
            if currentPlaylistItemId == nil {
                playlistTitle = "Now Playing"
            }
            statusMessage = nil
        }
        await maybeLoopAppleMusicIfNeeded()
    }

    func prefetchPlaylists(playlistIds: [String]) async {
        guard supportsAppleMusicPlayback else { return }
        guard PremiumStore.shared.isPremium else { return }
        guard MusicAuthorization.currentStatus == .authorized else { return }
        for playlistId in playlistIds {
            _ = try? await loadPlaylistEntries(playlistId: playlistId)
        }
    }

    func togglePlayPause() async {
        if !supportsAppleMusicPlayback, currentSource != .local {
            return
        }
        if currentSource == .local {
            if isLocalPlaying() {
                isPlaying = false
                await pauseLocalPlayersWithFade(duration: userStopFadeDuration)
            } else {
                playLocalPlayers()
                isPlaying = true
            }
            await refreshLocal()
            return
        }
        configureTransition()
        guard await ensurePlayable() else { return }
        let wasPlaying = player.state.playbackStatus == .playing
        if wasPlaying {
            isPlaying = false
            player.pause()
            return
        } else {
            if !PremiumStore.shared.isPremium {
                setStatus(title: "Premium Required", message: "Upgrade to Premium to play Apple Music playlists.")
                return
            }
            isPlaying = true
            if player.queue.currentEntry == nil {
                let loaded = await ensureQueueLoaded()
                if !loaded {
                    isPlaying = false
                    setStatus(title: "No Playlists", message: "Add an Apple Music playlist to your library.")
                    return
                }
            }
            currentSource = .appleMusic
            do {
                try await player.play()
            } catch {
                await handlePlaybackAuthFailure()
                isPlaying = false
                setStatus(title: "Playback Error", message: "Unable to start Apple Music playback.")
                return
            }
        }
        await refresh()
        notifyPlaylistStartedIfAvailable()
    }

    func stopForPremiumLoss() async {
        guard currentSource != .local else { return }
        if player.state.playbackStatus == .playing {
            player.pause()
            isPlaying = false
        }
        setStatus(title: "Premium Required", message: "Upgrade to Premium to play Apple Music playlists.")
    }

    func isPlayingPlaylist(_ itemId: String) -> Bool {
        isPlaying && currentPlaylistItemId == itemId
    }

    func togglePlaylist(itemId: String, title: String) async {
        if !supportsAppleMusicPlayback {
            return
        }
        configureTransition()
        guard let uuid = UUID(uuidString: itemId) else {
            setStatus(title: "Playlist Error", message: "Invalid playlist reference.")
            return
        }
        let source: PlaylistSource
        do {
            source = try await AppBackend.shared.musicRepository.playlistSource(for: uuid)
        } catch {
            setStatus(title: "Playlist Error", message: "Missing playlist details.")
            return
        }
        if source == .local {
            if player.state.playbackStatus == .playing {
                player.pause()
                isPlaying = false
            }
            await toggleLocalPlaylist(itemId: itemId, title: title)
            return
        }
        if currentSource == .local {
            stopAllLocalPlayers()
        }
        if !PremiumStore.shared.isPremium {
            setStatus(title: "Premium Required", message: "Upgrade to Premium to play Apple Music playlists.")
            return
        }
        guard await ensurePlayable() else { return }
        if isStartingPlayback {
            pendingPlaylistSelection = (itemId, title)
            return
        }
        isStartingPlayback = true
        defer {
            isStartingPlayback = false
            if let pending = pendingPlaylistSelection {
                pendingPlaylistSelection = nil
                Task { await togglePlaylist(itemId: pending.id, title: pending.title) }
            }
        }
        if currentPlaylistItemId == itemId, player.queue.currentEntry != nil {
            if player.state.playbackStatus == .playing {
                player.pause()
                isPlaying = false
                return
            } else {
                isPlaying = true
                do {
                    try await player.play()
                    await refresh()
                } catch {
                    await handlePlaybackAuthFailure(forcePrompt: true)
                    isPlaying = false
                    setStatus(title: "Playback Error", message: "Unable to start Apple Music playback.")
                }
                return
            }
        }
        if player.state.playbackStatus == .playing {
            player.pause()
            isPlaying = false
        }

        do {
            let playlistId = try await AppBackend.shared.musicRepository.playlistID(for: uuid)
            currentSource = .appleMusic
            currentPlaylistItemId = itemId
            let (loadedPlaylist, playlistEntries) = try await loadPlaylistEntries(playlistId: playlistId)
            guard let playlist = loadedPlaylist else {
                setStatus(title: "Playlist Missing", message: "Could not load the selected playlist.")
                return
            }
            guard !playlistEntries.isEmpty else {
                setStatus(title: "Empty Playlist", message: "This playlist has no playable items.")
                return
            }
            if let startEntry = playlistEntries.first {
                applyQueue(loadedPlaylist: playlist, playlistEntries: playlistEntries, startEntry: startEntry)
            }
            playlistTitle = title
            isPlaying = true
            do {
                try await playWithFallback(playlistEntries: playlistEntries)
            } catch {
                await handlePlaybackAuthFailure(forcePrompt: true)
                isPlaying = false
                setStatus(title: "Playback Error", message: "Unable to start Apple Music playback.")
                return
            }
            await refresh()
            notifyPlaylistStarted(title: title)
        } catch {
            setStatus(title: "Playback Error", message: "Unable to start Apple Music playback.")
        }
    }

    func prepareInitialLocalPlaylist(itemId: String, title: String) async {
        guard currentPlaylistItemId == nil else { return }
        guard let uuid = UUID(uuidString: itemId) else { return }

        if player.state.playbackStatus == .playing {
            player.pause()
        }
        stopAllLocalPlayers()

        do {
            let tracks = try await AppBackend.shared.musicRepository.fetchLocalPlaylistTracks(itemId: uuid)
            guard !tracks.isEmpty else { return }

            localTracks = tracks
            localCurrentTrackIndex = 0
            await startLocalPlayback(at: 0, shouldPlay: false)
            currentSource = .local
            currentPlaylistItemId = itemId
            playlistTitle = title
            isPlaying = false
            statusMessage = nil
            await refreshLocal()
        } catch {
            // Keep startup resilient if the default playlist isn't available.
        }
    }

    func next() async {
        if currentSource == .local {
            await moveLocalTrack(by: 1)
            return
        }
        configureTransition()
        do {
            try await player.skipToNextEntry()
            await refresh()
        } catch {
            await wrapAppleMusicBoundary(direction: .next)
        }
    }

    func previous() async {
        if currentSource == .local {
            await moveLocalTrack(by: -1)
            return
        }
        configureTransition()
        do {
            try await player.skipToPreviousEntry()
            await refresh()
        } catch {
            await wrapAppleMusicBoundary(direction: .previous)
        }
    }

    func beginScrub() {
        isScrubbing = true
        updateTimerIfNeeded()
    }

    func updateScrub(to time: TimeInterval) {
        setPlaybackTime(
            time,
            at: Date(),
            anchorsPlayerTime: false,
            forceProgressPublish: true
        )
    }

    func endScrub(to time: TimeInterval) async {
        isScrubbing = false
        updateTimerIfNeeded()
        let clamped = min(max(0, time), duration)
        if currentSource == .local {
            seekLocal(to: clamped)
            await refreshLocal()
        } else {
            player.playbackTime = clamped
            await refresh()
        }
    }

    private func tick() {
        if currentSource == .local {
            let now = Date()
            if !isScrubbing, isPlaying, duration > 0 {
                let elapsed = now.timeIntervalSince(lastPlayerTimeDate)
                if elapsed >= 0 {
                    setPlaybackTime(lastPlayerTime + elapsed, at: now, anchorsPlayerTime: false)
                }
            }
            if isPlaying {
                handleLocalCrossfadeTick()
            }
            requestPeriodicRefresh(local: true, now: now)
            return
        }
        if !PremiumStore.shared.isPremium || MusicAuthorization.currentStatus != .authorized {
            return
        }
        let now = Date()
        if !isScrubbing, isPlaying, duration > 0 {
            let elapsed = now.timeIntervalSince(lastPlayerTimeDate)
            if elapsed >= 0 {
                setPlaybackTime(lastPlayerTime + elapsed, at: now, anchorsPlayerTime: false)
            }
        }

        requestPeriodicRefresh(local: false, now: now)
    }

    private func updateTimerIfNeeded() {
        let desiredInterval: TimeInterval
        if localIsCrossfading {
            desiredInterval = crossfadeTimerInterval
        } else if isScrubbing {
            desiredInterval = scrubbingTimerInterval
        } else if isPlaying {
            desiredInterval = activeTimerInterval
        } else {
            desiredInterval = idleTimerInterval
        }
        if abs(timerInterval - desiredInterval) > 0.001 {
            timerInterval = desiredInterval
            scheduleTimer(interval: timerInterval)
        }
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        newTimer.tolerance = min(max(0.01, interval * 0.3), 0.2)
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func clampedPlaybackTime(_ time: TimeInterval) -> TimeInterval {
        let lowerBound = max(0, time)
        guard duration > 0 else { return lowerBound }
        return min(lowerBound, duration)
    }

    private func setPlaybackTime(
        _ time: TimeInterval,
        at now: Date,
        anchorsPlayerTime: Bool,
        forceProgressPublish: Bool = false
    ) {
        let clamped = clampedPlaybackTime(time)
        playbackTime = clamped
        if anchorsPlayerTime {
            lastPlayerTime = clamped
            lastPlayerTimeDate = now
        }
        publishPlaybackProgress(now: now, force: forceProgressPublish)
    }

    private func publishPlaybackProgress(now: Date = Date(), force: Bool = false) {
        if !force, now.timeIntervalSince(lastProgressPublishDate) < progressPublishInterval {
            return
        }
        lastProgressPublishDate = now
        playbackProgress.update(
            time: playbackTime,
            duration: duration,
            isPlaying: isPlaying,
            at: now,
            force: force
        )
    }

    private func requestPeriodicRefresh(local: Bool, now: Date) {
        guard now.timeIntervalSince(lastSyncDate) >= stateRefreshInterval else { return }
        guard !isStateRefreshInFlight else { return }
        isStateRefreshInFlight = true
        Task { @MainActor in
            defer { self.isStateRefreshInFlight = false }
            if local {
                await self.refreshLocal()
            } else {
                await self.refresh()
            }
        }
    }

    private func loadArtwork(from artwork: Artwork?) async {
        guard let artwork, let url = artwork.url(width: 160, height: 160) else {
            artworkImage = nil
            return
        }
        if let cached = remoteArtworkCache[url] {
            artworkImage = cached
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let image = imageFromData(data)
            artworkImage = image
            if let image {
                remoteArtworkCache[url] = image
            }
        } catch {
            artworkImage = nil
        }
    }

    private func imageFromData(_ data: Data) -> Image? {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        #elseif canImport(AppKit)
        if let nsImage = NSImage(data: data) {
            return Image(nsImage: nsImage)
        }
        #endif
        return nil
    }

    private func refreshLocal() async {
        isPlaying = isLocalPlaying()
        let now = Date()
        if let activePlayer = activeLocalPlayer() {
            if lastLocalMetadataIndex != localCurrentTrackIndex {
                lastLocalMetadataIndex = localCurrentTrackIndex
                await updateLocalMetadata(for: localCurrentTrackIndex)
            }
            if !isScrubbing {
                setPlaybackTime(
                    activePlayer.currentTime,
                    at: now,
                    anchorsPlayerTime: true,
                    forceProgressPublish: true
                )
            }
            duration = activePlayer.duration
            lastSyncDate = now
        } else {
            title = "Not Playing"
            artist = ""
            duration = 0
            setPlaybackTime(
                0,
                at: now,
                anchorsPlayerTime: true,
                forceProgressPublish: true
            )
            artworkImage = nil
        }
    }

    private func updateLocalMetadata(for index: Int) async {
        guard localTracks.indices.contains(index) else { return }
        let track = localTracks[index]
        title = track.title
        artist = track.artist ?? ""
        if let trackDuration = track.duration {
            duration = trackDuration
        }
        if let cached = localArtworkCache[track.assetId] {
            artworkImage = cached
        } else {
            let url = AppFilePaths.applicationSupportURL().appendingPathComponent(track.localPath)
            let asset = AVURLAsset(url: url)
            let artwork = await extractArtwork(from: asset)
            artworkImage = artwork
            if let artwork {
                localArtworkCache[track.assetId] = artwork
            }
        }
    }

    private func extractArtwork(from asset: AVAsset) async -> Image? {
        do {
            let metadata = try await asset.load(.commonMetadata)
            for item in metadata {
                guard let key = item.commonKey, key == .commonKeyArtwork else { continue }
                if let data = try await item.load(.dataValue) {
                    return imageFromData(data)
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func resolveDuration(for entry: MusicKit.MusicPlayer.Queue.Entry) -> TimeInterval {
        if let endTime = entry.endTime {
            if let startTime = entry.startTime {
                return max(0, endTime - startTime)
            }
            return max(0, endTime)
        }

        if let item = entry.item {
            switch item {
            case .song(let song):
                return song.duration ?? 0
            case .musicVideo(let musicVideo):
                return musicVideo.duration ?? 0
            @unknown default:
                return 0
            }
        }

        return 0
    }

    private struct ArtworkKey: Hashable {
        let title: String
        let subtitle: String?
        let artworkURL: URL?
    }

    private func updateArtworkIfNeeded(for entry: MusicKit.MusicPlayer.Queue.Entry) async {
        let key = ArtworkKey(
            title: entry.title,
            subtitle: entry.subtitle,
            artworkURL: entry.artwork?.url(width: 160, height: 160)
        )
        if key == lastArtworkKey {
            return
        }
        lastArtworkKey = key
        await loadArtwork(from: entry.artwork)
    }

    private func toggleLocalPlaylist(itemId: String, title: String) async {
        if isStartingPlayback {
            pendingPlaylistSelection = (itemId, title)
            return
        }
        isStartingPlayback = true
        defer {
            isStartingPlayback = false
            if let pending = pendingPlaylistSelection {
                pendingPlaylistSelection = nil
                Task { await togglePlaylist(itemId: pending.id, title: pending.title) }
            }
        }

        if currentPlaylistItemId == itemId, activeLocalPlayer() != nil {
            if isLocalPlaying() {
                isPlaying = false
                await pauseLocalPlayersWithFade(duration: userStopFadeDuration)
            } else {
                playLocalPlayers()
                isPlaying = true
            }
            await refreshLocal()
            return
        }

        if player.state.playbackStatus == .playing {
            player.pause()
        }

        do {
            guard let uuid = UUID(uuidString: itemId) else {
                setStatus(title: "Playlist Error", message: "Invalid playlist reference.")
                return
            }
            let tracks = try await AppBackend.shared.musicRepository.fetchLocalPlaylistTracks(itemId: uuid)
            guard !tracks.isEmpty else {
                setStatus(title: "Empty Playlist", message: "This playlist has no playable items.")
                return
            }
            localTracks = tracks
            localCurrentTrackIndex = 0
            await startLocalPlayback(at: 0, shouldPlay: true)
            currentSource = .local
            currentPlaylistItemId = itemId
            playlistTitle = title
            isPlaying = true
            await refreshLocal()
            notifyPlaylistStarted(title: title)
        } catch {
            setStatus(title: "Playback Error", message: "Unable to start local playback.")
        }
    }

    private func startLocalPlayback(at index: Int, shouldPlay: Bool) async {
        cancelLocalPauseFadeAndRestoreVolume()
        await AppBackend.shared.audioManager.prepareAudioSessionForPlayback()
        let clampedIndex = min(max(0, index), max(0, localTracks.count - 1))
        localCurrentTrackIndex = clampedIndex
        localIsCrossfading = false
        localCrossfadeStart = nil
        localNextTrackIndex = nil
        localIsAdvancing = false
        activeLocalPlayerIndex = 0
        lastLocalMetadataIndex = nil
        localPlayers = [nil, nil]
        if let player = await buildLocalPlayer(for: clampedIndex) {
            player.volume = effectiveLocalMusicVolume
            localPlayers[activeLocalPlayerIndex] = player
            if shouldPlay {
                player.play()
            }
        }
        updateTimerIfNeeded()
    }

    private func moveLocalTrack(by offset: Int) async {
        guard !localTracks.isEmpty else { return }
        let count = localTracks.count
        let target: Int
        if playlistPlaybackMode == .shuffle {
            target = randomLocalTrackIndex(excluding: localCurrentTrackIndex)
        } else {
            var wrapped = (localCurrentTrackIndex + offset) % count
            if wrapped < 0 {
                wrapped += count
            }
            target = wrapped
        }
        let wasPlaying = isLocalPlaying()
        stopAllLocalPlayers()
        await startLocalPlayback(at: target, shouldPlay: wasPlaying)
        await refreshLocal()
    }

    private enum BoundaryDirection {
        case next
        case previous
    }

    private func wrapAppleMusicBoundary(direction: BoundaryDirection) async {
        guard playlistPlaybackMode == .repeatAll else { return }
        guard let itemId = currentPlaylistItemId,
              let uuid = UUID(uuidString: itemId) else {
            return
        }

        do {
            let playlistId = try await AppBackend.shared.musicRepository.playlistID(for: uuid)
            let (loadedPlaylist, playlistEntries) = try await loadPlaylistEntries(playlistId: playlistId)
            guard let playlist = loadedPlaylist, !playlistEntries.isEmpty else { return }

            let targetEntry: Playlist.Entry?
            switch direction {
            case .next:
                targetEntry = playlistEntries.first
            case .previous:
                targetEntry = playlistEntries.last
            }
            guard let targetEntry else { return }

            applyQueue(loadedPlaylist: playlist, playlistEntries: playlistEntries, startEntry: targetEntry)

            if isPlaying {
                try await playWithFallback(playlistEntries: playlistEntries)
            }

            await refresh()
        } catch {
            // Keep existing now-playing state if we cannot resolve wrap-around.
        }
    }

    private func maybeLoopAppleMusicIfNeeded() async {
        guard supportsAppleMusicPlayback else { return }
        guard currentSource == .appleMusic else { return }
        guard playlistPlaybackMode == .repeatAll else { return }
        guard let itemId = currentPlaylistItemId else { return }
        guard player.queue.currentEntry == nil else { return }
        guard !isStartingPlayback, !isRestartingAppleMusic else { return }
        isRestartingAppleMusic = true
        defer { isRestartingAppleMusic = false }
        await togglePlaylist(itemId: itemId, title: playlistTitle)
    }

    private func activeLocalPlayer() -> AVAudioPlayer? {
        localPlayers[activeLocalPlayerIndex]
    }

    private func inactiveLocalPlayer() -> AVAudioPlayer? {
        localPlayers[1 - activeLocalPlayerIndex]
    }

    private func isLocalPlaying() -> Bool {
        activeLocalPlayer()?.isPlaying == true
    }

    private func playLocalPlayers() {
        cancelLocalPauseFadeAndRestoreVolume()
        activeLocalPlayer()?.play()
        if localIsCrossfading {
            inactiveLocalPlayer()?.play()
        }
    }

    private func pauseLocalPlayers() {
        activeLocalPlayer()?.pause()
        inactiveLocalPlayer()?.pause()
    }

    private func pauseLocalPlayersWithFade(duration: TimeInterval) async {
        let safeDuration = max(0, duration)
        guard safeDuration > 0.001 else {
            cancelLocalPauseFadeAndRestoreVolume()
            pauseLocalPlayers()
            return
        }

        localPauseFadeTask?.cancel()
        localPauseFadeGeneration &+= 1
        let generation = localPauseFadeGeneration

        let activeStart = activeLocalPlayer()?.volume ?? effectiveLocalMusicVolume
        let inactiveStart = inactiveLocalPlayer()?.volume ?? 0
        let steps = max(1, localPauseFadeStepCount)
        let stepDuration = max(safeDuration / Double(steps), 0.01)

        let fadeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for step in 1...steps {
                if Task.isCancelled || generation != self.localPauseFadeGeneration { return }
                try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
                if Task.isCancelled || generation != self.localPauseFadeGeneration { return }
                let progress = Float(step) / Float(steps)
                let multiplier = max(0, 1 - progress)
                self.activeLocalPlayer()?.volume = activeStart * multiplier
                self.inactiveLocalPlayer()?.volume = inactiveStart * multiplier
            }
            guard generation == self.localPauseFadeGeneration else { return }
            self.pauseLocalPlayers()
            self.applyEffectiveLocalMusicVolume()
            self.localPauseFadeTask = nil
        }

        localPauseFadeTask = fadeTask
        await fadeTask.value
    }

    private func cancelLocalPauseFadeAndRestoreVolume() {
        localPauseFadeTask?.cancel()
        localPauseFadeTask = nil
        localPauseFadeGeneration &+= 1
        applyEffectiveLocalMusicVolume()
    }

    private func stopAllLocalPlayers() {
        cancelLocalPauseFadeAndRestoreVolume()
        localPlayers.forEach { $0?.stop() }
        localPlayers = [nil, nil]
        localIsCrossfading = false
        localCrossfadeStart = nil
        localNextTrackIndex = nil
        lastLocalMetadataIndex = nil
        localIsAdvancing = false
        updateTimerIfNeeded()
    }

    private func seekLocal(to time: TimeInterval) {
        let clamped = max(0, min(time, activeLocalPlayer()?.duration ?? 0))
        if localIsCrossfading {
            inactiveLocalPlayer()?.stop()
            localPlayers[1 - activeLocalPlayerIndex] = nil
            localIsCrossfading = false
            localCrossfadeStart = nil
            localNextTrackIndex = nil
            activeLocalPlayer()?.volume = effectiveLocalMusicVolume
            updateTimerIfNeeded()
        }
        activeLocalPlayer()?.currentTime = clamped
    }

    private func handleLocalCrossfadeTick() {
        guard let active = activeLocalPlayer() else { return }
        let duration = active.duration
        guard duration > 0 else { return }
        let remaining = max(0, duration - active.currentTime)
        let maxFade = min(localCrossfadeDuration, max(0.0, duration / 2.0))
        let shortTrackThreshold = localCrossfadeDuration * 1.5
        let endThreshold: TimeInterval = 0.15

        if duration <= shortTrackThreshold {
            if remaining <= endThreshold {
                scheduleAdvanceLocalTrack()
            }
            return
        }

        if !localIsCrossfading, localNextTrackIndex == nil, remaining <= maxFade {
            let nextIndex = nextAutomaticLocalTrackIndex()
            if let nextDuration = localTracks.indices.contains(nextIndex) ? localTracks[nextIndex].duration : nil {
                let minCrossfadeable = localCrossfadeDuration + 0.5
                if nextDuration <= minCrossfadeable {
                    if remaining <= endThreshold {
                        scheduleAdvanceLocalTrack()
                    }
                    return
                }
            }
            localNextTrackIndex = nextIndex
            Task { @MainActor in
                if let nextPlayer = await buildLocalPlayer(for: nextIndex) {
                    let nextSlot = 1 - activeLocalPlayerIndex
                    nextPlayer.volume = 0.0
                    localPlayers[nextSlot] = nextPlayer
                    nextPlayer.play()
                    localIsCrossfading = true
                    localCrossfadeStart = Date()
                    updateTimerIfNeeded()
                } else {
                    localNextTrackIndex = nil
                }
            }
            return
        }

        if localIsCrossfading, let start = localCrossfadeStart {
            let elapsed = Date().timeIntervalSince(start)
            let progress = min(1.0, max(0.0, elapsed / maxFade))
            active.volume = Float(1.0 - progress) * effectiveLocalMusicVolume
            inactiveLocalPlayer()?.volume = Float(progress) * effectiveLocalMusicVolume
            if progress >= 1.0 {
                active.stop()
                localPlayers[activeLocalPlayerIndex] = nil
                activeLocalPlayerIndex = 1 - activeLocalPlayerIndex
                localCurrentTrackIndex = localNextTrackIndex ?? localCurrentTrackIndex
                localNextTrackIndex = nil
                localIsCrossfading = false
                localCrossfadeStart = nil
                activeLocalPlayer()?.volume = effectiveLocalMusicVolume
                lastLocalMetadataIndex = nil
                updateTimerIfNeeded()
            }
        } else if remaining <= endThreshold {
            scheduleAdvanceLocalTrack()
        }
    }

    private func scheduleAdvanceLocalTrack() {
        guard !localIsAdvancing else { return }
        localIsAdvancing = true
        Task { @MainActor in
            await advanceLocalTrack(shouldPlay: true)
        }
    }

    private func advanceLocalTrack(shouldPlay: Bool) async {
        let nextIndex = nextAutomaticLocalTrackIndex()
        stopAllLocalPlayers()
        await startLocalPlayback(at: nextIndex, shouldPlay: shouldPlay)
        await refreshLocal()
        localIsAdvancing = false
    }

    private func nextAutomaticLocalTrackIndex() -> Int {
        guard !localTracks.isEmpty else { return 0 }
        switch playlistPlaybackMode {
        case .shuffle:
            return randomLocalTrackIndex(excluding: localCurrentTrackIndex)
        case .repeatAll:
            return (localCurrentTrackIndex + 1) % localTracks.count
        case .repeatOne:
            return localCurrentTrackIndex
        }
    }

    private func randomLocalTrackIndex(excluding index: Int) -> Int {
        guard localTracks.count > 1 else { return index }
        var candidate = Int.random(in: 0..<localTracks.count)
        while candidate == index {
            candidate = Int.random(in: 0..<localTracks.count)
        }
        return candidate
    }

    private func buildLocalPlayer(for index: Int) async -> AVAudioPlayer? {
        guard localTracks.indices.contains(index) else { return nil }
        let track = localTracks[index]
        let url = AppFilePaths.applicationSupportURL().appendingPathComponent(track.localPath)
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0
            player.prepareToPlay()
            return player
        } catch {
            return nil
        }
    }

    private func ensureQueueLoaded() async -> Bool {
        guard supportsAppleMusicPlayback else { return false }
        if player.queue.currentEntry != nil {
            return true
        }
        do {
            let catalogEntries = try await AppBackend.shared.musicRepository.listMusicEntries()
            guard let first = catalogEntries.first else { return false }
            let (loadedPlaylist, playlistEntries) = try await loadPlaylistEntries(playlistId: first.playlistRef.appleMusicPlaylistId)
            guard let playlist = loadedPlaylist else { return false }
            guard !playlistEntries.isEmpty else { return false }
            if let startEntry = playlistEntries.first {
                applyQueue(loadedPlaylist: playlist, playlistEntries: playlistEntries, startEntry: startEntry)
            }
            currentPlaylistItemId = first.item.id
            currentSource = .appleMusic
            playlistTitle = first.item.title
            return true
        } catch {
            return false
        }
    }

    private func setStatus(title: String, message: String) {
        self.title = title
        self.artist = message
        self.artworkImage = nil
        self.duration = 0
        self.setPlaybackTime(
            0,
            at: Date(),
            anchorsPlayerTime: true,
            forceProgressPublish: true
        )
        self.statusMessage = message
    }

    private func ensurePlayable() async -> Bool {
        if !PremiumStore.shared.isPremium {
            setStatus(title: "Premium Required", message: "Upgrade to Premium to play Apple Music playlists.")
            return false
        }
        let status = MusicAuthorization.currentStatus
        if status != .authorized {
            setStatus(title: "Apple Music Access Needed", message: "Enable access in Settings to play music.")
            return false
        }
        do {
            let subscription = try await MusicSubscription.current
            if !subscription.canPlayCatalogContent {
                setStatus(title: "Apple Music Required", message: "A subscription is needed to play Apple Music.")
                return false
            }
        } catch {
            // If subscription status cannot be determined, allow playback attempt and surface any play errors.
        }
        return true
    }

    private func handlePlaybackAuthFailure(forcePrompt: Bool = false) async {
        if !PremiumStore.shared.isPremium {
            setStatus(title: "Premium Required", message: "Upgrade to Premium to play Apple Music playlists.")
            return
        }
        let status = MusicAuthorization.currentStatus
        if status != .authorized || forcePrompt {
            setStatus(title: "Apple Music Access Needed", message: "Enable access in Settings to play music.")
        }
    }

    private func loadPlaylistEntries(playlistId: String) async throws -> (Playlist?, MusicItemCollection<Playlist.Entry>) {
        guard supportsAppleMusicPlayback else { return (nil, MusicItemCollection<Playlist.Entry>()) }
        if let cachedEntries = playlistEntriesCache[playlistId], let cachedPlaylist = playlistCache[playlistId] {
            return (cachedPlaylist, cachedEntries)
        }
        guard let playlist = try await AppBackend.shared.musicRepository.fetchLibraryPlaylist(id: playlistId) else {
            return (nil, MusicItemCollection<Playlist.Entry>())
        }
        let loadedPlaylist = try await playlist.with([.entries])
        let entries = loadedPlaylist.entries ?? MusicItemCollection<Playlist.Entry>()
        playlistCache[playlistId] = loadedPlaylist
        playlistEntriesCache[playlistId] = entries
        let songs = entries.compactMap { entry -> Song? in
            guard let item = entry.item else { return nil }
            switch item {
            case .song(let song):
                return song
            default:
                return nil
            }
        }
        if !songs.isEmpty {
            playlistSongCache[playlistId] = songs
        }
        return (loadedPlaylist, entries)
    }

    private func applyQueue(
        loadedPlaylist: Playlist,
        playlistEntries: MusicItemCollection<Playlist.Entry>,
        startEntry: Playlist.Entry
    ) {
        if #available(iOS 16.4, *) {
            player.queue = ApplicationMusicPlayer.Queue(playlist: loadedPlaylist, startingAt: startEntry)
        } else {
            player.queue = ApplicationMusicPlayer.Queue(for: playlistEntries)
        }
        applyPlaylistPlaybackModeToAppleMusicPlayer()
    }

    private func playWithFallback(playlistEntries: MusicItemCollection<Playlist.Entry>) async throws {
        do {
            try await player.play()
        } catch {
            if !playlistEntries.isEmpty {
                player.queue = ApplicationMusicPlayer.Queue(for: playlistEntries)
                applyPlaylistPlaybackModeToAppleMusicPlayer()
                try await player.play()
            } else {
                throw error
            }
        }
    }

    private func notifyPlaylistStarted(title: String) {
        NotificationCenter.default.post(
            name: MusicPlaybackStore.playlistDidStartNotification,
            object: title
        )
    }

    private func notifyPlaylistStartedIfAvailable() {
        guard currentPlaylistItemId != nil else { return }
        let title = playlistTitle
        if !title.isEmpty, title != "Now Playing" {
            notifyPlaylistStarted(title: title)
        }
    }
}
