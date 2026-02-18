import SwiftUI
import UniformTypeIdentifiers

@available(iOS 18.0, *)
struct RootView: View {
    @Binding var hasCompletedSetup: Bool
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var theme: ThemeModel
    @EnvironmentObject private var backend: AppBackend
    @EnvironmentObject private var playback: PlaybackStateStore
    @EnvironmentObject private var musicPlayback: MusicPlaybackStore
    @EnvironmentObject private var menuState: AppMenuState
    @State private var menuControlsContext: MenuControlsContext?

    var body: some View {
        Group {
            if hasCompletedSetup {
                NavigationStack {
                    PlayView(hasCompletedSetup: $hasCompletedSetup)
                }
            } else {
                SetupView(hasCompletedSetup: $hasCompletedSetup)
            }
        }
        .tint(theme.color)
        .focusedSceneValue(\.menuControlsContext, menuControlsContext)
        .onAppear {
            refreshMenuControlsContext()
            consumePendingWindowRequests()
        }
        .onChange(of: musicPlayback.isPlaying) { _, _ in
            refreshMenuControlsContext()
        }
        .onChange(of: menuState.showAbout) { _, _ in
            openAboutWindowIfNeeded()
        }
        .onChange(of: menuState.showSettings) { _, _ in
            openSettingsWindowIfNeeded()
        }
        .onChange(of: menuState.showPlaylistPanel) { _, _ in
            openPlaylistWindowIfNeeded()
        }
        .onChange(of: menuState.showAtmospherePanel) { _, _ in
            openAtmosphereWindowIfNeeded()
        }
        .onChange(of: menuState.showSoundboardPanel) { _, _ in
            openSoundEffectsWindowIfNeeded()
        }
        .onChange(of: menuState.showAddPlaylistSheet) { _, _ in
            openAddPlaylistWindowIfNeeded()
        }
        .onChange(of: menuState.importRequest) { _, _ in
            openImportWindowIfNeeded()
        }
        .onDrop(
            of: [UTType.fileURL, UTType.audio, UTType.data, UTType.item],
            isTargeted: nil,
            perform: handleDrop
        )
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }
                DispatchQueue.main.async {
                    menuState.presentImport(fileURL: url, initialKind: nil)
                }
            }
            return true
        }

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.audio.identifier) }) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { url, _ in
                guard let url else { return }
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                do {
                    if FileManager.default.fileExists(atPath: tempURL.path) {
                        try FileManager.default.removeItem(at: tempURL)
                    }
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    DispatchQueue.main.async {
                        menuState.presentImport(fileURL: tempURL, initialKind: nil)
                    }
                } catch {
                    return
                }
            }
            return true
        }

        return false
    }

    private func refreshMenuControlsContext() {
        menuControlsContext = MenuControlsContext(
            isPlaylistPlaying: musicPlayback.isPlaying,
            togglePlayPause: { Task { await musicPlayback.togglePlayPause() } },
            nextSong: { Task { await musicPlayback.next() } },
            previousSong: { Task { await musicPlayback.previous() } },
            stopAtmospheres: {
                playback.stopAllLoops()
                backend.audioManager.reconcileAtmospheres(to: [])
            },
            stopSoundEffects: {
                playback.stopAllSFX()
                backend.audioManager.reconcileSFX(to: [])
            },
            increaseMixVolume: { adjustMixVolume(by: 0.05) },
            decreaseMixVolume: { adjustMixVolume(by: -0.05) },
            increaseAtmosphereVolume: { adjustAtmosphereVolume(by: 0.05) },
            decreaseAtmosphereVolume: { adjustAtmosphereVolume(by: -0.05) },
            increaseSoundEffectsVolume: { adjustSoundEffectsVolume(by: 0.05) },
            decreaseSoundEffectsVolume: { adjustSoundEffectsVolume(by: -0.05) }
        )
    }

    private func adjustMixVolume(by delta: Double) {
        playback.masterVolume = clampVolume(playback.masterVolume + delta)
    }

    private func adjustAtmosphereVolume(by delta: Double) {
        playback.atmosphereVolume = clampVolume(playback.atmosphereVolume + delta)
    }

    private func adjustSoundEffectsVolume(by delta: Double) {
        playback.sfxVolume = clampVolume(playback.sfxVolume + delta)
    }

    private func clampVolume(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func consumePendingWindowRequests() {
        openAboutWindowIfNeeded()
        openSettingsWindowIfNeeded()
        openPlaylistWindowIfNeeded()
        openAtmosphereWindowIfNeeded()
        openSoundEffectsWindowIfNeeded()
        openImportWindowIfNeeded()
        openAddPlaylistWindowIfNeeded()
    }

    private func openAboutWindowIfNeeded() {
        guard menuState.showAbout else { return }
        openWindow(id: CantusWindowID.about)
        menuState.showAbout = false
    }

    private func openSettingsWindowIfNeeded() {
        guard menuState.showSettings else { return }
        openWindow(id: CantusWindowID.settings)
        menuState.showSettings = false
    }

    private func openPlaylistWindowIfNeeded() {
        guard menuState.showPlaylistPanel else { return }
        openWindow(value: PlaylistPanelWindowPayload(initialFilter: menuState.playlistPanelInitialFilter))
        menuState.playlistPanelInitialFilter = nil
        menuState.showPlaylistPanel = false
    }

    private func openAtmosphereWindowIfNeeded() {
        guard menuState.showAtmospherePanel else { return }
        openWindow(id: CantusWindowID.atmospheres)
        menuState.showAtmospherePanel = false
    }

    private func openSoundEffectsWindowIfNeeded() {
        guard menuState.showSoundboardPanel else { return }
        openWindow(id: CantusWindowID.soundEffects)
        menuState.showSoundboardPanel = false
    }

    private func openImportWindowIfNeeded() {
        guard let request = menuState.importRequest else { return }
        openWindow(value: ImportAssetWindowPayload(fileURL: request.fileURL, initialKind: request.initialKind))
        menuState.importRequest = nil
    }

    private func openAddPlaylistWindowIfNeeded() {
        guard menuState.showAddPlaylistSheet else { return }
        openWindow(value: AddPlaylistWindowPayload(preferredTab: menuState.addPlaylistPreferredTab))
        menuState.showAddPlaylistSheet = false
    }
}
