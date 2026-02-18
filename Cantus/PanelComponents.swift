import SwiftUI

@available(iOS 18.0, *)
struct PanelShell<TrailingToolbar: View, Content: View>: View {
    let title: String
    let searchPlaceholder: String
    let tabs: [String]
    @Binding var selectedTab: Int
    @Binding var searchText: String
    let trailingToolbar: TrailingToolbar?
    let content: Content

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        searchPlaceholder: String,
        tabs: [String],
        selectedTab: Binding<Int>,
        searchText: Binding<String>,
        @ViewBuilder content: () -> Content
    ) where TrailingToolbar == EmptyView {
        self.title = title
        self.searchPlaceholder = searchPlaceholder
        self.tabs = tabs
        self._selectedTab = selectedTab
        self._searchText = searchText
        self.trailingToolbar = nil
        self.content = content()
    }

    init(
        title: String,
        searchPlaceholder: String,
        tabs: [String],
        selectedTab: Binding<Int>,
        searchText: Binding<String>,
        @ViewBuilder trailingToolbar: () -> TrailingToolbar,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.searchPlaceholder = searchPlaceholder
        self.tabs = tabs
        self._selectedTab = selectedTab
        self._searchText = searchText
        self.trailingToolbar = trailingToolbar()
        self.content = content()
    }

    private var unselectedTabColor: Color {
        colorScheme == .light ? Color.primary.opacity(0.7) : Color.primary
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        SearchField(text: $searchText, prompt: searchPlaceholder)

                        if !tabs.isEmpty {
                            Picker("Category", selection: $selectedTab) {
                            ForEach(tabs.indices, id: \.self) { index in
                                let isSelected = index == selectedTab
                                Text(tabs[index])
                                    .font(.body)
                                    .foregroundStyle(isSelected ? .primary : unselectedTabColor)
                                    .tag(index)
                            }
                        }
                            .pickerStyle(.segmented)
                            .tint(.primary)
                            .cantusGlassEffectClear(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
                .listRowBackground(Color.clear)

                Section {
                    content
                }
            }
            .cantusInsetGroupedListStyle()
            .navigationTitle(title)
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarIconButton(systemName: "xmark", action: { dismiss() }, accessibilityLabel: "Close")
                }
#endif
        if let trailingToolbar {
#if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                trailingToolbar
            }
#else
            ToolbarItem(placement: .automatic) {
                trailingToolbar
            }
#endif
        }
            }
        }
#if os(iOS)
        .background(.thinMaterial, in: .rect(cornerRadius: 28))
#else
        .background(Color.clear)
#endif
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
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .cantusGlassEffectClear(in: Capsule())
    }
}

@available(iOS 18.0, *)
struct ToolbarIconButton: View {
    let systemName: String
    let action: () -> Void
    var size: CGFloat = 34
    var iconScale: CGFloat = 1.0
    var accessibilityLabel: String? = nil
    @State private var isHovered = false
    @EnvironmentObject private var theme: ThemeModel

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: size, height: size)
                .scaleEffect(isHovered ? iconScale * 1.15 : iconScale)
        }
        .buttonStyle(.plain)
        .foregroundStyle(iconTint)
        .contentShape(Circle())
        .background(Circle().fill(Color.clear).frame(width: size, height: size))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(accessibilityLabel.map { Text($0) } ?? Text(systemName))
    }

    private var iconTint: Color {
        if systemName.contains("xmark") {
            return theme.headerColor
        }
        if systemName.contains("checkmark") {
            return theme.confirmIconColor
        }
        return .primary
    }
}

@available(iOS 18.0, *)
struct PanelToolbarPlusButton: View {
    let action: () -> Void
    var size: CGFloat = 34
    @State private var isHovered = false
    @EnvironmentObject private var theme: ThemeModel

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .frame(width: size, height: size)
                .scaleEffect(isHovered ? 1.15 : 1.0)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.confirmIconColor)
        .cantusGlassEffectClear(in: Circle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel("Import")
    }
}

@available(iOS 18.0, *)
struct PanelRow<InfoView: View>: View {
    let title: String
    let icon: String
    let isBookmarked: Bool
    let toggleBookmark: () -> Void
    let isPlaying: Bool
    let togglePlay: () -> Void
    let isBookmarkDisabled: Bool
    let containsMusic: Bool
    let badgeText: String?
    let badgeSystemImage: String?
    let infoView: InfoView?
    let recencyText: String?
    let isDimmed: Bool
    @EnvironmentObject private var theme: ThemeModel
    @State private var showInfo = false

    init(
        title: String,
        icon: String,
        isBookmarked: Bool,
        toggleBookmark: @escaping () -> Void,
        isPlaying: Bool,
        togglePlay: @escaping () -> Void,
        isBookmarkDisabled: Bool,
        containsMusic: Bool = false,
        badgeText: String? = nil,
        badgeSystemImage: String? = nil,
        recencyText: String? = nil,
        isDimmed: Bool = false
    ) where InfoView == EmptyView {
        self.title = title
        self.icon = icon
        self.isBookmarked = isBookmarked
        self.toggleBookmark = toggleBookmark
        self.isPlaying = isPlaying
        self.togglePlay = togglePlay
        self.isBookmarkDisabled = isBookmarkDisabled
        self.containsMusic = containsMusic
        self.badgeText = badgeText
        self.badgeSystemImage = badgeSystemImage
        self.infoView = nil
        self.recencyText = recencyText
        self.isDimmed = isDimmed
    }

    init(
        title: String,
        icon: String,
        isBookmarked: Bool,
        toggleBookmark: @escaping () -> Void,
        isPlaying: Bool,
        togglePlay: @escaping () -> Void,
        isBookmarkDisabled: Bool,
        containsMusic: Bool = false,
        badgeText: String? = nil,
        badgeSystemImage: String? = nil,
        @ViewBuilder infoView: () -> InfoView,
        recencyText: String? = nil,
        isDimmed: Bool = false
    ) {
        self.title = title
        self.icon = icon
        self.isBookmarked = isBookmarked
        self.toggleBookmark = toggleBookmark
        self.isPlaying = isPlaying
        self.togglePlay = togglePlay
        self.isBookmarkDisabled = isBookmarkDisabled
        self.containsMusic = containsMusic
        self.badgeText = badgeText
        self.badgeSystemImage = badgeSystemImage
        self.infoView = infoView()
        self.recencyText = recencyText
        self.isDimmed = isDimmed
    }

    var body: some View {
        HStack {
            Image(systemName: isPlaying ? "pause.fill" : icon)
                .foregroundStyle(isDimmed ? .secondary : theme.color)
                .frame(width: 20, alignment: .center)
            HStack(spacing: 6) {
                Text(title)
                    .foregroundStyle(isDimmed ? .secondary : .primary)
                    .font(.body)
                if containsMusic {
                    Image(systemName: "music.note")
                        .font(.caption)
                        .foregroundStyle(isDimmed ? .tertiary : .secondary)
                }
                if let badgeText {
                    HStack(spacing: 4) {
                        if let badgeSystemImage {
                            Image(systemName: badgeSystemImage)
                                .font(.caption2)
                        }
                        Text(badgeText)
                            .font(.caption2)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.cantusTertiarySystemFill))
                    .foregroundStyle(isDimmed ? .tertiary : .secondary)
                }
            }
            Spacer()
            if let recencyText {
                Text(recencyText)
                    .font(.caption2)
                    .foregroundStyle(isDimmed ? .tertiary : .secondary)
            }
            if infoView != nil {
                Button(action: { showInfo = true }) {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
                .popover(isPresented: $showInfo) {
                    infoView
                        .presentationDetents([.medium])
                }
            }

            Button(action: toggleBookmark) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(.plain)
            .foregroundColor(isBookmarkDisabled && !isBookmarked ? .secondary : theme.color)
            .opacity(isBookmarkDisabled && !isBookmarked ? 0.45 : 1.0)
            .disabled(isBookmarkDisabled && !isBookmarked)
            .padding(.leading, 6)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: togglePlay)
        .listRowBackground(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                if isPlaying {
                    Rectangle().fill(theme.listHighlightColor.opacity(0.25))
                }
            }
        )
        .opacity(isDimmed ? 0.55 : 1.0)
            #if os(iOS)
            .hoverEffectDisabled(true)
            #endif
    }
}

struct PlaylistRow: View {
    let title: String
    let icon: String

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
            #if os(iOS)
            .hoverEffectDisabled(true)
            #endif
    }
}

@available(iOS 18.0, *)
struct TagInfoPopover: View {
    let itemId: String
    let title: String

    @EnvironmentObject private var backend: AppBackend
    @EnvironmentObject private var theme: ThemeModel
    @State private var detail: ItemDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var attributionGroups: [ItemAttributionGroup] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                if detail?.item.containsMusic == true {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                        Text("Contains Music")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.cantusTertiarySystemFill)
                    )
                }
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let detail {
                tagSection("Theme", items: themeTags(from: detail))
                tagSection("Location", items: detail.locations.map(\.name))
                tagSection("Mood", items: detail.moods.map(\.name))
                tagSection("Creature Type", items: detail.creatureTypes.map(\.name))
                attributionSection
            } else {
                Text("No tags available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 240, maxWidth: 320)
        .padding(20)
        .task { await loadDetail() }
    }

    private func tagSection(_ title: String, items: [String]) -> some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(items, id: \.self) { item in
                                Text(item)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.cantusTertiarySystemFill)
                                    )
                            }
                        }
                    }
                }
            }
        }
    }

    private func themeTags(from detail: ItemDetail) -> [String] {
        if !detail.atmosphereThemes.isEmpty {
            return detail.atmosphereThemes.map(\.name)
        }
        if !detail.sfxThemes.isEmpty {
            return detail.sfxThemes.map(\.name)
        }
        if !detail.musicThemes.isEmpty {
            return detail.musicThemes.map(\.name)
        }
        return []
    }

    @ViewBuilder
    private var attributionSection: some View {
        if !attributionGroups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Attribution")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(attributionGroups.enumerated()), id: \.offset) { _, attribution in
                    VStack(alignment: .leading, spacing: 4) {
                        if !attribution.titles.isEmpty {
                            Text(formattedAttributionTitleList(attribution.titles))
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(formattedAttributionAuthor(attribution))
                            .font(.caption)
                        if let license = attribution.license, !license.isEmpty {
                            Text("Licensed under \(license)")
                                .font(.caption)
                        }
                        if let urlString = attribution.licenseURL,
                           let attributionURL = URL(string: urlString) {
                            Link(urlString, destination: attributionURL)
                                .font(.caption)
                        }
                    }
                }
            }
            .textSelection(.enabled)
        }
    }

    private func formattedAttributionTitleList(_ titles: [String]) -> String {
        let escaped = titles.map { title in
            "\"\(title.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return "[\(escaped.joined(separator: ", "))]"
    }

    private func formattedAttributionAuthor(_ attribution: ItemAttributionGroup) -> String {
        if let source = attribution.source, !source.isEmpty {
            return "\(attribution.author) (\(source))"
        }
        return attribution.author
    }

    private func loadDetail() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let uuid = UUID(uuidString: itemId) else {
            errorMessage = "Unable to load tags."
            return
        }
        do {
            detail = try await backend.libraryRepository.fetchItemDetail(itemId: uuid)
        } catch {
            errorMessage = "Unable to load tags."
            return
        }

        do {
            attributionGroups = try await backend.libraryRepository.fetchItemAttributions(itemId: uuid)
        } catch {
            attributionGroups = []
        }
    }
}
