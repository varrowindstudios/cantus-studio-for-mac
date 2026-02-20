import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

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
#if os(macOS)
                .frame(minHeight: 600)
#endif
#if os(macOS)
                .background(
                    MainPlayWindowToolbarConfigurator(
                        onOpenSettings: { menuState.presentSettings() },
                        onNewLocalPlaylist: { menuState.presentAddPlaylist(preferredTab: .local) },
                        onAddAppleMusicPlaylist: { menuState.presentAddPlaylist(preferredTab: .appleMusic) },
                        onImportAtmosphere: { menuState.presentImport(initialKind: .atmosphere) },
                        onImportSoundEffect: { menuState.presentImport(initialKind: .sfx) }
                    )
                )
#endif
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

#if os(macOS)
private struct MainPlayWindowToolbarConfigurator: NSViewRepresentable {
    let onOpenSettings: () -> Void
    let onNewLocalPlaylist: () -> Void
    let onAddAppleMusicPlaylist: () -> Void
    let onImportAtmosphere: () -> Void
    let onImportSoundEffect: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onOpenSettings = onOpenSettings
        context.coordinator.onNewLocalPlaylist = onNewLocalPlaylist
        context.coordinator.onAddAppleMusicPlaylist = onAddAppleMusicPlaylist
        context.coordinator.onImportAtmosphere = onImportAtmosphere
        context.coordinator.onImportSoundEffect = onImportSoundEffect

        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            coordinator?.attach(to: nsView.window)
        }
    }

    final class Coordinator: NSObject, NSToolbarDelegate {
        var onOpenSettings: (() -> Void)?
        var onNewLocalPlaylist: (() -> Void)?
        var onAddAppleMusicPlaylist: (() -> Void)?
        var onImportAtmosphere: (() -> Void)?
        var onImportSoundEffect: (() -> Void)?

        private weak var attachedWindow: NSWindow?
        private let toolbarIdentifier = NSToolbar.Identifier("cantus.main.play.window.toolbar")
        private let settingsIdentifier = NSToolbarItem.Identifier("cantus.main.play.window.toolbar.settings")
        private let addIdentifier = NSToolbarItem.Identifier("cantus.main.play.window.toolbar.add")

        func attach(to window: NSWindow?) {
            guard let window else { return }

            if attachedWindow !== window || window.toolbar?.identifier != toolbarIdentifier {
                let toolbar = NSToolbar(identifier: toolbarIdentifier)
                toolbar.delegate = self
                toolbar.displayMode = .iconOnly
                toolbar.allowsUserCustomization = false
                toolbar.autosavesConfiguration = false
                window.toolbar = toolbar
                attachedWindow = window
            } else {
                window.toolbar?.delegate = self
            }

            if window.titleVisibility != .hidden {
                window.titleVisibility = .hidden
            }
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [settingsIdentifier, .flexibleSpace, addIdentifier]
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [settingsIdentifier, .flexibleSpace, addIdentifier]
        }

        func toolbar(
            _ toolbar: NSToolbar,
            itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar flag: Bool
        ) -> NSToolbarItem? {
            switch itemIdentifier {
            case settingsIdentifier:
                return makeSettingsItem()
            case addIdentifier:
                return makeAddMenuItem()
            default:
                return nil
            }
        }

        private func makeSettingsItem() -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: settingsIdentifier)
            item.label = "Settings"
            item.paletteLabel = "Settings"
            item.toolTip = "Settings"
            item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
            item.target = self
            item.action = #selector(handleOpenSettings)
            return item
        }

        private func makeAddMenuItem() -> NSToolbarItem {
            if #available(macOS 11.0, *) {
                let item = NSMenuToolbarItem(itemIdentifier: addIdentifier)
                item.label = "Add"
                item.paletteLabel = "Add"
                item.toolTip = "Add"
                item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")
                item.menu = makeAddMenu()
                item.showsIndicator = false
                item.minSize = NSSize(width: 36, height: 30)
                item.maxSize = NSSize(width: 36, height: 30)
                return item
            }

            let item = NSToolbarItem(itemIdentifier: addIdentifier)
            item.label = "Add"
            item.paletteLabel = "Add"
            item.toolTip = "Add"
            let button = NSButton(
                image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Add") ?? NSImage(),
                target: self,
                action: #selector(handleShowAddMenu(_:))
            )
            button.imagePosition = .imageOnly
            button.isBordered = true
            button.bezelStyle = .circular
            button.setButtonType(.momentaryPushIn)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 30).isActive = true
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
            item.view = button
            item.minSize = NSSize(width: 30, height: 30)
            item.maxSize = NSSize(width: 30, height: 30)
            return item
        }

        private func makeAddMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false

            let newLocal = NSMenuItem(title: "New Local Playlist", action: #selector(handleNewLocalPlaylist), keyEquivalent: "")
            newLocal.target = self
            menu.addItem(newLocal)

            let addAppleMusic = NSMenuItem(title: "Add Apple Music Playlist", action: #selector(handleAddAppleMusicPlaylist), keyEquivalent: "")
            addAppleMusic.target = self
            menu.addItem(addAppleMusic)

            let importAtmosphere = NSMenuItem(title: "Import Atmosphere", action: #selector(handleImportAtmosphere), keyEquivalent: "")
            importAtmosphere.target = self
            menu.addItem(importAtmosphere)

            let importSoundEffect = NSMenuItem(title: "Import Sound Effect", action: #selector(handleImportSoundEffect), keyEquivalent: "")
            importSoundEffect.target = self
            menu.addItem(importSoundEffect)

            return menu
        }

        @objc
        private func handleOpenSettings() {
            onOpenSettings?()
        }

        @objc
        private func handleShowAddMenu(_ sender: Any?) {
            guard let button = sender as? NSButton else { return }
            let menu = makeAddMenu()
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -2), in: button)
        }

        @objc
        private func handleNewLocalPlaylist() {
            onNewLocalPlaylist?()
        }

        @objc
        private func handleAddAppleMusicPlaylist() {
            onAddAppleMusicPlaylist?()
        }

        @objc
        private func handleImportAtmosphere() {
            onImportAtmosphere?()
        }

        @objc
        private func handleImportSoundEffect() {
            onImportSoundEffect?()
        }
    }
}
#endif
