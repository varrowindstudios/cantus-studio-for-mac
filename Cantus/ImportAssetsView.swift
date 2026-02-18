import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

@available(iOS 18.0, *)
struct ImportAssetsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeModel
    @EnvironmentObject private var backend: AppBackend
    @EnvironmentObject private var playback: PlaybackStateStore

    @State private var selectedFileURL: URL?
    @State private var showFilePicker = false
    @State private var selectedKind: AssetKind?
    @State private var assetName = ""
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
    @State private var newTagCategory: TagCategory = .location
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var importAlert: ImportFlowAlert?
    @State private var isTagSearchActive = false
    @State private var tagSearchText = ""
    @Namespace private var tagSearchNamespace
    @State private var isTagSearchHovered = false
    @State private var isTagAddHovered = false
    @FocusState private var isTagSearchFocused: Bool
    @State private var containsMusic = false
    @StateObject private var previewPlayer = PreviewAudioPlayer()

    init(initialFileURL: URL? = nil, initialKind: AssetKind? = nil) {
        _selectedFileURL = State(initialValue: initialFileURL)
        _selectedKind = State(initialValue: initialKind)
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: sectionHeader("File")) {
                    Button(action: { showFilePicker = true }) {
                        HStack {
                            Label(selectedFileURL?.lastPathComponent ?? "Choose File", systemImage: "doc")
                                .font(.body)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(theme.color)
                    .foregroundStyle(theme.color)

                    if let selectedFileURL {
                        AudioPreviewPlayerView(
                            fileURL: selectedFileURL,
                            player: previewPlayer,
                            themeColor: theme.headerColor
                        )
                        .listRowBackground(Rectangle().fill(.thinMaterial))
                    }
                }
                .listRowBackground(Rectangle().fill(.thinMaterial))

                if selectedFileURL != nil {
                    Section(header: sectionHeader("Name")) {
                        TextField("Asset Name", text: $assetName)
                            .font(.body)
                    }
                    .listRowBackground(Rectangle().fill(.thinMaterial))
                }

                Section(header: sectionHeader("Type")) {
                    Picker("", selection: $selectedKind) {
                        Text("Choose a Type")
                            .font(.body)
                            .tag(AssetKind?.none)
                        ForEach(AssetKind.allCases) { option in
                            Text(option.label)
                                .font(.body)
                                .tag(Optional(option))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(theme.color)
                    .foregroundStyle(theme.color)
                }
                .listRowBackground(Rectangle().fill(.thinMaterial))

                if selectedKind == .atmosphere {
                    Section(header: sectionHeader("Attributes")) {
                        Toggle("Contains Music", isOn: $containsMusic)
                            .font(.body)
                    }
                    .listRowBackground(Rectangle().fill(.thinMaterial))
                }

                Section(header: tagHeader) {
                    if selectedKind == nil {
                        Text("Choose a Type to view tags.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Rectangle().fill(.thinMaterial))
                    } else if isLoadingTags {
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

                                TagRowView(
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
            .scrollContentBackground(.hidden)
            .navigationTitle(selectedKind?.importSheetTitle ?? "Import Asset")
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarIconButton(systemName: "xmark", action: { dismiss() }, accessibilityLabel: "Close")
                }
#endif
                ToolbarItem(placement: .confirmationAction) {
                    if selectedFileURL != nil, selectedKind != nil {
                        ToolbarIconButton(systemName: "checkmark", action: { handleImport() }, accessibilityLabel: "Import")
                    }
                }
            }
        }
#if os(iOS)
        .background(.thinMaterial, in: .rect(cornerRadius: 28))
#endif
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                selectedFileURL = urls.first
            case .failure(let error):
                errorMessage = error.localizedDescription
                importAlert = ImportFlowAlert(kind: .importFailure)
            }
        }
        .alert(item: $importAlert) { alert in
            switch alert.kind {
            case .invalidType:
                return Alert(
                    title: Text("Incorrect Filetype"),
                    message: Text("Cantus can only accept audio files."),
                    dismissButton: .default(Text("OK")) {
                        selectedFileURL = nil
                        importAlert = nil
                    }
                )
            case .duplicateConfirm:
                return Alert(
                    title: Text("Duplicate File"),
                    message: Text("It looks like you already have this sound in your Library. Import anyway?"),
                    primaryButton: .cancel(Text("Cancel")) {
                        selectedFileURL = nil
                        importAlert = nil
                    },
                    secondaryButton: .default(Text("Continue Import")) {
                        importAlert = nil
                        startImport()
                    }
                )
            case .importSuccess(let name):
                return Alert(
                    title: Text("Success"),
                    message: Text("\(name) was successully imported!"),
                    dismissButton: .default(Text("OK")) {
                        importAlert = nil
                        dismiss()
                    }
                )
            case .importFailure:
                return Alert(
                    title: Text("Failure"),
                    message: Text("Something went wrong. Check the file and try again."),
                    dismissButton: .default(Text("OK")) {
                        importAlert = nil
                    }
                )
            }
        }
        .task { await loadTags() }
        .onChange(of: selectedFileURL) { _, newValue in
            previewPlayer.load(url: newValue)
            guard let newValue else { return }
            assetName = backend.normalizedTitle(for: newValue)
            validateSelectedFile(newValue)
        }
        .onAppear {
            if let selectedFileURL {
                previewPlayer.load(url: selectedFileURL)
                assetName = backend.normalizedTitle(for: selectedFileURL)
                validateSelectedFile(selectedFileURL)
            }
        }
        .onDisappear {
            previewPlayer.stop()
        }
        .onChange(of: selectedKind) { _, newValue in
            if let newValue {
                newTagCategory = newValue.defaultNewTagCategory
            }
            if newValue != .atmosphere {
                containsMusic = false
            }
        }
        .sheet(isPresented: $showAddTag) {
            if let selectedKind {
                AddTagSheet(
                    name: $newTagName,
                    category: $newTagCategory,
                    allowedCategories: selectedKind.allowedTagCategories,
                    title: selectedKind.addTagTitle,
                    onCancel: { showAddTag = false },
                    onSave: { saveNewTag() }
                )
            }
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
                .disabled(selectedKind == nil)
                .opacity(selectedKind == nil ? 0.4 : 1.0)
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
                .disabled(selectedKind == nil)
                .opacity(selectedKind == nil ? 0.4 : 1.0)
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
        guard let selectedKind else { return [] }
        let categories = selectedKind.allowedTagCategories
        return categories.compactMap { category in
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
            errorMessage = error.localizedDescription
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
                await MainActor.run { errorMessage = error.localizedDescription }
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

    private func handleImport() {
        startImport()
    }

    private func startImport() {
        guard let selectedFileURL, let selectedKind, !isImporting else { return }
        isImporting = true
        let tagIds = tagIdsByCategory()
        let trimmedName = assetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredTitle = trimmedName.isEmpty ? nil : trimmedName
        Task {
            do {
                let imported = try await backend.importLocalAsset(
                    sourceURL: selectedFileURL,
                    kind: selectedKind.libraryKind,
                    selectedTagIDs: tagIds,
                    containsMusic: containsMusic,
                    preferredTitle: preferredTitle
                )
                await MainActor.run {
                    isImporting = false
                    let fileURL = AppFilePaths.applicationSupportURL().appendingPathComponent(imported.localPath)
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        let name = imported.title
                        if selectedKind.libraryKind == .atmosphere {
                            playback.addRecentLoop(imported.title)
                        } else if selectedKind.libraryKind == .sfx {
                            playback.addRecentSFX(imported.title)
                        }
                        LibraryChangeNotifier.notify()
                        importAlert = ImportFlowAlert(kind: .importSuccess(name))
                    } else {
                        importAlert = ImportFlowAlert(kind: .importFailure)
                    }
                }
            } catch {
                await MainActor.run {
                    importAlert = ImportFlowAlert(kind: .importFailure)
                    isImporting = false
                }
            }
        }
    }

    private func isAudioFile(_ url: URL) -> Bool {
        guard !url.pathExtension.isEmpty,
              let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .audio)
    }

    private func validateSelectedFile(_ url: URL) {
        if !isAudioFile(url) {
            importAlert = ImportFlowAlert(kind: .invalidType)
            return
        }
        Task {
            let trimmedName = assetName.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = trimmedName.isEmpty ? backend.normalizedTitle(for: url) : backend.normalizedTitle(from: trimmedName)
            do {
                let isDuplicate = try await backend.libraryRepository.titleExists(candidate)
                if isDuplicate {
                    await MainActor.run {
                        importAlert = ImportFlowAlert(kind: .duplicateConfirm)
                    }
                }
            } catch {
                return
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
private struct AudioPreviewPlayerView: View {
    let fileURL: URL
    @ObservedObject var player: PreviewAudioPlayer
    let themeColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(action: { player.toggle() }) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                        .cantusGlassEffectClear(in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!player.isReady)

                VStack(alignment: .leading, spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { player.currentTime },
                            set: { player.seek(to: $0) }
                        ),
                        in: 0...max(player.duration, 0.1),
                        onEditingChanged: { isEditing in
                            player.setScrubbing(isEditing)
                        }
                    )
                    .tint(themeColor)
                    .disabled(!player.isReady)

                    HStack {
                        Text(formatTime(player.currentTime))
                        Spacer()
                        Text(formatTime(player.duration))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .onAppear {
            player.load(url: fileURL)
        }
        .onChange(of: fileURL) { _, newValue in
            player.load(url: newValue)
        }
    }

    private func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }
        let totalSeconds = max(0, Int(value.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):" + String(format: "%02d", seconds)
    }
}

@available(iOS 18.0, *)
private final class PreviewAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var isReady = false
    @Published var duration: TimeInterval = 0
    @Published var currentTime: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var accessedURL: URL?
    private var isScrubbing = false

    func load(url: URL?) {
        guard let url else {
            stop()
            return
        }
        if accessedURL == url, player != nil { return }
        stop()
        beginAccess(for: url)
        configureSessionIfNeeded()
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.prepareToPlay()
            player = newPlayer
            duration = newPlayer.duration
            currentTime = newPlayer.currentTime
            isReady = true
        } catch {
            stop()
        }
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        if !player.isPlaying {
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        isReady = false
        duration = 0
        currentTime = 0
        stopTimer()
        endAccess()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(0, time), player.duration)
        player.currentTime = clamped
        currentTime = clamped
    }

    func setScrubbing(_ scrubbing: Bool) {
        isScrubbing = scrubbing
        if !scrubbing, let player {
            currentTime = player.currentTime
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        stopTimer()
        player.currentTime = 0
        currentTime = 0
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let player = self.player, !self.isScrubbing else { return }
            self.currentTime = player.currentTime
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func beginAccess(for url: URL) {
        guard accessedURL != url else { return }
        endAccess()
        if url.startAccessingSecurityScopedResource() {
            accessedURL = url
        }
    }

    private func endAccess() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }

    private func configureSessionIfNeeded() {
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            return
        }
#endif
    }

    deinit {
        stop()
    }
}

@available(iOS 18.0, *)
struct EditAssetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeModel
    @EnvironmentObject private var backend: AppBackend
    @EnvironmentObject private var bookmarks: BookmarksStore
    @EnvironmentObject private var playback: PlaybackStateStore

    let itemId: String
    let initialTitle: String
    let initialKind: LibraryKind

    @State private var titleText: String
    @State private var selectedKind: AssetKind
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
    @State private var newTagCategory: TagCategory
    @State private var isSaving = false
    @State private var alertState: ImportAlert?
    @State private var isTagSearchActive = false
    @State private var tagSearchText = ""
    @Namespace private var tagSearchNamespace
    @State private var isTagSearchHovered = false
    @State private var isTagAddHovered = false
    @FocusState private var isTagSearchFocused: Bool
    @FocusState private var isNameFocused: Bool
    @State private var originalTitle: String?
    @State private var originalKind: LibraryKind?
    @State private var containsMusic = false

    init(itemId: String, initialTitle: String, initialKind: LibraryKind) {
        self.itemId = itemId
        self.initialTitle = initialTitle
        self.initialKind = initialKind
        _titleText = State(initialValue: initialTitle)
        _selectedKind = State(initialValue: AssetKind(libraryKind: initialKind) ?? .atmosphere)
        _newTagCategory = State(initialValue: (AssetKind(libraryKind: initialKind) ?? .atmosphere).defaultNewTagCategory)
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: sectionHeader("Name")) {
                    TextField("Sound Name", text: $titleText)
                        .font(.body)
                        .focused($isNameFocused)
                }
                .listRowBackground(Rectangle().fill(.thinMaterial))

                Section(header: sectionHeader("Type")) {
                    Picker("Type", selection: $selectedKind) {
                        ForEach(AssetKind.allCases) { option in
                            Text(option.label)
                                .font(.body)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .listRowBackground(Rectangle().fill(.thinMaterial))

                if selectedKind == .atmosphere {
                    Section(header: sectionHeader("Attributes")) {
                        Toggle("Contains Music", isOn: $containsMusic)
                            .font(.body)
                    }
                    .listRowBackground(Rectangle().fill(.thinMaterial))
                }

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

                                TagRowView(
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
            .scrollContentBackground(.hidden)
            .navigationTitle("Edit Properties")
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
        }
#if os(iOS)
        .background(.thinMaterial, in: .rect(cornerRadius: 28))
#endif
        .alert(item: $alertState) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK")) {
                    alertState = nil
                }
            )
        }
        .task {
            await loadTags()
            await loadItem()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isNameFocused = true
            }
        }
        .onChange(of: selectedKind) { _, newValue in
            newTagCategory = newValue.defaultNewTagCategory
            selectedTags = selectedTags.filter { selection in
                newValue.allowedTagCategories.contains(selection.category)
            }
            if newValue != .atmosphere {
                containsMusic = false
            }
        }
        .sheet(isPresented: $showAddTag) {
            AddTagSheet(
                name: $newTagName,
                category: $newTagCategory,
                allowedCategories: selectedKind.allowedTagCategories,
                title: selectedKind.addTagTitle,
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
                .matchedGeometryEffect(id: "editTagSearch", in: tagSearchNamespace)
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
                        .matchedGeometryEffect(id: "editTagSearch", in: tagSearchNamespace)
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

    private var visibleTagSections: [TagSection] {
        let categories = selectedKind.allowedTagCategories
        return categories.compactMap { category in
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

    private func loadTags() async {
        guard !isLoadingTags else { return }
        isLoadingTags = true
        do {
            await backend.seedIfNeeded()
            try await backend.tagRepository.ensureBaselineTags()
            catalog = try await backend.tagRepository.fetchAllTags()
        } catch {
            alertState = ImportAlert(title: "Failure", message: "Something went wrong. Check the file and try again.", shouldDismiss: false)
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
                let kind = LibraryKind(rawValue: detail.item.kind) ?? initialKind
                let assetKind = AssetKind(libraryKind: kind) ?? .atmosphere
                originalTitle = detail.item.title
                originalKind = kind
                titleText = detail.item.title
                selectedKind = assetKind
                newTagCategory = assetKind.defaultNewTagCategory
                selectedTags = tagsFromDetail(detail)
                containsMusic = detail.item.containsMusic
            }
        } catch {
            await MainActor.run {
                alertState = ImportAlert(title: "Failure", message: "Something went wrong. Check the file and try again.", shouldDismiss: false)
            }
        }
    }

    private func tagsFromDetail(_ detail: ItemDetail) -> Set<TagSelection> {
        var selections: Set<TagSelection> = []
        detail.locations.forEach { selections.insert(TagSelection(category: .location, tagId: $0.id)) }
        detail.moods.forEach { selections.insert(TagSelection(category: .mood, tagId: $0.id)) }
        detail.musicThemes.forEach { selections.insert(TagSelection(category: .musicTheme, tagId: $0.id)) }
        detail.atmosphereThemes.forEach { selections.insert(TagSelection(category: .atmosphereTheme, tagId: $0.id)) }
        detail.sfxThemes.forEach { selections.insert(TagSelection(category: .sfxTheme, tagId: $0.id)) }
        detail.creatureTypes.forEach { selections.insert(TagSelection(category: .creatureType, tagId: $0.id)) }
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
                await MainActor.run { alertState = ImportAlert(title: "Failure", message: "Something went wrong. Check the file and try again.", shouldDismiss: false) }
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
                    kind: selectedKind.libraryKind,
                    selectedTagIDs: tagIds,
                    containsMusic: containsMusic
                )
                await MainActor.run {
                    updateLocalStores(newTitle: trimmed, newKind: selectedKind.libraryKind)
                    isSaving = false
                    LibraryChangeNotifier.notify()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    alertState = ImportAlert(title: "Failure", message: "Something went wrong. Check the file and try again.", shouldDismiss: false)
                    isSaving = false
                }
            }
        }
    }

    private func updateLocalStores(newTitle: String, newKind: LibraryKind) {
        let oldTitle = originalTitle ?? initialTitle
        let oldKind = originalKind ?? initialKind
        guard oldTitle != newTitle || oldKind != newKind else { return }

        if oldKind != newKind {
            if oldKind == .atmosphere {
                bookmarks.removeLoopBookmark(oldTitle)
                playback.removeLoopState(oldTitle)
            } else if oldKind == .sfx {
                bookmarks.removeSFXBookmark(oldTitle)
                playback.removeSFXState(oldTitle)
            }
            return
        }

        if oldKind == .atmosphere {
            bookmarks.renameLoop(from: oldTitle, to: newTitle)
            playback.renameLoop(from: oldTitle, to: newTitle)
        } else if oldKind == .sfx {
            bookmarks.renameSFX(from: oldTitle, to: newTitle)
            playback.renameSFX(from: oldTitle, to: newTitle)
        }
    }

    private func tagIdsByCategory() -> [TagCategory: [Int64]] {
        var mapping: [TagCategory: [Int64]] = [:]
        for selection in selectedTags {
            mapping[selection.category, default: []].append(selection.tagId)
        }
        return mapping
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

enum AssetKind: String, CaseIterable, Identifiable, Hashable, Codable {
    case atmosphere
    case sfx

    var id: String { rawValue }

    init?(libraryKind: LibraryKind) {
        switch libraryKind {
        case .atmosphere:
            self = .atmosphere
        case .sfx:
            self = .sfx
        case .music:
            return nil
        }
    }

    var label: String {
        switch self {
        case .atmosphere: return "Atmosphere"
        case .sfx: return "Sound Effect"
        }
    }

    var importSheetTitle: String {
        switch self {
        case .atmosphere: return "Import Atmosphere"
        case .sfx: return "Import Sound Effect"
        }
    }

    var allowedTagCategories: [TagCategory] {
        switch self {
        case .atmosphere:
            return [.atmosphereTheme, .location, .mood]
        case .sfx:
            return [.sfxTheme, .location, .creatureType]
        }
    }

    var defaultNewTagCategory: TagCategory {
        allowedTagCategories.first ?? .location
    }

    var libraryKind: LibraryKind {
        switch self {
        case .atmosphere: return .atmosphere
        case .sfx: return .sfx
        }
    }

    var addTagTitle: String {
        switch self {
        case .atmosphere:
            return "Add Atmosphere Tag"
        case .sfx:
            return "Add Sound Effect Tag"
        }
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

private struct TagRowView: View {
    let category: TagCategory
    let tags: [TagValue]
    let selected: Set<TagSelection>
    let isAllSelected: Bool
    let onToggle: (TagValue, TagCategory) -> Void

    @EnvironmentObject private var theme: ThemeModel
    private let horizontalPadding: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 6) {
                ForEach(tags, id: \.id) { tag in
                    let isAllTag = tag.name == "All"
                    let isDisabled = isAllSelected && !isAllTag
                    TagChip(
                        title: tag.name,
                        isSelected: isSelected(tag),
                        isAllTag: isAllTag,
                        isDisabled: isDisabled,
                        action: { onToggle(tag, currentCategory) }
                    )
                    .disabled(isDisabled)
                    .opacity(isDisabled ? 0.45 : 1.0)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
        .padding(.top, 2)
        .frame(height: 28)
    }

    private var currentCategory: TagCategory {
        category
    }

    private func isSelected(_ tag: TagValue) -> Bool {
        selected.contains(TagSelection(category: currentCategory, tagId: tag.id))
    }

}


private struct TagChip: View {
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

private struct ImportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let shouldDismiss: Bool
}

private struct ImportFlowAlert: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case invalidType
        case duplicateConfirm
        case importSuccess(String)
        case importFailure
    }
}
