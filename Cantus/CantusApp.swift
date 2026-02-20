import SwiftUI
import MusicKit
import TipKit

@available(iOS 18.0, *)
@main
struct CantusApp: App {
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = true
    @AppStorage("cantus.firstLaunchDefaults.v1.applied") private var hasAppliedFirstLaunchDefaults = false
    @StateObject private var theme = ThemeModel()
    @StateObject private var bookmarks = BookmarksStore()
    @StateObject private var playbackState = PlaybackStateStore()
    @StateObject private var backend = AppBackend.shared
    @StateObject private var premium = PremiumStore.shared
    @StateObject private var musicPlayback = MusicPlaybackStore()
    @StateObject private var menuState = AppMenuState()
    @Environment(\.scenePhase) private var scenePhase
    @State private var shouldPromptAppleMusic = false

    private let defaultPlaylistBookmarks = [
        "Initiative!",
        "The Copper Cup",
        "Caravan at Dawn",
        "The Hungry Dark"
    ]
    private let defaultAtmosphereBookmarks = [
        "Damp Sewers",
        "Sunny Forest",
        "Busy Marketplace",
        "Creepy Drone"
    ]
    private let defaultSFXBookmarks = [
        "Blade Impact Metal",
        "Dragon Fire Breath",
        "Lock Mechanism",
        "Magic Burst",
        "Arrow Thwoosh",
        "Beast Snarl"
    ]
    private let defaultNowPlayingPlaylistTitle = "Initiative!"

    init() {
        do {
            try Tips.configure([
                .displayFrequency(.immediate)
            ])
        } catch {
            // Keep app launch resilient if TipKit datastore configuration fails.
        }
    }

    var body: some Scene {
        WindowGroup {
            withSharedEnvironment(
                RootView(hasCompletedSetup: $hasCompletedSetup)
                    .frame(minWidth: 384)
                    .preferredColorScheme(.dark)
                    .task {
                        backend.audioManager.prewarmAudioSession()
                        await backend.audioManager.prepareAudioSessionForPlayback()
                        await backend.seedIfNeeded()
                        await applyFirstLaunchDefaultsIfNeeded()
                        await promptAppleMusicIfNeeded()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: PremiumStore.didSubscribeNotification)) { _ in
                        shouldPromptAppleMusic = true
                    }
                    .task(id: shouldPromptAppleMusic) {
                        guard shouldPromptAppleMusic else { return }
                        shouldPromptAppleMusic = false
                        await promptAppleMusicIfNeeded()
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        guard newPhase == .active else { return }
                        Task {
                            backend.audioManager.prewarmAudioSession()
                            await promptAppleMusicIfNeeded()
                        }
                    }
            )
        }
        .defaultSize(width: 1365, height: 1104)
        .windowResizability(.contentMinSize)
        .windowStyle(.automatic)
        .windowToolbarStyle(.automatic)
        .commands {
            CantusMenuCommands(menuState: menuState)
        }

        Window("About Cantus", id: CantusWindowID.about) {
            withSharedEnvironment(
                AboutView()
            )
        }
        .defaultSize(width: 440, height: 320)
        .windowStyle(.automatic)
        .windowToolbarStyle(.automatic)

        Window("Settings", id: CantusWindowID.settings) {
            withSharedEnvironment(
                SettingsView()
            )
        }
        .defaultSize(width: 480, height: 660)
        .windowStyle(.automatic)
        .windowToolbarStyle(.automatic)

        WindowGroup("Playlists", for: PlaylistPanelWindowPayload.self) { payload in
            withSharedEnvironment(
                PlaylistPanelView(initialFilter: payload.wrappedValue?.initialFilter)
            )
        }
        .defaultSize(width: 480, height: 660)
        .windowStyle(.automatic)
        .windowToolbarStyle(.automatic)

        Window("Atmospheres", id: CantusWindowID.atmospheres) {
            withSharedEnvironment(
                AtmospherePanelView()
            )
        }
        .defaultSize(width: 480, height: 660)
        .windowStyle(.automatic)
        .windowToolbarStyle(.automatic)

        Window("Sound Effects", id: CantusWindowID.soundEffects) {
            withSharedEnvironment(
                SoundboardPanelView()
            )
        }
        .defaultSize(width: 480, height: 660)
        .windowStyle(.automatic)
        .windowToolbarStyle(.automatic)

        WindowGroup("Import Asset", for: ImportAssetWindowPayload.self) { payload in
            withSharedEnvironment(
                ImportAssetsView(
                    initialFileURL: payload.wrappedValue?.fileURL,
                    initialKind: payload.wrappedValue?.initialKind
                )
            )
        }
        .defaultSize(width: 480, height: 660)
        .windowStyle(.automatic)
        .windowToolbarStyle(.automatic)

        WindowGroup("Add Playlist", for: AddPlaylistWindowPayload.self) { payload in
            withSharedEnvironment(
                AddPlaylistWindowRoot(
                    initialTab: payload.wrappedValue?.preferredTab ?? .local
                )
            )
        }
        .defaultSize(width: 760, height: 820)
        .windowStyle(.automatic)
        .windowToolbarStyle(.automatic)

        WindowGroup("Edit Attributes", for: EditAssetWindowPayload.self) { payload in
            if let payload = payload.wrappedValue {
                withSharedEnvironment(
                    EditAssetView(
                        itemId: payload.itemId,
                        initialTitle: payload.title,
                        initialKind: payload.kind
                    )
                )
            } else {
                EmptyView()
            }
        }
        .defaultSize(width: 720, height: 800)
        .windowStyle(.automatic)
        .windowToolbarStyle(.automatic)

        WindowGroup("Edit Playlist", for: EditPlaylistWindowPayload.self) { payload in
            if let payload = payload.wrappedValue {
                withSharedEnvironment(
                    EditPlaylistView(
                        itemId: payload.itemId,
                        initialTitle: payload.title
                    )
                )
            } else {
                EmptyView()
            }
        }
        .defaultSize(width: 720, height: 800)
        .windowStyle(.automatic)
        .windowToolbarStyle(.automatic)
    }

    @MainActor
    private func applyFirstLaunchDefaultsIfNeeded() async {
        guard !hasAppliedFirstLaunchDefaults else { return }
        if hasExistingUserState {
            hasAppliedFirstLaunchDefaults = true
            return
        }

        async let playlistItemsTask = backend.libraryRepository.fetchItems(
            kind: .music,
            filters: Filters(),
            sort: .titleAsc
        )
        async let atmosphereItemsTask = backend.libraryRepository.fetchItems(
            kind: .atmosphere,
            filters: Filters(),
            sort: .titleAsc
        )
        async let sfxItemsTask = backend.libraryRepository.fetchItems(
            kind: .sfx,
            filters: Filters(),
            sort: .titleAsc
        )

        do {
            let (playlistItems, atmosphereItems, sfxItems) = try await (
                playlistItemsTask,
                atmosphereItemsTask,
                sfxItemsTask
            )

            let playlistBookmarks = resolveDefaultTitles(
                requested: defaultPlaylistBookmarks,
                available: playlistItems.map(\.title)
            )
            let atmosphereBookmarks = resolveDefaultTitles(
                requested: defaultAtmosphereBookmarks,
                available: atmosphereItems.map(\.title)
            )
            let sfxBookmarks = resolveDefaultTitles(
                requested: defaultSFXBookmarks,
                available: sfxItems.map(\.title)
            )

            bookmarks.setInitialBookmarks(
                playlists: playlistBookmarks,
                atmospheres: atmosphereBookmarks,
                soundEffects: sfxBookmarks
            )

            var didPrepareInitialPlaylist = false
            if let initiative = playlistItems.first(where: {
                $0.title.caseInsensitiveCompare(defaultNowPlayingPlaylistTitle) == .orderedSame
            }) {
                await musicPlayback.prepareInitialLocalPlaylist(
                    itemId: initiative.id,
                    title: initiative.title
                )
                didPrepareInitialPlaylist = musicPlayback.currentPlaylistItemId == initiative.id
            }
            hasAppliedFirstLaunchDefaults = didPrepareInitialPlaylist
        } catch {
            // Keep app launch resilient if default seeding lookup fails.
        }
    }

    private func resolveDefaultTitles(requested: [String], available: [String]) -> [String] {
        var lookup: [String: String] = [:]
        for title in available {
            lookup[title.lowercased()] = title
        }
        return requested.compactMap { lookup[$0.lowercased()] }
    }

    private var hasExistingUserState: Bool {
        !bookmarks.playlistBookmarkList.isEmpty ||
        !bookmarks.loopBookmarkList.isEmpty ||
        !bookmarks.sfxBookmarkList.isEmpty ||
        !playbackState.recentPlaylists.isEmpty ||
        !playbackState.recentLoops.isEmpty ||
        !playbackState.recentSFX.isEmpty
    }

    @MainActor
    private func promptAppleMusicIfNeeded() async {
        guard premium.consumePendingAppleMusicPrompt() else { return }
        guard MusicAuthorization.currentStatus == .notDetermined else { return }
        _ = await MusicAuthorization.request()
    }

    @ViewBuilder
    private func withSharedEnvironment<Content: View>(_ content: Content) -> some View {
        content
            .environmentObject(theme)
            .environmentObject(bookmarks)
            .environmentObject(playbackState)
            .environmentObject(backend)
            .environmentObject(premium)
            .environmentObject(musicPlayback)
            .environmentObject(menuState)
    }
}

@available(iOS 18.0, *)
private struct AddPlaylistWindowRoot: View {
    @State private var preferredTab: PlaylistAddSheetView.Tab
    @EnvironmentObject private var theme: ThemeModel
    @EnvironmentObject private var backend: AppBackend
    @EnvironmentObject private var premium: PremiumStore
    @EnvironmentObject private var bookmarks: BookmarksStore
    @EnvironmentObject private var playback: PlaybackStateStore
    @EnvironmentObject private var menuState: AppMenuState

    init(initialTab: PlaylistAddSheetView.Tab) {
        _preferredTab = State(initialValue: initialTab)
    }

    var body: some View {
        PlaylistAddSheetView(
            isPremium: premium.isPremium,
            onRequestUpgrade: {
                menuState.presentSettings()
            },
            onPlaylistAdded: {
                LibraryChangeNotifier.notify()
            },
            preferredTab: $preferredTab,
            showsTypeChooserInitially: true
        )
        .environmentObject(theme)
        .environmentObject(premium)
        .environmentObject(backend)
        .environmentObject(bookmarks)
        .environmentObject(playback)
    }
}

@available(iOS 18.0, *)
private struct CantusMenuCommands: Commands {
    @ObservedObject var menuState: AppMenuState
    @FocusedValue(\.menuControlsContext) private var menuControlsContext

    var body: some Commands {
#if os(iOS) || os(macOS)
        // App menu
        CommandGroup(replacing: .appInfo) {
            Button("About Cantus") {
                menuState.presentAbout()
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                menuState.presentSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        // File menu additions
        CommandGroup(after: .newItem) {
            Button("New Local Playlist") {
                menuState.presentAddPlaylist(preferredTab: .local)
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("Add Apple Music Playlist") {
                menuState.presentAddPlaylist(preferredTab: .appleMusic)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Import Atmosphere") {
                menuState.presentImport(initialKind: .atmosphere)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Button("Import Sound Effect") {
                menuState.presentImport(initialKind: .sfx)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        CommandGroup(after: .importExport) {
            Button("Import Sound Library") {
                menuState.presentSettings(action: .importLibrary)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Export Sound Library") {
                menuState.presentSettings(action: .exportLibrary)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        // View menu additions
        CommandGroup(after: .toolbar) {
            Button("Toggle Volume Sliders") {
                menuState.showVolumeSliders.toggle()
            }
            .keyboardShortcut(KeyEquivalent("1"), modifiers: [.command, .option])

            Button("Toggle Playlists") {
                menuState.showPlaylists.toggle()
            }
            .keyboardShortcut(KeyEquivalent("2"), modifiers: [.command, .option])

            Button("Toggle Atmospheres") {
                menuState.showAtmospheres.toggle()
            }
            .keyboardShortcut(KeyEquivalent("3"), modifiers: [.command, .option])

            Button("Toggle Sound Effects") {
                menuState.showSoundEffects.toggle()
            }
            .keyboardShortcut(KeyEquivalent("4"), modifiers: [.command, .option])
        }

        // Window menu additions
        CommandGroup(after: .windowArrangement) {
            Button("Playlists") {
                menuState.presentPlaylistPanel()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])

            Button("Atmospheres") {
                menuState.presentAtmospherePanel()
            }
            .keyboardShortcut("a", modifiers: [.command, .option])

            Button("Sound Effects") {
                menuState.presentSoundboardPanel()
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
        }

        CommandMenu("Controls") {
            Button("QuickPlay") {
                menuState.triggerQuickPlay()
            }
            .keyboardShortcut(.space, modifiers: [.command, .option])

            Divider()

            Button(action: { menuControlsContext?.togglePlayPause() }) {
                Label(
                    menuControlsContext?.isPlaylistPlaying == true ? "Pause Current Playlist" : "Play Current Playlist",
                    systemImage: menuControlsContext?.isPlaylistPlaying == true ? "pause.fill" : "play.fill"
                )
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(menuControlsContext == nil)

            Button("Next Song", systemImage: "forward.fill") {
                menuControlsContext?.nextSong()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])
            .disabled(menuControlsContext == nil)

            Button("Previous Song", systemImage: "backward.fill") {
                menuControlsContext?.previousSong()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            .disabled(menuControlsContext == nil)

            Button("Stop Active Atmospheres", systemImage: "stop.fill") {
                menuControlsContext?.stopAtmospheres()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(menuControlsContext == nil)

            Button("Stop Active Sound Effects", systemImage: "stop.fill") {
                menuControlsContext?.stopSoundEffects()
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(menuControlsContext == nil)

            Divider()

            Button("Increase Mix Volume", systemImage: "speaker.plus") {
                menuControlsContext?.increaseMixVolume()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command])
            .disabled(menuControlsContext == nil)

            Button("Decrease Mix Volume", systemImage: "speaker.minus") {
                menuControlsContext?.decreaseMixVolume()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command])
            .disabled(menuControlsContext == nil)

            Button("Increase Atmosphere Volume", systemImage: "speaker.plus") {
                menuControlsContext?.increaseAtmosphereVolume()
            }
            .keyboardShortcut(.upArrow, modifiers: [.option])
            .disabled(menuControlsContext == nil)

            Button("Decrease Atmosphere Volume", systemImage: "speaker.minus") {
                menuControlsContext?.decreaseAtmosphereVolume()
            }
            .keyboardShortcut(.downArrow, modifiers: [.option])
            .disabled(menuControlsContext == nil)

            Button("Increase Sound Effects Volume", systemImage: "speaker.plus") {
                menuControlsContext?.increaseSoundEffectsVolume()
            }
            .keyboardShortcut(.upArrow, modifiers: [.control])
            .disabled(menuControlsContext == nil)

            Button("Decrease Sound Effects Volume", systemImage: "speaker.minus") {
                menuControlsContext?.decreaseSoundEffectsVolume()
            }
            .keyboardShortcut(.downArrow, modifiers: [.control])
            .disabled(menuControlsContext == nil)
        }
#endif
    }
}
