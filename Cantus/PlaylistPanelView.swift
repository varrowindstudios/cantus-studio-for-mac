import SwiftUI
import MusicKit
import UniformTypeIdentifiers

@available(iOS 18.0, *)
struct PlaylistPanelView: View {
    struct InitialFilter: Equatable, Hashable, Codable {
        enum Category: String, Equatable, Hashable, Codable {
            case theme
            case location
            case mood
        }

        let category: Category
        let tagName: String
    }

    @State private var selectedTab = 0
    @State private var searchText = ""
    @Environment(\.openWindow) private var openWindow
    @State private var showPremiumUpgrade = false
    @State private var facets: FacetCounts?
    @State private var isLoading = false
    @State private var selectedTag: TagOption?
    @State private var taggedItems: [LibraryItemRow] = []
    @State private var isLoadingItems = false
    @State private var allItems: [LibraryItemRow] = []
    @State private var isLoadingAll = false
    @State private var searchResults: [LibraryItemRow] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var refreshToken = UUID()
    @State private var editTarget: EditTarget?
    @State private var deleteTarget: DeleteTarget?
    @State private var showDeleteAlert = false
    @State private var playlistSources: [String: PlaylistSource] = [:]
    @State private var didApplyInitialFilter = false
    @State private var isApplyingInitialFilter = false

    private let initialFilter: InitialFilter?

    @EnvironmentObject private var premium: PremiumStore
    @EnvironmentObject private var theme: ThemeModel
    @EnvironmentObject private var backend: AppBackend
    @EnvironmentObject private var musicPlayback: MusicPlaybackStore
    @EnvironmentObject private var bookmarks: BookmarksStore
    @EnvironmentObject private var playback: PlaybackStateStore

    private enum SortCategory: Int, CaseIterable {
        case all = 0
        case theme = 1
        case location = 2
        case mood = 3

        var label: String {
            switch self {
            case .all: return "All"
            case .theme: return "Theme"
            case .location: return "Location"
            case .mood: return "Mood"
            }
        }
    }

    private var selectedCategory: SortCategory {
        SortCategory(rawValue: selectedTab) ?? .all
    }

    init(initialFilter: InitialFilter? = nil) {
        self.initialFilter = initialFilter
    }

    var body: some View {
        PanelShell(
            title: "Playlists",
            searchPlaceholder: "Search Playlists",
            tabs: SortCategory.allCases.map(\.label),
            selectedTab: $selectedTab,
            searchText: $searchText,
            trailingToolbar: {
                ToolbarIconButton(
                    systemName: "plus",
                    action: {
                        openWindow(value: AddPlaylistWindowPayload(preferredTab: .local))
                    },
                    accessibilityLabel: "Add Playlist"
                )
            }
        ) {
            if isSearching || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if isSearching {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if searchResults.isEmpty {
                    Text("No matches")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(searchResults, id: \.id) { item in
                        playlistRow(item)
                            .listRowSeparator(.hidden)
                    }
                }
            } else if selectedCategory == .all {
                if isLoadingAll {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if allItems.isEmpty {
                    Text("No playlists yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(allItems, id: \.id) { item in
                        playlistRow(item)
                            .listRowSeparator(.hidden)
                    }
                }
            } else if let selectedTagValue = selectedTag {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                    Text(selectedTagValue.name)
                        .font(.headline)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { selectedTag = nil }
                .foregroundStyle(.secondary)
                .listRowSeparator(.hidden)

                if isLoadingItems {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if taggedItems.isEmpty {
                    Text("No playlists yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(taggedItems, id: \.id) { item in
                        playlistRow(item)
                            .listRowSeparator(.hidden)
                    }
                }
            } else if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else {
                let options = tagOptions(for: selectedCategory)
                if options.isEmpty {
                    if allTagOption(for: selectedCategory) != nil {
                        if isLoadingItems {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            taggedItemsList
                        }
                    } else {
                        Text("No tags available.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(options) { option in
                        HStack {
                            Text(option.name)
                                .font(.body)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTag = option }
                    }
                }
            }
        }
        .task(id: refreshToken) {
            await loadFacets()
            await loadPlaylistSources()
            applyInitialFilterIfNeeded()
            if selectedCategory == .all {
                await loadAllItems()
            } else {
                await loadFallbackItemsIfNeeded()
            }
        }
        .onChange(of: selectedTab) { _, _ in
            if isApplyingInitialFilter {
                isApplyingInitialFilter = false
                return
            }
            selectedTag = nil
            taggedItems = []
            if selectedCategory == .all {
                Task { await loadAllItems() }
            } else {
                Task { await loadFallbackItemsIfNeeded() }
            }
        }
        .onChange(of: searchText) { _, newValue in
            let term = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            searchTask?.cancel()
            if term.isEmpty {
                searchResults = []
                isSearching = false
                return
            }
            isSearching = true
            searchTask = Task { [term] in
                try? await Task.sleep(nanoseconds: 200_000_000)
                await performSearch(term: term)
            }
        }
        .onChange(of: selectedTag) { _, newValue in
            guard let newValue else { return }
            Task { await loadItems(for: newValue) }
        }
        .alert("Remove Playlist?", isPresented: $showDeleteAlert, presenting: deleteTarget) { target in
            Button("Remove", role: .destructive) {
                Task { await deleteItem(target) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text("Remove \(target.title) from the library?")
        }
        .sheet(isPresented: $showPremiumUpgrade) {
            PremiumUpgradeView()
                .environmentObject(theme)
                .environmentObject(premium)
        }
        .onChange(of: editTarget?.id) { _, _ in
            guard let target = editTarget else { return }
            openWindow(value: EditPlaylistWindowPayload(itemId: target.itemId, title: target.title))
            editTarget = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .cantusLibraryDidChange)) { _ in
            refreshToken = UUID()
        }
    }

    private func playlistRow(_ item: LibraryItemRow) -> some View {
        let source = playlistSources[item.id] ?? .local
        let isLocal = source == .local
        let canPlay = isLocal || premium.isPremium
        let isPremium = premium.isPremium
        return PanelRow(
            title: item.title,
            icon: "play.fill",
            isBookmarked: bookmarks.isPlaylistBookmarked(item.title),
            toggleBookmark: { bookmarks.togglePlaylist(item.title) },
            isPlaying: musicPlayback.isPlayingPlaylist(item.id),
            togglePlay: {
                if isLocal {
                    Task { await musicPlayback.togglePlaylist(itemId: item.id, title: item.title) }
                } else if isPremium {
                    Task { await musicPlayback.togglePlaylist(itemId: item.id, title: item.title) }
                } else {
                    showPremiumUpgrade = true
                }
            },
            isBookmarkDisabled: false,
            containsMusic: false,
            badgeText: source.label,
            infoView: {
                TagInfoPopover(itemId: item.id, title: item.title)
                    .environmentObject(backend)
                    .environmentObject(theme)
            },
            recencyText: recencyText(for: item),
            isDimmed: !canPlay
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteTarget = DeleteTarget(itemId: item.id, title: item.title)
                showDeleteAlert = true
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .tint(theme.headerColor)
        }
        .contextMenu {
            Button {
                if bookmarks.isPlaylistBookmarked(item.title) {
                    bookmarks.togglePlaylist(item.title)
                } else {
                    bookmarks.togglePlaylist(item.title)
                }
            } label: {
                Label(
                    bookmarks.isPlaylistBookmarked(item.title) ? "Remove Bookmark" : "Bookmark this playlist",
                    systemImage: bookmarks.isPlaylistBookmarked(item.title) ? "bookmark.slash" : "bookmark"
                )
            }
            Button {
                editTarget = EditTarget(itemId: item.id, title: item.title)
            } label: {
                Label("Edit properties", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleteTarget = DeleteTarget(itemId: item.id, title: item.title)
                showDeleteAlert = true
            } label: {
                Label("Remove this playlist", systemImage: "trash")
            }
        }
    }

    private func recencyText(for item: LibraryItemRow) -> String? {
        if musicPlayback.isPlayingPlaylist(item.id) {
            return nil
        }
        guard let lastPlayed = playback.lastPlayedPlaylist(item.title) else { return nil }
        let interval = max(0, Date().timeIntervalSince(lastPlayed))
        return formatRecency(interval: interval)
    }

    private func formatRecency(interval: TimeInterval) -> String {
        let minute: TimeInterval = 60
        let hour: TimeInterval = 3600
        let day: TimeInterval = 86400
        let month: TimeInterval = 30 * day

        if interval < minute {
            return "Just now"
        } else if interval < hour {
            let minutes = max(1, Int(round(interval / minute)))
            return "\(minutes)min ago"
        } else if interval < day {
            let hours = max(1, Int(round(interval / hour)))
            return "\(hours)hr ago"
        } else if interval < month {
            let days = max(1, Int(round(interval / day)))
            return "\(days)d ago"
        } else {
            let months = max(1, Int(round(interval / month)))
            return "\(months)mo ago"
        }
    }

    private struct TagOption: Identifiable, Equatable {
        let id: Int64
        let name: String
        let count: Int
    }

    private func tagOptions(for category: SortCategory) -> [TagOption] {
        guard let facets else { return [] }
        let source: [(TagValue, Int)]
        switch category {
        case .all:
            return []
        case .theme:
            source = facets.musicThemes
        case .location:
            source = facets.locations
        case .mood:
            source = facets.moods
        }
        return source
            .filter { $0.0.name != "All" }
            .map { TagOption(id: $0.0.id, name: $0.0.name, count: $0.1) }
    }

    private func allTagOption(for category: SortCategory) -> TagOption? {
        guard let facets else { return nil }
        let source: [(TagValue, Int)]
        switch category {
        case .all:
            return nil
        case .theme:
            source = facets.musicThemes
        case .location:
            source = facets.locations
        case .mood:
            source = facets.moods
        }
        guard let match = source.first(where: { $0.0.name == "All" }) else { return nil }
        return TagOption(id: match.0.id, name: match.0.name, count: match.1)
    }

    private func filter(for category: SortCategory, tagId: Int64) -> Filters {
        var filters = Filters()
        switch category {
        case .all:
            return filters
        case .theme:
            filters.musicThemeIDs = [tagId]
        case .location:
            filters.locationIDs = [tagId]
        case .mood:
            filters.moodIDs = [tagId]
        }
        return filters
    }

    private func loadItems(for option: TagOption) async {
        isLoadingItems = true
        let filters = filter(for: selectedCategory, tagId: option.id)
        do {
            taggedItems = try await backend.libraryRepository.fetchItems(kind: .music, filters: filters, sort: .titleAsc)
        } catch {
            taggedItems = []
        }
        isLoadingItems = false
    }

    private func loadFallbackItemsIfNeeded() async {
        guard selectedCategory != .all else { return }
        guard tagOptions(for: selectedCategory).isEmpty,
              let allTag = allTagOption(for: selectedCategory) else { return }
        await loadItems(for: allTag)
    }

    private func loadAllItems() async {
        guard !isLoadingAll else { return }
        isLoadingAll = true
        do {
            allItems = try await backend.libraryRepository.fetchItems(kind: .music, filters: Filters(), sort: .titleAsc)
        } catch {
            allItems = []
        }
        isLoadingAll = false
    }

    private func loadFacets() async {
        guard !isLoading else { return }
        isLoading = true
        do {
            await backend.seedIfNeeded()
            facets = try await backend.facetRepository.facetCounts(kind: .music, filters: Filters())
        } catch {
            facets = nil
        }
        isLoading = false
    }

    private func loadPlaylistSources() async {
        do {
            playlistSources = try await backend.musicRepository.playlistSourceMap()
        } catch {
            playlistSources = [:]
        }
    }

    private func applyInitialFilterIfNeeded() {
        guard !didApplyInitialFilter, let initialFilter else { return }
        guard facets != nil else { return }
        didApplyInitialFilter = true
        isApplyingInitialFilter = true

        let tabIndex: Int
        switch initialFilter.category {
        case .theme: tabIndex = SortCategory.theme.rawValue
        case .location: tabIndex = SortCategory.location.rawValue
        case .mood: tabIndex = SortCategory.mood.rawValue
        }
        selectedTab = tabIndex

        let targetOptions = tagOptions(for: SortCategory(rawValue: tabIndex) ?? .all)
        if let match = targetOptions.first(where: { $0.name.caseInsensitiveCompare(initialFilter.tagName) == .orderedSame }) {
            selectedTag = match
        } else if let allTag = allTagOption(for: SortCategory(rawValue: tabIndex) ?? .all),
                  initialFilter.tagName == allTag.name {
            selectedTag = allTag
        }
    }

    private func performSearch(term: String) async {
        do {
            searchResults = try await backend.libraryRepository.searchItems(kind: .music, query: term, filters: Filters())
        } catch {
            searchResults = []
        }
        isSearching = false
    }

    @ViewBuilder
    private var taggedItemsList: some View {
        ForEach(taggedItems, id: \.id) { item in
            playlistRow(item)
                .listRowSeparator(.hidden)
        }
    }

    private func deleteItem(_ target: DeleteTarget) async {
        guard let uuid = UUID(uuidString: target.itemId) else { return }
        do {
            try await backend.libraryRepository.deleteItem(itemId: uuid)
            await MainActor.run {
                bookmarks.removePlaylistBookmark(target.title)
                playback.removeRecentPlaylist(target.title)
                if selectedCategory == .all {
                    allItems.removeAll { $0.id == target.itemId }
                } else {
                    taggedItems.removeAll { $0.id == target.itemId }
                }
                searchResults.removeAll { $0.id == target.itemId }
                playlistSources[target.itemId] = nil
                showDeleteAlert = false
                LibraryChangeNotifier.notify()
            }
        } catch {
            await MainActor.run {
                showDeleteAlert = false
            }
        }
    }

}

private struct EditTarget: Identifiable {
    let itemId: String
    let title: String
    var id: String { itemId }
}

private struct DeleteTarget: Identifiable {
    let itemId: String
    let title: String
    var id: String { itemId }
}

@available(iOS 18.0, *)
private struct AppleMusicPlaylistPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeModel
    @EnvironmentObject private var backend: AppBackend
    @EnvironmentObject private var premium: PremiumStore
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var playlists: [Playlist] = []
    @State private var selectedPlaylist: PlaylistSelection?

    let onPlaylistAdded: () -> Void
    var embedded: Bool = false
    var onSelect: ((PlaylistSelection) -> Void)? = nil

    var body: some View {
        Group {
            if embedded {
                pickerSections
            } else {
                NavigationStack {
                    List {
                        pickerSections
                    }
                    .cantusInsetGroupedListStyle()
                    .navigationTitle("Add Apple Music Playlist")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            ToolbarIconButton(systemName: "xmark", action: { dismiss() }, accessibilityLabel: "Close")
                        }
                        }
                }
            }
        }
        .task { await loadPlaylists() }
        .sheet(item: embedded ? .constant(nil) : $selectedPlaylist) { selection in
            PlaylistImportView(playlist: selection.playlist) {
                dismiss()
                onPlaylistAdded()
            }
            .environmentObject(theme)
            .environmentObject(backend)
        }
    }

    @ViewBuilder
    private var pickerSections: some View {
        Section {
            SearchField(text: $searchText, prompt: "Search your playlists")
        }
        .listRowBackground(Color.clear)

        Section {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.secondary)
            } else if filteredPlaylists.isEmpty {
                Text("No playlists found")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredPlaylists) { playlist in
                    if embedded, let onSelect {
                        Button {
                            onSelect(PlaylistSelection(playlist: playlist))
                        } label: {
                            HStack {
                                Text(playlist.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Button {
                            selectedPlaylist = PlaylistSelection(playlist: playlist)
                        } label: {
                            HStack {
                                Text(playlist.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(theme.color)
                            }
                        }
                    }
                }
            }
        }
    }

    private var filteredPlaylists: [Playlist] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return playlists }
        return playlists.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func loadPlaylists() async {
        isLoading = true
        errorMessage = nil
        guard premium.isPremium else {
            errorMessage = "Premium is required to access Apple Music playlists."
            isLoading = false
            return
        }
        let status = MusicAuthorization.currentStatus
        if status != .authorized {
            errorMessage = "Apple Music access is required. Enable it in Settings."
            isLoading = false
            return
        }
        do {
            let request = MusicLibraryRequest<Playlist>()
            let response = try await request.response()
            playlists = Array(response.items)
        } catch {
            errorMessage = "Could not load Apple Music playlists."
        }
        isLoading = false
    }
}

private struct PlaylistSelection: Identifiable, Hashable {
    let id: MusicItemID
    let playlist: Playlist

    init(playlist: Playlist) {
        self.playlist = playlist
        self.id = playlist.id
    }

    static func == (lhs: PlaylistSelection, rhs: PlaylistSelection) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct EmbeddedGlassModifier: ViewModifier {
    let isEmbedded: Bool

    func body(content: Content) -> some View {
        if isEmbedded {
            content
        } else {
            content.background(.thinMaterial, in: .rect(cornerRadius: 28))
        }
    }
}

@available(iOS 18.0, *)
struct PlaylistAddSheetView: View {
    enum Tab: Int, CaseIterable {
        case appleMusic = 0
        case local = 1

        var title: String {
            switch self {
            case .appleMusic: return "Apple Music"
            case .local: return "Local"
            }
        }

        var addSheetTitle: String {
            switch self {
            case .appleMusic: return "Add Apple Music Playlist"
            case .local: return "New Local Playlist"
            }
        }
    }

    let isPremium: Bool
    let onRequestUpgrade: () -> Void
    let onPlaylistAdded: () -> Void
    @Binding var preferredTab: Tab

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Tab? = .local
    @State private var canSaveLocal = false
    @State private var saveLocalTrigger = false
    @State private var selectedApplePlaylist: PlaylistSelection?

    @EnvironmentObject private var theme: ThemeModel
    @EnvironmentObject private var backend: AppBackend

    init(
        isPremium: Bool,
        onRequestUpgrade: @escaping () -> Void,
        onPlaylistAdded: @escaping () -> Void,
        preferredTab: Binding<Tab>,
        showsTypeChooserInitially: Bool = false
    ) {
        self.isPremium = isPremium
        self.onRequestUpgrade = onRequestUpgrade
        self.onPlaylistAdded = onPlaylistAdded
        self._preferredTab = preferredTab
        _selectedTab = State(initialValue: showsTypeChooserInitially ? nil : preferredTab.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: sectionHeader("Type")) {
                    Picker("", selection: $selectedTab) {
                        Text("Choose a Type")
                            .tag(Tab?.none)
                        ForEach(Tab.allCases, id: \.self) { tab in
                            Text(tab.title)
                                .tag(Optional(tab))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(theme.color)
                    .foregroundStyle(theme.color)
                }
                .listRowBackground(Rectangle().fill(.thinMaterial))

                switch selectedTab {
                case .appleMusic:
                    if isPremium {
                        AppleMusicPlaylistPickerView(
                            onPlaylistAdded: onPlaylistAdded,
                            embedded: true,
                            onSelect: { selection in
                                selectedApplePlaylist = selection
                            }
                        )
                    } else {
                        Section {
                            VStack(spacing: 12) {
                                Text("Apple Music playlists require Premium.")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                Button("Upgrade to Premium") {
                                    preferredTab = .appleMusic
                                    onRequestUpgrade()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .listRowBackground(Rectangle().fill(.thinMaterial))
                    }
                case .local:
                    LocalPlaylistCreateView(
                        onPlaylistAdded: onPlaylistAdded,
                        embedded: true,
                        externalSaveTrigger: $saveLocalTrigger,
                        onCanSaveChange: { canSaveLocal = $0 }
                    )
                case nil:
                    Section {
                        Text("Choose a playlist type to continue.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Rectangle().fill(.thinMaterial))
                }
            }
            .cantusInsetGroupedListStyle()
            .navigationTitle(selectedTab?.addSheetTitle ?? "Add New Playlist")
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarIconButton(systemName: "xmark", action: { dismiss() }, accessibilityLabel: "Close")
                }
#endif
                if selectedTab == .local, canSaveLocal {
                    ToolbarItem(placement: .confirmationAction) {
                        ToolbarIconButton(systemName: "checkmark", action: { saveLocalTrigger = true }, accessibilityLabel: "Save")
                    }
                }
            }
            .navigationDestination(item: $selectedApplePlaylist) { selection in
                PlaylistImportView(playlist: selection.playlist) {
                    selectedApplePlaylist = nil
                    onPlaylistAdded()
                }
                .environmentObject(theme)
                .environmentObject(backend)
            }
        }
#if os(iOS)
        .background(.thinMaterial, in: .rect(cornerRadius: 28))
#endif
        .onChange(of: preferredTab) { _, newValue in
            selectedTab = newValue
        }
        .onChange(of: selectedTab) { _, newValue in
            if let newValue {
                preferredTab = newValue
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

@available(iOS 18.0, *)
private struct LocalPlaylistCreateView: View {
    let onPlaylistAdded: () -> Void
    var embedded: Bool = false
    var externalSaveTrigger: Binding<Bool>? = nil
    var onCanSaveChange: ((Bool) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeModel
    @EnvironmentObject private var backend: AppBackend

    @State private var playlistName: String = ""
    @State private var trackURLs: [URL] = []
    @State private var showFilePicker = false
#if os(iOS)
    @State private var editMode: EditMode = .inactive
#else
    @State private var isReordering = false
#endif
    @State private var catalog = TagCatalog(
        locations: [],
        moods: [],
        musicThemes: [],
        atmosphereThemes: [],
        sfxThemes: [],
        creatureTypes: []
    )
    @State private var selectedTags: Set<TagSelection> = []
    @State private var isLoadingTags = false
    @State private var showAddTag = false
    @State private var newTagName = ""
    @State private var newTagCategory: TagCategory = .musicTheme
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let allowedCategories: [TagCategory] = [.musicTheme, .location, .mood]
    
#if os(iOS)
    private var isReorderingActive: Bool { editMode == .active }
#else
    private var isReorderingActive: Bool { isReordering }
#endif

    var body: some View {
        Group {
            if embedded {
                createSections
            } else {
                NavigationStack {
                    List {
                        createSections
                    }
                    .cantusInsetGroupedListStyle()
                        .navigationTitle("Create Local Playlist")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                ToolbarIconButton(systemName: "xmark", action: { dismiss() }, accessibilityLabel: "Close")
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                ToolbarIconButton(systemName: "checkmark", action: { handleSave() }, accessibilityLabel: "Save")
                                    .disabled(isSaving || playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || trackURLs.isEmpty)
                            }
                        }
                }
            }
        }
        .modifier(EmbeddedGlassModifier(isEmbedded: embedded))
#if os(iOS)
        .environment(\.editMode, $editMode)
#endif
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let newUrls = urls.filter { !trackURLs.contains($0) }
                trackURLs.append(contentsOf: newUrls)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("Playlist Error", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
        .task { await loadTags() }
        .onChange(of: playlistName) { _, _ in
            notifyCanSave()
        }
        .onChange(of: trackURLs) { _, _ in
            notifyCanSave()
        }
        .onChange(of: isSaving) { _, _ in
            notifyCanSave()
        }
        .onChange(of: externalSaveTrigger?.wrappedValue ?? false) { _, newValue in
            guard newValue else { return }
            handleSave()
            externalSaveTrigger?.wrappedValue = false
        }
        .sheet(isPresented: $showAddTag) {
            AddTagSheet(
                name: $newTagName,
                category: $newTagCategory,
                allowedCategories: allowedCategories,
                title: "Add Playlist Tag",
                onCancel: { showAddTag = false },
                onSave: { saveNewTag() }
            )
        }
    }

    @ViewBuilder
    private var createSections: some View {
        Section(header: sectionHeader("Name")) {
            TextField("Playlist Name", text: $playlistName)
                .font(.body)
        }
        .listRowBackground(Rectangle().fill(.thinMaterial))

        Section(header: trackHeader) {
            if trackURLs.isEmpty {
                Text("Choose audio files to add to this playlist.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Rectangle().fill(.thinMaterial))
            } else {
                ForEach(trackURLs, id: \.self) { url in
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.body)
                        .listRowBackground(Rectangle().fill(.thinMaterial))
                }
                .onDelete(perform: removeTracks)
                .onMove(perform: moveTracks)
            }
        }

        Section(header: tagHeader) {
            if isLoadingTags {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Rectangle().fill(.thinMaterial))
            } else {
                ForEach(visibleTagSections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        PlaylistTagRowView(
                            category: section.category,
                            tags: section.tags,
                            selected: selectedTags,
                            isAllSelected: isAllSelected(in: section.category),
                            onToggle: toggleTag
                        )
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Rectangle().fill(.thinMaterial))
                }
            }
        }
    }

    private func notifyCanSave() {
        onCanSaveChange?(canSave)
    }

    private var canSave: Bool {
        !isSaving && !playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !trackURLs.isEmpty
    }

    private var trackHeader: some View {
        HStack {
            Text("Tracks")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: { showFilePicker = true }) {
                Image(systemName: "plus")
                    .frame(width: 32, height: 32)
                    .cantusGlassEffectClear(in: Circle())
            }
            .buttonStyle(.plain)
            Button(action: toggleEditMode) {
                Image(systemName: isReorderingActive ? "checkmark" : "arrow.up.arrow.down")
                    .frame(width: 32, height: 32)
                    .cantusGlassEffectClear(in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var tagHeader: some View {
        HStack {
            sectionHeader("Tags")
            Spacer()
            Button(action: { showAddTag = true }) {
                Image(systemName: "plus")
                    .frame(width: 32, height: 32)
                    .cantusGlassEffectClear(in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var visibleTagSections: [TagSection] {
        return allowedCategories.compactMap { category in
            let filtered = tags(for: category)
            guard !filtered.isEmpty else { return nil }
            return TagSection(
                category: category,
                title: category.label,
                tags: filtered
            )
        }
    }

    private func tags(for category: TagCategory) -> [TagValue] {
        let source: [TagValue]
        switch category {
        case .location:
            source = catalog.locations
        case .mood:
            source = catalog.moods
        case .musicTheme:
            source = catalog.musicThemes
        case .atmosphereTheme:
            source = catalog.atmosphereThemes
        case .sfxTheme:
            source = catalog.sfxThemes
        case .creatureType:
            source = catalog.creatureTypes
        }
        var filtered = source
        if let allTag = source.first(where: isAllTag) {
            filtered.removeAll { $0.id == allTag.id }
            filtered.insert(allTag, at: 0)
        }
        return sortTags(filtered, category: category)
    }

    private func toggleTag(_ tag: TagValue, category: TagCategory) {
        if isAllTag(tag) {
            withAnimation(.easeInOut(duration: 0.2)) {
                let selection = TagSelection(category: category, tagId: tag.id)
                if selectedTags.contains(selection) {
                    selectedTags.remove(selection)
                } else {
                    selectedTags = selectedTags.filter { $0.category != category }
                    selectedTags.insert(selection)
                }
            }
            return
        }

        if isAllSelected(in: category) {
            return
        }

        let selection = TagSelection(category: category, tagId: tag.id)
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedTags.contains(selection) {
                selectedTags.remove(selection)
            } else {
                selectedTags.insert(selection)
            }
        }
    }

    private func isAllTag(_ tag: TagValue) -> Bool {
        tag.name == "All"
    }

    private func isAllSelected(in category: TagCategory) -> Bool {
        guard let allId = catalogTagId(for: category, name: "All") else { return false }
        return selectedTags.contains(TagSelection(category: category, tagId: allId))
    }

    private func catalogTagId(for category: TagCategory, name: String) -> Int64? {
        let tags: [TagValue]
        switch category {
        case .location:
            tags = catalog.locations
        case .mood:
            tags = catalog.moods
        case .musicTheme:
            tags = catalog.musicThemes
        case .atmosphereTheme:
            tags = catalog.atmosphereThemes
        case .sfxTheme:
            tags = catalog.sfxThemes
        case .creatureType:
            tags = catalog.creatureTypes
        }
        return tags.first(where: { $0.name == name })?.id
    }

    private func loadTags() async {
        guard !isLoadingTags else { return }
        isLoadingTags = true
        do {
            await backend.seedIfNeeded()
            try await backend.tagRepository.ensureBaselineTags()
            catalog = try await backend.tagRepository.fetchAllTags()
        } catch {
            errorMessage = "Unable to load tags."
        }
        isLoadingTags = false
    }

    private func saveNewTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            do {
                let created = try await backend.tagRepository.upsertTag(name: name, category: newTagCategory)
                await MainActor.run {
                    insertTagAtFront(created, category: newTagCategory)
                    selectedTags.insert(TagSelection(category: newTagCategory, tagId: created.id))
                    newTagName = ""
                    showAddTag = false
                }
            } catch {
                await MainActor.run { errorMessage = "Unable to add tag." }
            }
        }
    }

    private func insertTagAtFront(_ tag: TagValue, category: TagCategory) {
        switch category {
        case .location:
            catalog.locations = [tag] + catalog.locations.filter { $0.id != tag.id }
        case .mood:
            catalog.moods = [tag] + catalog.moods.filter { $0.id != tag.id }
        case .musicTheme:
            catalog.musicThemes = [tag] + catalog.musicThemes.filter { $0.id != tag.id }
        case .atmosphereTheme:
            catalog.atmosphereThemes = [tag] + catalog.atmosphereThemes.filter { $0.id != tag.id }
        case .sfxTheme:
            catalog.sfxThemes = [tag] + catalog.sfxThemes.filter { $0.id != tag.id }
        case .creatureType:
            catalog.creatureTypes = [tag] + catalog.creatureTypes.filter { $0.id != tag.id }
        }
    }

    private func sortTags(_ tags: [TagValue], category: TagCategory) -> [TagValue] {
        let selected = tags.filter { selectedTags.contains(TagSelection(category: category, tagId: $0.id)) }
        let unselected = tags.filter { !selectedTags.contains(TagSelection(category: category, tagId: $0.id)) }
        let sorter: (TagValue, TagValue) -> Bool = {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        var combined = selected.sorted(by: sorter) + unselected.sorted(by: sorter)
        if let allIndex = combined.firstIndex(where: { isAllTag($0) }) {
            let allTag = combined.remove(at: allIndex)
            combined.insert(allTag, at: 0)
        }
        return combined
    }

    private func moveTracks(from source: IndexSet, to destination: Int) {
        trackURLs.move(fromOffsets: source, toOffset: destination)
    }

    private func removeTracks(at offsets: IndexSet) {
        trackURLs.remove(atOffsets: offsets)
    }

    private func toggleEditMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
#if os(iOS)
            editMode = editMode == .active ? .inactive : .active
#else
            isReordering.toggle()
#endif
        }
    }

    private func handleSave() {
        guard !isSaving else { return }
        let name = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard !trackURLs.isEmpty else { return }
        isSaving = true
        let tagIds = tagIdsByCategory()
        Task {
            do {
                _ = try await backend.addLocalPlaylist(
                    name: name,
                    trackURLs: trackURLs,
                    selectedTagIDs: tagIds
                )
                await MainActor.run {
                    isSaving = false
                    LibraryChangeNotifier.notify()
                    dismiss()
                    onPlaylistAdded()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to create playlist."
                }
            }
        }
    }

    private func tagIdsByCategory() -> [TagCategory: [Int64]] {
        var mapping: [TagCategory: [Int64]] = [:]
        for selection in selectedTags {
            mapping[selection.category, default: []].append(selection.tagId)
        }
        return mapping
    }
}

@available(iOS 18.0, *)
private struct PlaylistImportView: View {
    let playlist: Playlist
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var backend: AppBackend
    @EnvironmentObject private var theme: ThemeModel

    @State private var catalog = TagCatalog(
        locations: [],
        moods: [],
        musicThemes: [],
        atmosphereThemes: [],
        sfxThemes: [],
        creatureTypes: []
    )
    @State private var selectedTags: Set<TagSelection> = []
    @State private var isLoadingTags = false
    @State private var showAddTag = false
    @State private var newTagName = ""
    @State private var newTagCategory: TagCategory = .musicTheme
    @State private var isTagSearchActive = false
    @State private var tagSearchText = ""
    @Namespace private var tagSearchNamespace
    @State private var isTagSearchHovered = false
    @State private var isTagAddHovered = false
    @FocusState private var isTagSearchFocused: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let allowedCategories: [TagCategory] = [.musicTheme, .location, .mood]

    var body: some View {
        NavigationStack {
            List {
                Section(header: sectionHeader("Playlist")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(playlist.name)
                            .font(.headline)
                        if let subtitle = playlist.curatorName {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowBackground(Rectangle().fill(.thinMaterial))

                Section(header: tagHeader) {
                    if isLoadingTags {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowBackground(Rectangle().fill(.thinMaterial))
                    } else {
                        ForEach(visibleTagSections) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                PlaylistTagRowView(
                                    category: section.category,
                                    tags: section.tags,
                                    selected: selectedTags,
                                    isAllSelected: isAllSelected(in: section.category),
                                    onToggle: toggleTag
                                )
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Rectangle().fill(.thinMaterial))
                        }
                    }
                }
            }
            .cantusInsetGroupedListStyle()
            .navigationTitle("Import Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarIconButton(systemName: "xmark", action: { dismiss() }, accessibilityLabel: "Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarIconButton(systemName: "checkmark", action: { handleSave() }, accessibilityLabel: "Save")
                        .disabled(isSaving)
                }
            }
            .alert("Import Error", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
        }
        .background(.thinMaterial, in: .rect(cornerRadius: 28))
        .task { await loadTags() }
        .sheet(isPresented: $showAddTag) {
            AddTagSheet(
                name: $newTagName,
                category: $newTagCategory,
                allowedCategories: allowedCategories,
                title: "Add Playlist Tag",
                onCancel: { showAddTag = false },
                onSave: { saveNewTag() }
            )
        }
    }

    private var tagHeader: some View {
        HStack {
            if isTagSearchActive {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search tags", text: $tagSearchText)
                        .cantusTextInputAutocapitalization(.never)
                        .cantusDisableAutocorrection()
                        .font(.body)
                        .focused($isTagSearchFocused)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            tagSearchText = ""
                            isTagSearchActive = false
                            isTagSearchFocused = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .textFieldStyle(.plain)
                .cantusGlassEffectClear(in: Capsule())
                .matchedGeometryEffect(id: "tagSearch", in: tagSearchNamespace)
                .transition(.opacity)
            } else {
                sectionHeader("Tags")
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) { isTagSearchActive = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isTagSearchFocused = true
                    }
                }) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .cantusGlassEffectClear(in: Circle())
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(isTagSearchHovered ? 0.12 : 0.0))
                        )
                        .matchedGeometryEffect(id: "tagSearch", in: tagSearchNamespace)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTagSearchHovered = hovering
                    }
                }
                Button(action: { showAddTag = true }) {
                    Image(systemName: "plus")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .cantusGlassEffectClear(in: Circle())
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(isTagAddHovered ? 0.12 : 0.0))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTagAddHovered = hovering
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var visibleTagSections: [TagSection] {
        return allowedCategories.compactMap { category in
            let filtered = tags(for: category)
            guard !filtered.isEmpty else { return nil }
            return TagSection(
                category: category,
                title: category.label,
                tags: filtered
            )
        }
    }

    private func tags(for category: TagCategory) -> [TagValue] {
        let source: [TagValue]
        switch category {
        case .location:
            source = catalog.locations
        case .mood:
            source = catalog.moods
        case .musicTheme:
            source = catalog.musicThemes
        case .atmosphereTheme:
            source = catalog.atmosphereThemes
        case .sfxTheme:
            source = catalog.sfxThemes
        case .creatureType:
            source = catalog.creatureTypes
        }

        let term = tagSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var filtered = (isTagSearchActive && !term.isEmpty)
            ? source.filter { $0.name.localizedCaseInsensitiveContains(term) }
            : source
        if let allTag = source.first(where: isAllTag) {
            filtered.removeAll { $0.id == allTag.id }
            filtered.insert(allTag, at: 0)
        }
        return sortTags(filtered, category: category)
    }

    private func toggleTag(_ tag: TagValue, category: TagCategory) {
        if isAllTag(tag) {
            withAnimation(.easeInOut(duration: 0.2)) {
                let selection = TagSelection(category: category, tagId: tag.id)
                if selectedTags.contains(selection) {
                    selectedTags.remove(selection)
                } else {
                    selectedTags = selectedTags.filter { $0.category != category }
                    selectedTags.insert(selection)
                }
            }
            return
        }

        if isAllSelected(in: category) {
            return
        }

        let selection = TagSelection(category: category, tagId: tag.id)
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedTags.contains(selection) {
                selectedTags.remove(selection)
            } else {
                selectedTags.insert(selection)
            }
        }
    }

    private func isAllTag(_ tag: TagValue) -> Bool {
        tag.name == "All"
    }

    private func isAllSelected(in category: TagCategory) -> Bool {
        guard let allId = catalogTagId(for: category, name: "All") else { return false }
        return selectedTags.contains(TagSelection(category: category, tagId: allId))
    }

    private func catalogTagId(for category: TagCategory, name: String) -> Int64? {
        let tags: [TagValue]
        switch category {
        case .location:
            tags = catalog.locations
        case .mood:
            tags = catalog.moods
        case .musicTheme:
            tags = catalog.musicThemes
        case .atmosphereTheme:
            tags = catalog.atmosphereThemes
        case .sfxTheme:
            tags = catalog.sfxThemes
        case .creatureType:
            tags = catalog.creatureTypes
        }
        return tags.first(where: { $0.name == name })?.id
    }

    private func loadTags() async {
        guard !isLoadingTags else { return }
        isLoadingTags = true
        do {
            await backend.seedIfNeeded()
            try await backend.tagRepository.ensureBaselineTags()
            catalog = try await backend.tagRepository.fetchAllTags()
        } catch {
            errorMessage = "Unable to load tags."
        }
        isLoadingTags = false
    }

    private func saveNewTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            do {
                let created = try await backend.tagRepository.upsertTag(name: name, category: newTagCategory)
                await MainActor.run {
                    insertTagAtFront(created, category: newTagCategory)
                    selectedTags.insert(TagSelection(category: newTagCategory, tagId: created.id))
                    newTagName = ""
                    showAddTag = false
                }
            } catch {
                await MainActor.run { errorMessage = "Unable to add tag." }
            }
        }
    }

    private func insertTagAtFront(_ tag: TagValue, category: TagCategory) {
        switch category {
        case .location:
            catalog.locations = [tag] + catalog.locations.filter { $0.id != tag.id }
        case .mood:
            catalog.moods = [tag] + catalog.moods.filter { $0.id != tag.id }
        case .musicTheme:
            catalog.musicThemes = [tag] + catalog.musicThemes.filter { $0.id != tag.id }
        case .atmosphereTheme:
            catalog.atmosphereThemes = [tag] + catalog.atmosphereThemes.filter { $0.id != tag.id }
        case .sfxTheme:
            catalog.sfxThemes = [tag] + catalog.sfxThemes.filter { $0.id != tag.id }
        case .creatureType:
            catalog.creatureTypes = [tag] + catalog.creatureTypes.filter { $0.id != tag.id }
        }
    }

    private func sortTags(_ tags: [TagValue], category: TagCategory) -> [TagValue] {
        let selected = tags.filter { selectedTags.contains(TagSelection(category: category, tagId: $0.id)) }
        let unselected = tags.filter { !selectedTags.contains(TagSelection(category: category, tagId: $0.id)) }
        let sorter: (TagValue, TagValue) -> Bool = {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        var combined = selected.sorted(by: sorter) + unselected.sorted(by: sorter)
        if let allIndex = combined.firstIndex(where: { isAllTag($0) }) {
            let allTag = combined.remove(at: allIndex)
            combined.insert(allTag, at: 0)
        }
        return combined
    }

    private func handleSave() {
        guard !isSaving else { return }
        isSaving = true
        let tagIds = tagIdsByCategory()
        Task {
            do {
                let artworkURL = playlist.artwork?.url(width: 300, height: 300)?.absoluteString
                let subtitle = playlist.curatorName
                _ = try await backend.addAppleMusicPlaylist(
                    id: playlist.id.rawValue,
                    title: playlist.name,
                    subtitle: subtitle,
                    artworkURL: artworkURL,
                    selectedTagIDs: tagIds
                )
                await MainActor.run {
                    isSaving = false
                    LibraryChangeNotifier.notify()
                    dismiss()
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to add playlist."
                }
            }
        }
    }

    private func tagIdsByCategory() -> [TagCategory: [Int64]] {
        var mapping: [TagCategory: [Int64]] = [:]
        for selection in selectedTags {
            mapping[selection.category, default: []].append(selection.tagId)
        }
        return mapping
    }
}

@available(iOS 18.0, *)
struct EditPlaylistView: View {
    let itemId: String
    let initialTitle: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var backend: AppBackend
    @EnvironmentObject private var theme: ThemeModel
    @EnvironmentObject private var bookmarks: BookmarksStore
    @EnvironmentObject private var playback: PlaybackStateStore

    @State private var titleText: String
    @State private var catalog = TagCatalog(
        locations: [],
        moods: [],
        musicThemes: [],
        atmosphereThemes: [],
        sfxThemes: [],
        creatureTypes: []
    )
    @State private var selectedTags: Set<TagSelection> = []
    @State private var isLoadingTags = false
    @State private var isLoadingItem = false
    @State private var showAddTag = false
    @State private var newTagName = ""
    @State private var newTagCategory: TagCategory = .musicTheme
    @State private var isTagSearchActive = false
    @State private var tagSearchText = ""
    @Namespace private var tagSearchNamespace
    @State private var isTagSearchHovered = false
    @State private var isTagAddHovered = false
    @FocusState private var isTagSearchFocused: Bool
    @FocusState private var isNameFocused: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var originalTitle: String?

    private let allowedCategories: [TagCategory] = [.musicTheme, .location, .mood]

    init(itemId: String, initialTitle: String) {
        self.itemId = itemId
        self.initialTitle = initialTitle
        _titleText = State(initialValue: initialTitle)
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: sectionHeader("Name")) {
                    TextField("Playlist Name", text: $titleText)
                        .font(.body)
                        .focused($isNameFocused)
                }
                .listRowBackground(Rectangle().fill(.thinMaterial))

                Section(header: tagHeader) {
                    if isLoadingTags || isLoadingItem {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowBackground(Rectangle().fill(.thinMaterial))
                    } else {
                        ForEach(visibleTagSections) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                PlaylistTagRowView(
                                    category: section.category,
                                    tags: section.tags,
                                    selected: selectedTags,
                                    isAllSelected: isAllSelected(in: section.category),
                                    onToggle: toggleTag
                                )
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Rectangle().fill(.thinMaterial))
                        }
                    }
                }
            }
            .cantusInsetGroupedListStyle()
            .navigationTitle("Edit Playlist")
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarIconButton(systemName: "xmark", action: { dismiss() }, accessibilityLabel: "Close")
                }
#endif
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarIconButton(systemName: "checkmark", action: { handleSave() }, accessibilityLabel: "Save")
                        .disabled(isSaving || titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Update Error", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
        }
#if os(iOS)
        .background(.thinMaterial, in: .rect(cornerRadius: 28))
#endif
        .task {
            await loadTags()
            await loadItem()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isNameFocused = true
            }
        }
        .sheet(isPresented: $showAddTag) {
            AddTagSheet(
                name: $newTagName,
                category: $newTagCategory,
                allowedCategories: allowedCategories,
                title: "Add Playlist Tag",
                onCancel: { showAddTag = false },
                onSave: { saveNewTag() }
            )
        }
    }

    private var tagHeader: some View {
        HStack {
            if isTagSearchActive {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search tags", text: $tagSearchText)
                        .cantusTextInputAutocapitalization(.never)
                        .cantusDisableAutocorrection()
                        .font(.body)
                        .focused($isTagSearchFocused)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            tagSearchText = ""
                            isTagSearchActive = false
                            isTagSearchFocused = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .textFieldStyle(.plain)
                .cantusGlassEffectClear(in: Capsule())
                .matchedGeometryEffect(id: "editPlaylistTagSearch", in: tagSearchNamespace)
                .transition(.opacity)
            } else {
                sectionHeader("Tags")
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) { isTagSearchActive = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isTagSearchFocused = true
                    }
                }) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .cantusGlassEffectClear(in: Circle())
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(isTagSearchHovered ? 0.12 : 0.0))
                        )
                        .matchedGeometryEffect(id: "editPlaylistTagSearch", in: tagSearchNamespace)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTagSearchHovered = hovering
                    }
                }
                Button(action: { showAddTag = true }) {
                    Image(systemName: "plus")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .cantusGlassEffectClear(in: Circle())
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(isTagAddHovered ? 0.12 : 0.0))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTagAddHovered = hovering
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var visibleTagSections: [TagSection] {
        return allowedCategories.compactMap { category in
            let filtered = tags(for: category)
            guard !filtered.isEmpty else { return nil }
            return TagSection(
                category: category,
                title: category.label,
                tags: filtered
            )
        }
    }

    private func tags(for category: TagCategory) -> [TagValue] {
        let source: [TagValue]
        switch category {
        case .location:
            source = catalog.locations
        case .mood:
            source = catalog.moods
        case .musicTheme:
            source = catalog.musicThemes
        case .atmosphereTheme:
            source = catalog.atmosphereThemes
        case .sfxTheme:
            source = catalog.sfxThemes
        case .creatureType:
            source = catalog.creatureTypes
        }

        let term = tagSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var filtered = (isTagSearchActive && !term.isEmpty)
            ? source.filter { $0.name.localizedCaseInsensitiveContains(term) }
            : source
        if let allTag = source.first(where: isAllTag) {
            filtered.removeAll { $0.id == allTag.id }
            filtered.insert(allTag, at: 0)
        }
        return sortTags(filtered, category: category)
    }

    private func toggleTag(_ tag: TagValue, category: TagCategory) {
        if isAllTag(tag) {
            withAnimation(.easeInOut(duration: 0.2)) {
                let selection = TagSelection(category: category, tagId: tag.id)
                if selectedTags.contains(selection) {
                    selectedTags.remove(selection)
                } else {
                    selectedTags = selectedTags.filter { $0.category != category }
                    selectedTags.insert(selection)
                }
            }
            return
        }

        if isAllSelected(in: category) {
            return
        }

        let selection = TagSelection(category: category, tagId: tag.id)
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedTags.contains(selection) {
                selectedTags.remove(selection)
            } else {
                selectedTags.insert(selection)
            }
        }
    }

    private func isAllTag(_ tag: TagValue) -> Bool {
        tag.name == "All"
    }

    private func isAllSelected(in category: TagCategory) -> Bool {
        guard let allId = catalogTagId(for: category, name: "All") else { return false }
        return selectedTags.contains(TagSelection(category: category, tagId: allId))
    }

    private func catalogTagId(for category: TagCategory, name: String) -> Int64? {
        let tags: [TagValue]
        switch category {
        case .location:
            tags = catalog.locations
        case .mood:
            tags = catalog.moods
        case .musicTheme:
            tags = catalog.musicThemes
        case .atmosphereTheme:
            tags = catalog.atmosphereThemes
        case .sfxTheme:
            tags = catalog.sfxThemes
        case .creatureType:
            tags = catalog.creatureTypes
        }
        return tags.first(where: { $0.name == name })?.id
    }

    private func loadTags() async {
        guard !isLoadingTags else { return }
        isLoadingTags = true
        do {
            await backend.seedIfNeeded()
            try await backend.tagRepository.ensureBaselineTags()
            catalog = try await backend.tagRepository.fetchAllTags()
        } catch {
            errorMessage = "Unable to load tags."
        }
        isLoadingTags = false
    }

    private func loadItem() async {
        guard !isLoadingItem else { return }
        isLoadingItem = true
        defer { isLoadingItem = false }
        guard let uuid = UUID(uuidString: itemId) else { return }
        do {
            let detail = try await backend.libraryRepository.fetchItemDetail(itemId: uuid)
            await MainActor.run {
                titleText = detail.item.title
                originalTitle = detail.item.title
                selectedTags = tagsFromDetail(detail)
            }
        } catch {
            await MainActor.run {
                errorMessage = "Unable to load playlist."
            }
        }
    }

    private func tagsFromDetail(_ detail: ItemDetail) -> Set<TagSelection> {
        var selections: Set<TagSelection> = []
        detail.locations.forEach { selections.insert(TagSelection(category: .location, tagId: $0.id)) }
        detail.moods.forEach { selections.insert(TagSelection(category: .mood, tagId: $0.id)) }
        detail.musicThemes.forEach { selections.insert(TagSelection(category: .musicTheme, tagId: $0.id)) }
        return selections
    }

    private func saveNewTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            do {
                let created = try await backend.tagRepository.upsertTag(name: name, category: newTagCategory)
                await MainActor.run {
                    insertTagAtFront(created, category: newTagCategory)
                    selectedTags.insert(TagSelection(category: newTagCategory, tagId: created.id))
                    newTagName = ""
                    showAddTag = false
                }
            } catch {
                await MainActor.run { errorMessage = "Unable to add tag." }
            }
        }
    }

    private func insertTagAtFront(_ tag: TagValue, category: TagCategory) {
        switch category {
        case .location:
            catalog.locations = [tag] + catalog.locations.filter { $0.id != tag.id }
        case .mood:
            catalog.moods = [tag] + catalog.moods.filter { $0.id != tag.id }
        case .musicTheme:
            catalog.musicThemes = [tag] + catalog.musicThemes.filter { $0.id != tag.id }
        case .atmosphereTheme:
            catalog.atmosphereThemes = [tag] + catalog.atmosphereThemes.filter { $0.id != tag.id }
        case .sfxTheme:
            catalog.sfxThemes = [tag] + catalog.sfxThemes.filter { $0.id != tag.id }
        case .creatureType:
            catalog.creatureTypes = [tag] + catalog.creatureTypes.filter { $0.id != tag.id }
        }
    }

    private func sortTags(_ tags: [TagValue], category: TagCategory) -> [TagValue] {
        let selected = tags.filter { selectedTags.contains(TagSelection(category: category, tagId: $0.id)) }
        let unselected = tags.filter { !selectedTags.contains(TagSelection(category: category, tagId: $0.id)) }
        let sorter: (TagValue, TagValue) -> Bool = {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        var combined = selected.sorted(by: sorter) + unselected.sorted(by: sorter)
        if let allIndex = combined.firstIndex(where: { isAllTag($0) }) {
            let allTag = combined.remove(at: allIndex)
            combined.insert(allTag, at: 0)
        }
        return combined
    }

    private func handleSave() {
        guard !isSaving else { return }
        let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        let tagIds = tagIdsByCategory()
        Task {
            do {
                guard let uuid = UUID(uuidString: itemId) else { return }
                try await backend.updateItemProperties(
                    itemId: uuid,
                    title: trimmed,
                    kind: .music,
                    selectedTagIDs: tagIds,
                    containsMusic: false
                )
                await MainActor.run {
                    if let originalTitle, originalTitle != trimmed {
                        bookmarks.renamePlaylist(from: originalTitle, to: trimmed)
                        playback.renamePlaylist(from: originalTitle, to: trimmed)
                    }
                    isSaving = false
                    LibraryChangeNotifier.notify()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to update playlist."
                }
            }
        }
    }

    private func tagIdsByCategory() -> [TagCategory: [Int64]] {
        var mapping: [TagCategory: [Int64]] = [:]
        for selection in selectedTags {
            mapping[selection.category, default: []].append(selection.tagId)
        }
        return mapping
    }
}

private struct TagSection: Identifiable {
    let category: TagCategory
    let title: String
    let tags: [TagValue]

    var id: String { category.rawValue }
}

private struct TagSelection: Hashable {
    let category: TagCategory
    let tagId: Int64
}

private struct PlaylistTagRowView: View {
    let category: TagCategory
    let tags: [TagValue]
    let selected: Set<TagSelection>
    let isAllSelected: Bool
    let onToggle: (TagValue, TagCategory) -> Void

    @EnvironmentObject private var theme: ThemeModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 6) {
                ForEach(tags, id: \.id) { tag in
                    let isAllTag = tag.name == "All"
                    let isDisabled = isAllSelected && !isAllTag
                    PlaylistTagChip(
                        title: tag.name,
                        isSelected: isSelected(tag),
                        isAllTag: isAllTag,
                        isDisabled: isDisabled,
                        action: { onToggle(tag, category) }
                    )
                    .disabled(isDisabled)
                    .opacity(isDisabled ? 0.45 : 1.0)
                }
            }
        }
        .padding(.top, 2)
        .frame(height: 28)
    }

    private func isSelected(_ tag: TagValue) -> Bool {
        selected.contains(TagSelection(category: category, tagId: tag.id))
    }
}

private struct PlaylistTagChip: View {
    let title: String
    let isSelected: Bool
    let isAllTag: Bool
    let isDisabled: Bool
    let action: () -> Void
    @EnvironmentObject private var theme: ThemeModel

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(
            Capsule()
                .fill(backgroundColor)
        )
        .contentShape(Capsule())
        .foregroundStyle(isSelected ? highlightColor : .primary)
    }

    private var highlightColor: Color {
        isAllTag ? theme.headerColor : theme.color
    }

    private var backgroundColor: Color {
        if isSelected {
            return highlightColor.opacity(0.18)
        }
        return isAllTag ? Color.cantusSecondarySystemFill : Color.cantusTertiarySystemFill
    }
}

@available(iOS 18.0, *)
private struct AddTagSheet: View {
    @Binding var name: String
    @Binding var category: TagCategory
    let allowedCategories: [TagCategory]
    let title: String
    let onCancel: () -> Void
    let onSave: () -> Void
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Tag Name", text: $name)
                    .cantusTextInputAutocapitalization(.words)
                    .focused($isNameFocused)

                Picker("Category", selection: $category) {
                    ForEach(allowedCategories) { option in
                        Text(option.label)
                            .tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarIconButton(systemName: "xmark", action: onCancel, accessibilityLabel: "Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarIconButton(systemName: "checkmark", action: onSave, accessibilityLabel: "Save")
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isNameFocused = true
                }
            }
        }
    }
}

@available(iOS 18.0, *)
private struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .cantusTextInputAutocapitalization(.never)
                .cantusDisableAutocorrection()
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .cantusGlassEffectClear(in: Capsule())
    }
}
