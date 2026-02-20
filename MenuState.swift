import Foundation

@available(iOS 18.0, *)
@MainActor
final class AppMenuState: ObservableObject {
    @Published var showAbout = false
    @Published var showSettings = false
    @Published var showPlaylistPanel = false
    @Published var playlistPanelInitialFilter: PlaylistPanelView.InitialFilter? = nil
    @Published var showAtmospherePanel = false
    @Published var showSoundboardPanel = false
    @Published var showAddPlaylistSheet = false
    @Published var addPlaylistPreferredTab: PlaylistAddSheetView.Tab = .local
    @Published var importRequest: ImportAssetsRequest?
    @Published var showVolumeSliders = true
    @Published var showPlaylists = true
    @Published var showAtmospheres = true
    @Published var showSoundEffects = true
    @Published var pendingSettingsAction: SettingsMenuAction? = nil
    @Published var quickPlayRequested = false
    @Published var replayTourRequestToken: UUID? = nil
    @Published var showFastImportTourTip = false

    func closePanelsAndSheets() {
        showAbout = false
        showSettings = false
        showPlaylistPanel = false
        playlistPanelInitialFilter = nil
        showAtmospherePanel = false
        showSoundboardPanel = false
        showAddPlaylistSheet = false
    }

    func triggerQuickPlay() {
        // Force an edge transition so onChange handlers fire every time.
        quickPlayRequested = false
        DispatchQueue.main.async {
            self.quickPlayRequested = true
        }
    }

    func requestTourReplay() {
        DispatchQueue.main.async {
            self.replayTourRequestToken = UUID()
        }
    }

    func presentAbout() {
        closePanelsAndSheets()
        DispatchQueue.main.async {
            self.showAbout = true
        }
    }

    func presentSettings(action: SettingsMenuAction? = nil) {
        closePanelsAndSheets()
        DispatchQueue.main.async {
            self.pendingSettingsAction = action
            self.showSettings = true
        }
    }

    func presentPlaylistPanel(initialFilter: PlaylistPanelView.InitialFilter? = nil) {
        closePanelsAndSheets()
        DispatchQueue.main.async {
            self.playlistPanelInitialFilter = initialFilter
            self.showPlaylistPanel = true
        }
    }

    func presentAtmospherePanel() {
        closePanelsAndSheets()
        DispatchQueue.main.async {
            self.showAtmospherePanel = true
        }
    }

    func presentSoundboardPanel() {
        closePanelsAndSheets()
        DispatchQueue.main.async {
            self.showSoundboardPanel = true
        }
    }

    func presentAddPlaylist(preferredTab: PlaylistAddSheetView.Tab) {
        closePanelsAndSheets()
        DispatchQueue.main.async {
            self.addPlaylistPreferredTab = preferredTab
            self.showAddPlaylistSheet = true
        }
    }

    func presentImport(initialKind: AssetKind?) {
        presentImport(fileURL: nil, initialKind: initialKind)
    }

    func presentImport(fileURL: URL?, initialKind: AssetKind?) {
        closePanelsAndSheets()
        DispatchQueue.main.async {
            self.importRequest = ImportAssetsRequest(fileURL: fileURL, initialKind: initialKind)
        }
    }
}

@available(iOS 18.0, *)
enum SettingsMenuAction: Equatable {
    case importLibrary
    case exportLibrary
}

@available(iOS 18.0, *)
struct ImportAssetsRequest: Identifiable, Equatable {
    let id = UUID()
    let fileURL: URL?
    let initialKind: AssetKind?
}

enum CantusWindowID {
    static let about = "about"
    static let settings = "settings"
    static let atmospheres = "atmospheres"
    static let soundEffects = "soundEffects"
}

struct PlaylistPanelWindowPayload: Hashable, Codable {
    let initialFilter: PlaylistPanelView.InitialFilter?

    init(initialFilter: PlaylistPanelView.InitialFilter? = nil) {
        self.initialFilter = initialFilter
    }
}

struct ImportAssetWindowPayload: Hashable, Codable {
    let fileURL: URL?
    let initialKind: AssetKind?

    init(fileURL: URL? = nil, initialKind: AssetKind? = nil) {
        self.fileURL = fileURL
        self.initialKind = initialKind
    }
}

struct AddPlaylistWindowPayload: Hashable, Codable {
    let preferredTabRawValue: Int

    init(preferredTab: PlaylistAddSheetView.Tab) {
        self.preferredTabRawValue = preferredTab.rawValue
    }

    var preferredTab: PlaylistAddSheetView.Tab {
        PlaylistAddSheetView.Tab(rawValue: preferredTabRawValue) ?? .local
    }
}

struct EditAssetWindowPayload: Hashable, Codable {
    let itemId: String
    let title: String
    let kindRawValue: String

    init(itemId: String, title: String, kind: LibraryKind) {
        self.itemId = itemId
        self.title = title
        self.kindRawValue = kind.rawValue
    }

    var kind: LibraryKind {
        LibraryKind(rawValue: kindRawValue) ?? .atmosphere
    }
}

struct EditPlaylistWindowPayload: Hashable, Codable {
    let itemId: String
    let title: String

    init(itemId: String, title: String) {
        self.itemId = itemId
        self.title = title
    }
}

extension Notification.Name {
    static let cantusLibraryDidChange = Notification.Name("CantusLibraryDidChange")
}

enum LibraryChangeNotifier {
    static func notify() {
        NotificationCenter.default.post(name: .cantusLibraryDidChange, object: nil)
    }
}
