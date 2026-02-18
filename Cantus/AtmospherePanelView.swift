import SwiftUI

@available(iOS 18.0, *)
struct AtmospherePanelView: View {
    @State private var selectedTab = 0
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var bookmarks: BookmarksStore
    @EnvironmentObject private var playback: PlaybackStateStore
    @EnvironmentObject private var backend: AppBackend
    @EnvironmentObject private var theme: ThemeModel
    @State private var now = Date()
    @State private var facets: FacetCounts?
    @State private var isLoading = false
    @State private var debugMessage: String?
    @State private var selectedTag: TagOption?
    @State private var taggedItems: [LibraryItemRow] = []
    @State private var isLoadingItems = false
    @State private var searchText = ""
    @State private var searchResults: [LibraryItemRow] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var allItems: [LibraryItemRow] = []
    @State private var isLoadingAll = false
    @State private var deleteTarget: DeleteTarget?
    @State private var showDeleteAlert = false
    @State private var editTarget: EditTarget?

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

    var body: some View {
        PanelShell(
            title: "Atmospheres",
            searchPlaceholder: "Search Atmosphere Loops",
            tabs: SortCategory.allCases.map(\.label),
            selectedTab: $selectedTab,
            searchText: $searchText,
            trailingToolbar: {
                ToolbarIconButton(
                    systemName: "plus",
                    action: {
                        openWindow(value: ImportAssetWindowPayload(initialKind: .atmosphere))
                    },
                    accessibilityLabel: "Import"
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
                        PanelRow(
                            title: item.title,
                            icon: "play.fill",
                            isBookmarked: bookmarks.isLoopBookmarked(item.title),
                            toggleBookmark: { bookmarks.toggleLoop(item.title) },
                            isPlaying: playback.isLoopPlaying(item.title),
                            togglePlay: {
                                let wasPlaying = playback.isLoopPlaying(item.title)
                                playback.toggleLoop(item.title)
                                if wasPlaying {
                                    backend.audioManager.stopAtmosphere(title: item.title)
                                } else {
                                    backend.audioManager.playAtmosphere(title: item.title)
                                }
                            },
                            isBookmarkDisabled: false,
                            containsMusic: item.containsMusic,
                            infoView: {
                                TagInfoPopover(itemId: item.id, title: item.title)
                                    .environmentObject(backend)
                                    .environmentObject(theme)
                            },
                            recencyText: recencyText(for: item.title)
                        )
                        .listRowSeparator(.hidden)
                        .contextMenu {
                            Button {
                                bookmarks.toggleLoop(item.title)
                            } label: {
                                Label(
                                    bookmarks.isLoopBookmarked(item.title) ? "Remove bookmark" : "Bookmark this sound",
                                    systemImage: bookmarks.isLoopBookmarked(item.title) ? "bookmark.slash" : "bookmark"
                                )
                            }
                            Button {
                                editTarget = EditTarget(itemId: item.id, title: item.title, kind: .atmosphere)
                            } label: {
                                Label("Edit properties", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteTarget = DeleteTarget(id: item.id, title: item.title)
                                showDeleteAlert = true
                            } label: {
                                Label("Delete this sound", systemImage: "trash")
                            }
                            .tint(theme.headerColor)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteTarget = DeleteTarget(id: item.id, title: item.title)
                                showDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(theme.headerColor)
                        }
                    }
                }
            } else if selectedCategory == .all {
                if isLoadingAll {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    ForEach(allItems, id: \.id) { item in
                        PanelRow(
                            title: item.title,
                            icon: "play.fill",
                            isBookmarked: bookmarks.isLoopBookmarked(item.title),
                            toggleBookmark: { bookmarks.toggleLoop(item.title) },
                            isPlaying: playback.isLoopPlaying(item.title),
                            togglePlay: {
                                let wasPlaying = playback.isLoopPlaying(item.title)
                                playback.toggleLoop(item.title)
                                if wasPlaying {
                                    backend.audioManager.stopAtmosphere(title: item.title)
                                } else {
                                    backend.audioManager.playAtmosphere(title: item.title)
                                }
                            },
                            isBookmarkDisabled: false,
                            containsMusic: item.containsMusic,
                            infoView: {
                                TagInfoPopover(itemId: item.id, title: item.title)
                                    .environmentObject(backend)
                                    .environmentObject(theme)
                            },
                            recencyText: recencyText(for: item.title)
                        )
                        .listRowSeparator(.hidden)
                        .contextMenu {
                            Button {
                                bookmarks.toggleLoop(item.title)
                            } label: {
                                Label(
                                    bookmarks.isLoopBookmarked(item.title) ? "Remove bookmark" : "Bookmark this sound",
                                    systemImage: bookmarks.isLoopBookmarked(item.title) ? "bookmark.slash" : "bookmark"
                                )
                            }
                            Button {
                                editTarget = EditTarget(itemId: item.id, title: item.title, kind: .atmosphere)
                            } label: {
                                Label("Edit properties", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteTarget = DeleteTarget(id: item.id, title: item.title)
                                showDeleteAlert = true
                            } label: {
                                Label("Delete this sound", systemImage: "trash")
                            }
                            .tint(theme.headerColor)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteTarget = DeleteTarget(id: item.id, title: item.title)
                                showDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(theme.headerColor)
                        }
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
                } else {
                    ForEach(taggedItems, id: \.id) { item in
                        PanelRow(
                            title: item.title,
                            icon: "play.fill",
                            isBookmarked: bookmarks.isLoopBookmarked(item.title),
                            toggleBookmark: { bookmarks.toggleLoop(item.title) },
                            isPlaying: playback.isLoopPlaying(item.title),
                            togglePlay: {
                                let wasPlaying = playback.isLoopPlaying(item.title)
                                playback.toggleLoop(item.title)
                                if wasPlaying {
                                    backend.audioManager.stopAtmosphere(title: item.title)
                                } else {
                                    backend.audioManager.playAtmosphere(title: item.title)
                                }
                            },
                            isBookmarkDisabled: false,
                            containsMusic: item.containsMusic,
                            infoView: {
                                TagInfoPopover(itemId: item.id, title: item.title)
                                    .environmentObject(backend)
                                    .environmentObject(theme)
                            },
                            recencyText: recencyText(for: item.title)
                        )
                        .listRowSeparator(.hidden)
                        .contextMenu {
                            Button {
                                bookmarks.toggleLoop(item.title)
                            } label: {
                                Label(
                                    bookmarks.isLoopBookmarked(item.title) ? "Remove bookmark" : "Bookmark this sound",
                                    systemImage: bookmarks.isLoopBookmarked(item.title) ? "bookmark.slash" : "bookmark"
                                )
                            }
                            Button {
                                editTarget = EditTarget(itemId: item.id, title: item.title, kind: .atmosphere)
                            } label: {
                                Label("Edit properties", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteTarget = DeleteTarget(id: item.id, title: item.title)
                                showDeleteAlert = true
                            } label: {
                                Label("Delete this sound", systemImage: "trash")
                            }
                            .tint(theme.headerColor)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteTarget = DeleteTarget(id: item.id, title: item.title)
                                showDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(theme.headerColor)
                        }
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
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No tags available. Seed data may still be loading.")
                                .foregroundStyle(.secondary)
                                .font(.body)
                            if let debugMessage {
                                Text(debugMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
        .task {
            await loadFacets()
            if selectedCategory == .all {
                await loadAllItems()
            } else {
                await loadFallbackItemsIfNeeded()
            }
        }
        .onChange(of: selectedTab) { _, _ in
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
        .onReceive(Self.minuteTicker) { now = $0 }
        .alert("Delete Asset?", isPresented: $showDeleteAlert, presenting: deleteTarget) { target in
            Button("Delete", role: .destructive) {
                Task { await deleteItem(target) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text("Delete \(target.title) from the library?")
        }
        .onChange(of: editTarget?.id) { _, _ in
            guard let target = editTarget else { return }
            openWindow(
                value: EditAssetWindowPayload(
                    itemId: target.itemId,
                    title: target.title,
                    kind: target.kind
                )
            )
            editTarget = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .cantusLibraryDidChange)) { _ in
            Task { await refreshVisibleContent() }
        }
    }

    private func refreshVisibleContent() async {
        await loadFacets()
        if selectedCategory == .all {
            if isSearching {
                await performSearch(term: searchText)
            } else {
                await loadAllItems()
            }
        } else if let selectedTag {
            await loadItems(for: selectedTag)
        } else if isSearching {
            await performSearch(term: searchText)
        } else {
            await loadFallbackItemsIfNeeded()
        }
    }

    private func loadFacets() async {
        guard !isLoading else { return }
        isLoading = true
        do {
            let seedURL = Bundle.main.url(forResource: "seed_catalog", withExtension: "json")
            if seedURL == nil {
                debugMessage = "Seed file missing from bundle."
            }
            await backend.seedIfNeeded()
            facets = try await backend.facetRepository.facetCounts(kind: .atmosphere, filters: Filters())
            let count = try await backend.libraryRepository.fetchItems(kind: .atmosphere, filters: Filters(), sort: .titleAsc).count
            debugMessage = "Atmosphere items: \(count), facet themes: \(facets?.atmosphereThemes.count ?? 0)"
        } catch {
            let count = (try? await backend.libraryRepository.fetchItems(kind: .atmosphere, filters: Filters(), sort: .titleAsc).count) ?? 0
            debugMessage = "Load error: \(error). Atmosphere items: \(count)"
            print("Failed to load facets: \(error)")
        }
        isLoading = false
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
            source = facets.atmosphereThemes
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
            source = facets.atmosphereThemes
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
            filters.atmosphereThemeIDs = [tagId]
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
            taggedItems = try await backend.libraryRepository.fetchItems(kind: .atmosphere, filters: filters, sort: .titleAsc)
        } catch {
            print("Failed to load atmospheres: \(error)")
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
            allItems = try await backend.libraryRepository.fetchItems(kind: .atmosphere, filters: Filters(), sort: .titleAsc)
        } catch {
            allItems = []
        }
        isLoadingAll = false
    }

    @ViewBuilder
    private var taggedItemsList: some View {
        ForEach(taggedItems, id: \.id) { item in
            PanelRow(
                title: item.title,
                icon: "play.fill",
                isBookmarked: bookmarks.isLoopBookmarked(item.title),
                toggleBookmark: { bookmarks.toggleLoop(item.title) },
                isPlaying: playback.isLoopPlaying(item.title),
                togglePlay: {
                    let wasPlaying = playback.isLoopPlaying(item.title)
                    playback.toggleLoop(item.title)
                    if wasPlaying {
                        backend.audioManager.stopAtmosphere(title: item.title)
                    } else {
                        backend.audioManager.playAtmosphere(title: item.title)
                    }
                },
                isBookmarkDisabled: false,
                containsMusic: item.containsMusic,
                infoView: {
                    TagInfoPopover(itemId: item.id, title: item.title)
                        .environmentObject(backend)
                        .environmentObject(theme)
                },
                recencyText: recencyText(for: item.title)
            )
            .listRowSeparator(.hidden)
            .contextMenu {
                Button {
                    bookmarks.toggleLoop(item.title)
                } label: {
                    Label(
                        bookmarks.isLoopBookmarked(item.title) ? "Remove bookmark" : "Bookmark this sound",
                        systemImage: bookmarks.isLoopBookmarked(item.title) ? "bookmark.slash" : "bookmark"
                    )
                }
                Button {
                    editTarget = EditTarget(itemId: item.id, title: item.title, kind: .atmosphere)
                } label: {
                    Label("Edit properties", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deleteTarget = DeleteTarget(id: item.id, title: item.title)
                    showDeleteAlert = true
                } label: {
                    Label("Delete this sound", systemImage: "trash")
                }
                .tint(theme.headerColor)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    deleteTarget = DeleteTarget(id: item.id, title: item.title)
                    showDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(theme.headerColor)
            }
        }
    }

    private var recentSet: Set<String> {
        Set(playback.recentLoops.filter { !bookmarks.loopBookmarks.contains($0) })
    }


    private func recencyText(for title: String) -> String? {
        guard !playback.isLoopPlaying(title) else { return nil }
        guard let lastPlayed = playback.lastPlayedLoop(title) else { return nil }
        let interval = max(0, now.timeIntervalSince(lastPlayed))
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

    private static let minuteTicker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private func performSearch(term: String) async {
        do {
            let results = try await backend.libraryRepository.searchAtmosphereAssets(query: term)
            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }
        } catch {
            await MainActor.run {
                self.searchResults = []
                self.isSearching = false
            }
            print("Search failed: \(error)")
        }
    }

    private func deleteItem(_ target: DeleteTarget) async {
        guard let uuid = UUID(uuidString: target.id) else { return }
        do {
            try await backend.libraryRepository.deleteItem(itemId: uuid)
            if bookmarks.isLoopBookmarked(target.title) {
                bookmarks.toggleLoop(target.title)
            }
            playback.removeRecentLoop(target.title)
            LibraryChangeNotifier.notify()
            searchResults.removeAll { $0.id == target.id }
            taggedItems.removeAll { $0.id == target.id }
            allItems.removeAll { $0.id == target.id }
            if selectedCategory == .all {
                if isSearching {
                    await performSearch(term: searchText)
                } else {
                    await loadAllItems()
                }
            } else if let selectedTag {
                await loadItems(for: selectedTag)
            } else if isSearching {
                await performSearch(term: searchText)
            } else {
                await loadFacets()
            }
        } catch {
            print("Delete failed: \(error)")
        }
    }
}

private struct DeleteTarget: Identifiable {
    let id: String
    let title: String
}

private struct EditTarget: Identifiable {
    let id = UUID()
    let itemId: String
    let title: String
    let kind: LibraryKind
}

#Preview {
    if #available(iOS 18.0, *) {
        AtmospherePanelView()
            .environmentObject(ThemeModel())
            .environmentObject(BookmarksStore())
            .environmentObject(PlaybackStateStore())
            .environmentObject(AppBackend.shared)
    }
}
