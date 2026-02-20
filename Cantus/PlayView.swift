import SwiftUI
import MusicKit
import UniformTypeIdentifiers
import TipKit
#if os(macOS)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if os(iOS)
import AVKit
#endif

@available(iOS 18.0, *)
private enum CantusPlayTourState {
    static let versionKey = "cantus.playtour.version"

    static func currentVersion() -> Int {
        max(0, UserDefaults.standard.integer(forKey: versionKey))
    }

    static func bumpVersion() {
        let next = currentVersion() + 1
        UserDefaults.standard.set(next, forKey: versionKey)
    }
}

@available(iOS 18.0, *)
private enum CantusPlayTourStep: String, CaseIterable {
    case controlIt = "cantus.playtour.controlIt"
    case fastAccessTags = "cantus.playtour.fastAccessTags"
    case bookmarksAndRecents = "cantus.playtour.bookmarksAndRecents"
    case navigateWithEase = "cantus.playtour.navigateWithEase"
    case mixItUp = "cantus.playtour.mixItUp"
    case instantDucking = "cantus.playtour.instantDucking"
    case fastImport = "cantus.playtour.fastImport"
    case quickPlayFast = "cantus.playtour.quickPlayFast"

    var tipID: String { "\(rawValue).v\(CantusPlayTourState.currentVersion())" }
}

@available(iOS 18.0, *)
private struct CantusControlItTip: Tip {
    var id: String { CantusPlayTourStep.controlIt.tipID }
    var title: Text { Text("Control It!") }
    var message: Text? { Text("Play, pause, and move through your playlists with ease") }
    var options: [any TipOption] { Tip.IgnoresDisplayFrequency(true) }
}

@available(iOS 18.0, *)
private struct CantusFastAccessTagsTip: Tip {
    var id: String { CantusPlayTourStep.fastAccessTags.tipID }
    var title: Text { Text("Fast access to tags") }
    var message: Text? { Text("See the tags associated with your active playlist and tap to see related sounds") }
    var options: [any TipOption] { Tip.IgnoresDisplayFrequency(true) }
}

@available(iOS 18.0, *)
private struct CantusBookmarksAndRecentsTip: Tip {
    var id: String { CantusPlayTourStep.bookmarksAndRecents.tipID }
    var title: Text { Text("Bookmarks and Recently Played") }
    var message: Text? { Text("Play recent and bookmarked playlists, atmospheres, and sound effects with one tap") }
    var options: [any TipOption] { Tip.IgnoresDisplayFrequency(true) }
}

@available(iOS 18.0, *)
private struct CantusNavigateWithEaseTip: Tip {
    var id: String { CantusPlayTourStep.navigateWithEase.tipID }
    var title: Text { Text("Navigate with ease") }
    var message: Text? { Text("See all your sounds, sort by tag, search, and bookmark your favorites") }
    var options: [any TipOption] { Tip.IgnoresDisplayFrequency(true) }
}

@available(iOS 18.0, *)
private struct CantusMixItUpTip: Tip {
    var id: String { CantusPlayTourStep.mixItUp.tipID }
    var title: Text { Text("Mix it up!") }
    var message: Text? { Text("Adjust the volume of your music, atmosphere, and sound effects for the perfect mix") }
    var options: [any TipOption] { Tip.IgnoresDisplayFrequency(true) }
}

@available(iOS 18.0, *)
private struct CantusInstantDuckingTip: Tip {
    var id: String { CantusPlayTourStep.instantDucking.tipID }
    var title: Text { Text("Instant \"ducking\"") }
    var message: Text? { Text("Automatically lowers your music when you play a sound effect to make it pop and then brings it back") }
    var options: [any TipOption] { Tip.IgnoresDisplayFrequency(true) }
}

@available(iOS 18.0, *)
private struct CantusFastImportTip: Tip {
    var id: String { CantusPlayTourStep.fastImport.tipID }
    var title: Text { Text("Fast Import of New Sounds") }
    var message: Text? { Text("Import your sound files, tag them, and add them to your library") }
    var options: [any TipOption] { Tip.IgnoresDisplayFrequency(true) }
}

@available(iOS 18.0, *)
private struct CantusQuickPlayFastTip: Tip {
    var id: String { CantusPlayTourStep.quickPlayFast.tipID }
    var title: Text { Text("QuickPlay it Fast!") }
    var message: Text? { Text("Search for any sound by name or tag, and then tap to play it instantly") }
    var options: [any TipOption] { Tip.IgnoresDisplayFrequency(true) }
}

@available(iOS 18.0, *)
struct PlayView: View {
    @Binding var hasCompletedSetup: Bool
    @State private var showPremiumUpgrade = false
    @State private var pendingAlert: PendingAlert?
    @State private var now = Date()
    @State private var editRequest: EditRequest?
    @State private var atmosphereContainsMusic: [String: Bool] = [:]
    @State private var atmosphereItemIds: [String: String] = [:]
    @State private var sfxItemIds: [String: String] = [:]
    @State private var playlistItemIds: [String: String] = [:]
    @State private var playlistTitlesById: [String: String] = [:]
    @State private var playlistSourcesById: [String: PlaylistSource] = [:]
    @State private var editPlaylistRequest: EditPlaylistRequest?
    @State private var quickBoardOrder: [QuickBoardSection]
    @State private var draggingQuickBoard: QuickBoardSection?
    @State private var layoutWidth: CGFloat = 0
    @State private var bottomDockHeight: CGFloat = 0
    @State private var quickPlayQuery = ""
    @State private var quickPlayResults: [QuickPlayResult] = []
    @State private var quickPlaySelectedResultID: String?
    @State private var quickPlayIsPresented = false
    @State private var quickPlayFieldFocused = false
    @State private var quickPlaySearchTask: Task<Void, Never>?
    @State private var showAddPopover = false
    @AppStorage("hasSeenCantusWelcomeTourSplash") private var hasSeenCantusWelcomeTourSplash = false
    @AppStorage("cantus.firstLaunchDefaults.v1.applied") private var hasAppliedFirstLaunchDefaults = false
    @State private var showWelcomeTourSplash = false
    @State private var showTourCompletionSplash = false
    @State private var isTourActive = false
    @State private var currentTourStep: CantusPlayTourStep?
    @State private var tourStepStatusTask: Task<Void, Never>?
    @State private var lastTourManualInvalidateAt = Date.distantPast
    @State private var didCompleteInitialLibraryBootstrap = false
    @State private var showFirstLaunchLoadCover = false

    private struct PendingAlert: Identifiable {
        enum Kind {
            case removeBookmark
            case removeBookmarkSFX
            case removeBookmarkPlaylist
        }

        let id = UUID()
        let kind: Kind
        let item: String
    }

    private static let controlItTip = CantusControlItTip()
    private static let fastAccessTagsTip = CantusFastAccessTagsTip()
    private static let bookmarksAndRecentsTip = CantusBookmarksAndRecentsTip()
    private static let navigateWithEaseTip = CantusNavigateWithEaseTip()
    private static let mixItUpTip = CantusMixItUpTip()
    private static let instantDuckingTip = CantusInstantDuckingTip()
    private static let fastImportTip = CantusFastImportTip()
    private static let quickPlayFastTip = CantusQuickPlayFastTip()

    private let atmosphereDividerHeight: CGFloat = 2
    private let defaultNowPlayingPlaylistTitle = "Initiative!"

    @EnvironmentObject private var theme: ThemeModel
    @EnvironmentObject private var bookmarks: BookmarksStore
    @EnvironmentObject private var playback: PlaybackStateStore
    @EnvironmentObject private var backend: AppBackend
    @EnvironmentObject private var musicPlayback: MusicPlaybackStore
    @EnvironmentObject private var premium: PremiumStore
    @Environment(\.scenePhase) private var scenePhase
    
    @EnvironmentObject private var menuState: AppMenuState

    init(hasCompletedSetup: Binding<Bool>) {
        self._hasCompletedSetup = hasCompletedSetup
        _quickBoardOrder = State(initialValue: Self.loadQuickBoardOrder())
    }

    var body: some View {
        lifecycleLayer
    }

    private var baseLayer: some View {
        ZStack {
            scrollBody
        }
        .background(PlayBackground())
        .overlay(alignment: .bottom) {
            BottomFadeOverlay()
        }
    }

    private var interactionLayer: some View {
        platformConfiguredBaseLayer
            .onReceive(Self.minuteTicker) { newDate in
                now = newDate
            }
            .onChange(of: menuState.quickPlayRequested) { _, newValue in
                guard newValue else { return }
                menuState.quickPlayRequested = false
                toggleQuickPlay()
            }
            .onChange(of: quickPlayQuery) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if quickPlayFieldFocused, !trimmed.isEmpty, !quickPlayIsPresented {
                    quickPlayIsPresented = true
                }
                performQuickPlaySearch(query: newValue)
            }
            .onChange(of: quickPlayFieldFocused) { _, isFocused in
                if !isFocused {
                    quickPlayIsPresented = false
                }
            }
            .onChange(of: quickPlayIsPresented) { _, newValue in
                if !newValue {
                    clearQuickPlay()
                }
            }
            .onChange(of: quickBoardOrder) { _, newValue in
                persistQuickBoardOrder(newValue)
            }
            .overlay(alignment: .top) {
                quickPlayResultsOverlay
            }
            .task { await bootstrapInitialLibraryStateIfNeeded() }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task {
                    if didCompleteInitialLibraryBootstrap {
                        await loadLibraryMetadata()
                    } else {
                        await bootstrapInitialLibraryStateIfNeeded()
                    }
                }
            }
            .onChange(of: hasAppliedFirstLaunchDefaults) { _, _ in
                presentWelcomeTourIfReady()
            }
            .overlay {
#if canImport(UIKit)
                CantusTipTapCaptureView(isActive: isTourActive) {
                    handleTourTipInternalTap()
                }
                .allowsHitTesting(false)
#endif
            }
            .simultaneousGesture(TapGesture().onEnded {
                if quickPlayIsPresented {
                    dismissQuickPlay()
                }
            })
            .tipBackground(.clear)
            .tipCornerRadius(14)
            .tint(theme.color)
    }

#if os(iOS)
    private var platformConfiguredBaseLayer: some View {
        baseLayer
            .toolbar { playToolbarContent }
    }
#else
    private var platformConfiguredBaseLayer: some View {
        baseLayer
    }
#endif

#if os(iOS)
    @ToolbarContentBuilder
    private var playToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarLeading) {
            ToolbarIconButton(systemName: "gearshape", action: { menuState.presentSettings() }, size: 32, hitTargetSize: 32, iconScale: 1.0, accessibilityLabel: "Settings")
        }
        ToolbarItemGroup(placement: .principal) {
            quickPlayPrincipalSearchField
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            addPopoverButton
        }
    }
#endif

    private var addPopoverButton: some View {
#if os(macOS)
        Menu {
            Button("New Local Playlist") {
                performAddPopoverAction {
                    menuState.presentAddPlaylist(preferredTab: .local)
                }
            }
            Button("Add Apple Music Playlist") {
                performAddPopoverAction {
                    menuState.presentAddPlaylist(preferredTab: .appleMusic)
                }
            }
            Button("Import Atmosphere") {
                performAddPopoverAction {
                    menuState.presentImport(initialKind: .atmosphere)
                }
            }
            Button("Import Sound Effect") {
                performAddPopoverAction {
                    menuState.presentImport(initialKind: .sfx)
                }
            }
        } label: {
            Image(systemName: "plus")
                .symbolRenderingMode(.monochrome)
        }
        .menuIndicator(.hidden)
        .tint(.primary)
        .accessibilityLabel("Import")
#else
        ToolbarIconButton(systemName: "plus", action: { showAddPopover = true }, size: 32, hitTargetSize: 32, iconScale: 1.0, accessibilityLabel: "Import")
            .popoverTip(tipForTourStep(.fastImport), arrowEdge: .bottom)
            .popover(isPresented: $showAddPopover, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    AddPopoverActionButton(title: "New Local Playlist") {
                        performAddPopoverAction {
                            menuState.presentAddPlaylist(preferredTab: .local)
                        }
                    }
                    AddPopoverActionButton(title: "Add Apple Music Playlist") {
                        performAddPopoverAction {
                            menuState.presentAddPlaylist(preferredTab: .appleMusic)
                        }
                    }
                    AddPopoverActionButton(title: "Import Atmosphere") {
                        performAddPopoverAction {
                            menuState.presentImport(initialKind: .atmosphere)
                        }
                    }
                    AddPopoverActionButton(title: "Import Sound Effect") {
                        performAddPopoverAction {
                            menuState.presentImport(initialKind: .sfx)
                        }
                    }
                }
                .padding(.leading, 3)
                .padding(.trailing, 2)
                .padding(8)
                .frame(minWidth: 292, alignment: .leading)
                .presentationCompactAdaptation(.popover)
            }
#endif
    }

    private func performAddPopoverAction(_ action: @escaping () -> Void) {
        showAddPopover = false
        DispatchQueue.main.async {
            action()
        }
    }

    private struct AddPopoverActionButton: View {
        let title: String
        let action: () -> Void

        @EnvironmentObject private var theme: ThemeModel
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack {
                    Text(title)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                Capsule()
                    .fill(isHovered ? theme.color.opacity(0.18) : Color.clear)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.14)) {
                    isHovered = hovering
                }
            }
        }
    }

    private var quickPlayPrincipalSearchField: some View {
        quickPlayToolbarSearchField
            .frame(width: quickPlayPreferredWidth)
            .frame(minWidth: 96, maxWidth: 520)
        .popoverTip(tipForTourStep(.quickPlayFast), arrowEdge: .bottom)
    }

    private var quickPlaySecondarySearchRow: some View {
        HStack {
            Spacer(minLength: 0)
            quickPlayToolbarSearchField
                .frame(width: quickPlaySecondaryWidth)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .popoverTip(tipForTourStep(.quickPlayFast), arrowEdge: .bottom)
    }

    private var quickPlayToolbarSearchField: some View {
        HStack(spacing: quickPlayFieldSpacing) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            QuickPlayInlineTextField(
                text: $quickPlayQuery,
                isFocused: $quickPlayFieldFocused,
                isActive: $quickPlayIsPresented,
                onUp: { handleQuickPlayMove(step: -1) },
                onDown: { handleQuickPlayMove(step: 1) },
                onReturn: { handleQuickPlaySubmit() },
                onEscape: { dismissQuickPlay() }
            )
            if quickPlayIsPresented || quickPlayFieldFocused {
                Button(action: { dismissQuickPlay() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, quickPlayFieldHorizontalInset)
        .frame(height: 36)
        .cantusGlassEffectRegular(in: Capsule())
        .overlay {
            ZStack {
                if !quickPlayIsPresented {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { activateQuickPlay() }
                }
                Capsule()
                    .stroke(
                        quickPlayIsPresented ? theme.color.opacity(0.78) : Color.white.opacity(0.14),
                        lineWidth: quickPlayIsPresented ? 1.4 : 1.0
                    )
                    .shadow(
                        color: quickPlayIsPresented ? theme.color.opacity(0.22) : .clear,
                        radius: quickPlayIsPresented ? 6 : 0,
                        x: 0,
                        y: 0
                    )
            }
        }
    }

    private var sheetLayer: some View {
        PlaySheets(
            showPremiumUpgrade: $showPremiumUpgrade,
            editRequest: $editRequest,
            editPlaylistRequest: $editPlaylistRequest,
            onLibraryChange: { await loadLibraryMetadata() }
        ) {
            interactionLayer
        }
    }

    private var lifecycleLayer: some View {
        sheetLayer
            .overlay {
                if shouldShowFirstLaunchLoadCover {
                    theme.backgroundColor
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            .overlay {
                if showWelcomeTourSplash && !shouldShowFirstLaunchLoadCover {
                    CantusPlayModalOverlay {
                        CantusWelcomeTourSplashView(
                            onTakeTour: {
                                hasSeenCantusWelcomeTourSplash = true
                                showWelcomeTourSplash = false
                                startTour(resetProgress: true)
                            },
                            onSkip: {
                                hasSeenCantusWelcomeTourSplash = true
                                showWelcomeTourSplash = false
                            }
                        )
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .overlay {
                if showTourCompletionSplash {
                    CantusPlayModalOverlay {
                        CantusTourCompletionSplashView {
                            showTourCompletionSplash = false
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .alert(item: $pendingAlert) { alert in
                switch alert.kind {
                case .removeBookmark:
                    return Alert(
                        title: Text("Remove Bookmark?"),
                        message: Text("Remove Bookmark from \(alert.item)?"),
                        primaryButton: .destructive(Text("Yes")) {
                            bookmarks.toggleLoop(alert.item)
                        },
                        secondaryButton: .cancel()
                    )
                case .removeBookmarkSFX:
                    return Alert(
                        title: Text("Remove Bookmark?"),
                        message: Text("Remove Bookmark from \(alert.item)?"),
                        primaryButton: .destructive(Text("Yes")) {
                            bookmarks.toggleSFX(alert.item)
                        },
                        secondaryButton: .cancel()
                    )
                case .removeBookmarkPlaylist:
                    return Alert(
                        title: Text("Remove Bookmark?"),
                        message: Text("Remove Bookmark from \(alert.item)?"),
                        primaryButton: .destructive(Text("Yes")) {
                            bookmarks.togglePlaylist(alert.item)
                        },
                        secondaryButton: .cancel()
                    )
                }
            }
            .onAppear {
                backend.audioManager.reconcileAtmospheres(to: playback.playingLoops)
                backend.audioManager.reconcileSFX(to: playback.playingSFX)
                updateSFXDuckingState()
            }
            .onChange(of: menuState.replayTourRequestToken) { _, newValue in
                guard newValue != nil else { return }
                startTour(resetProgress: true)
            }
            .onChange(of: playback.playingLoops) { _, newValue in
                backend.audioManager.reconcileAtmospheres(to: newValue)
            }
            .onChange(of: playback.playingSFX) { _, newValue in
                backend.audioManager.reconcileSFX(to: newValue)
                updateSFXDuckingState(activeSFX: newValue)
            }
            .onChange(of: playback.sfxDuckingEnabled) { _, isEnabled in
                updateSFXDuckingState(duckingEnabled: isEnabled)
            }
            .onChange(of: musicPlayback.isPlaying) { _, _ in
                updateSFXDuckingState()
            }
            .onChange(of: musicPlayback.currentPlaylistItemId) { _, newValue in
                updateSFXDuckingState()
                guard let newValue else { return }
                guard let title = playlistTitlesById[newValue] else { return }
                if bookmarks.playlistBookmarks.contains(title) {
                    playback.markPlaylistPlayed(title)
                } else {
                    playback.addRecentPlaylist(title)
                }
            }
            .onDisappear {
                tourStepStatusTask?.cancel()
                tourStepStatusTask = nil
            }
    }

    private var shouldShowFirstLaunchLoadCover: Bool {
        showFirstLaunchLoadCover || (
            !didCompleteInitialLibraryBootstrap &&
            !hasAppliedFirstLaunchDefaults &&
            !hasSeenCantusWelcomeTourSplash
        )
    }

    private var isIpadLike: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
#else
        false
#endif
    }

    private var isWindowedIpad: Bool {
        guard isIpadLike else { return false }
#if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes
        let activeScene = scenes.first { $0.activationState == .foregroundActive }
        if let windowScene = activeScene as? UIWindowScene {
            return !windowScene.isFullScreen
        }
#endif
        return false
    }

    private var scrollBody: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    Spacer()
                        .frame(height: 0)

                    quickBoards

                    Color.clear
                        .frame(height: max(24, bottomDockHeight + 12))
                }
                .padding(.bottom, 24)
            }
            .contentMargins(.horizontal, playContentHorizontalPadding, for: .scrollContent)
            .simultaneousGesture(TapGesture().onEnded {
                if quickPlayIsPresented {
                    dismissQuickPlay()
                }
            })
            .onAppear { updateLayoutWidth(proxy.size.width) }
            .onChange(of: proxy.size.width) { _, newValue in
                updateLayoutWidth(newValue)
            }
            .onPreferenceChange(BottomDockHeightPreferenceKey.self) { newValue in
                if abs(bottomDockHeight - newValue) > 0.5 {
                    bottomDockHeight = newValue
                }
            }
#if os(macOS)
            .safeAreaInset(edge: .top) {
                quickPlaySecondarySearchRow
                    .padding(.horizontal, quickPlaySecondaryLayout.inset)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }
#endif
            .safeAreaInset(edge: .bottom) {
                bottomDock
                    .frame(width: layoutWidth > 0 ? layoutWidth : nil)
            }
            .ignoresSafeArea(isWindowedIpad ? .keyboard : [], edges: .bottom)
            .zIndex(1)
        }
    }

    private var bottomDock: some View {
        VStack(spacing: 12) {
            volumeSliders
            NowPlayingDock(
                openPlaylist: { openPlaylistPanel() },
                openPlaylistForTag: { filter in
                    openPlaylistPanel(filter: filter)
                },
                playbackProgress: musicPlayback.playbackProgress,
                tagsTip: tipForTourStep(.fastAccessTags),
                controlsTip: tipForTourStep(.controlIt)
            )
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .padding(.horizontal, playContentHorizontalPadding)
        .padding(.bottom, bottomDockBottomPadding)
        .frame(maxWidth: contentMaxWidth)
        .background {
            DockBackdropEffect()
        }
        .clipped()
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: BottomDockHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            if quickPlayIsPresented {
                dismissQuickPlay()
            }
        })
        .zIndex(1)
    }

    private var adaptiveHorizontalPadding: CGFloat {
        let base: CGFloat = 18
        guard layoutWidth > 0 else { return base }
        let scaled = layoutWidth * 0.04
        return min(base, max(8, scaled))
    }

    private var playContentHorizontalPadding: CGFloat {
#if os(macOS)
        18
#else
        adaptiveHorizontalPadding
#endif
    }

    private var bottomDockBottomPadding: CGFloat {
#if os(macOS)
        16
#else
        8
#endif
    }

    private var contentMaxWidth: CGFloat? {
        layoutWidth > 0 ? layoutWidth : nil
    }

    private var quickPlayPreferredWidth: CGFloat {
        let maxWidth: CGFloat = 520
        guard layoutWidth > 0 else { return maxWidth }
#if os(macOS)
        let reserved: CGFloat
        if layoutWidth <= 520 {
            reserved = 300
        } else if layoutWidth <= 700 {
            reserved = 320
        } else {
            reserved = 340
        }
        let available = layoutWidth - (adaptiveHorizontalPadding * 2) - reserved
        let clamped = min(maxWidth, max(96, available))
#else
        let reserved: CGFloat = isIpadLike ? 220 : 120
        let available = layoutWidth - (adaptiveHorizontalPadding * 2) - reserved
        let clamped = min(maxWidth, max(120, available))
#endif
        return floor(clamped / 10) * 10
    }

    private var usesSecondaryQuickPlaySearchOnMac: Bool {
#if os(macOS)
        true
#else
        false
#endif
    }

    private var quickPlaySecondaryMaxWidth: CGFloat {
#if os(macOS)
        448
#else
        520
#endif
    }

    private var quickPlaySecondaryMinWidth: CGFloat {
#if os(macOS)
        336
#else
        220
#endif
    }

    private var quickPlaySecondaryWidth: CGFloat {
#if os(macOS)
        quickPlaySecondaryLayout.width
#else
        return min(quickPlaySecondaryMaxWidth, max(quickPlaySecondaryMinWidth, quickPlayPreferredWidth))
#endif
    }

    private var quickPlaySecondaryLayout: (width: CGFloat, inset: CGFloat) {
#if os(macOS)
        let minWidth = quickPlaySecondaryMinWidth
        let maxWidth = quickPlaySecondaryMaxWidth
        let hardMinInset: CGFloat = 24
        let preferredInset = compactQuickPlayHorizontalInset
        guard layoutWidth > 0 else { return (minWidth, preferredInset) }

        let resolvedInset: CGFloat
        if layoutWidth >= minWidth + (preferredInset * 2) {
            resolvedInset = preferredInset
        } else if layoutWidth >= minWidth + (hardMinInset * 2) {
            resolvedInset = (layoutWidth - minWidth) / 2
        } else {
            resolvedInset = hardMinInset
        }

        let available = max(0, layoutWidth - (resolvedInset * 2))
        let resolvedWidth: CGFloat
        if available <= minWidth {
            resolvedWidth = available
        } else {
            resolvedWidth = min(maxWidth, max(minWidth, available))
        }
        return (resolvedWidth, resolvedInset)
#else
        return (quickPlaySecondaryWidth, adaptiveHorizontalPadding)
#endif
    }

    private var compactQuickPlayHorizontalInset: CGFloat {
#if os(macOS)
        guard layoutWidth > 0 else { return 24 }
        if layoutWidth <= 420 { return 24 }
        if layoutWidth <= 520 { return 26 }
        if layoutWidth <= 700 { return 28 }
        return min(36, max(28, layoutWidth * 0.04))
#else
        return adaptiveHorizontalPadding
#endif
    }

    private var quickPlayFieldHorizontalInset: CGFloat {
#if os(macOS)
        if usesSecondaryQuickPlaySearchOnMac {
            if quickPlaySecondaryWidth <= quickPlaySecondaryMinWidth + 24 { return 7 }
            if quickPlaySecondaryWidth <= quickPlaySecondaryMinWidth + 80 { return 9 }
            return 10
        }
        guard layoutWidth > 0 else { return 4 }
        if layoutWidth <= 420 { return 1 }
        if layoutWidth <= 520 { return 2 }
        if layoutWidth <= 640 { return 3 }
        if layoutWidth <= 760 { return 4 }
        return 5
#else
        return 12
#endif
    }

    private var quickPlayFieldSpacing: CGFloat {
#if os(macOS)
        layoutWidth > 0 && layoutWidth <= 520 ? 5 : 8
#else
        return 8
#endif
    }

    private var quickPlayOverlayWidth: CGFloat {
#if os(macOS)
        if usesSecondaryQuickPlaySearchOnMac {
            return min(520, max(180, quickPlaySecondaryLayout.width))
        }
#endif
        return quickPlayPreferredWidth
    }

    private func updateLayoutWidth(_ newValue: CGFloat) {
        let rounded = (newValue * 2).rounded() / 2
        if abs(layoutWidth - rounded) > 0.1 {
            layoutWidth = rounded
        }
    }

    private var quickBoards: some View {
        QuickBoardsView(
            availableWidth: max(0, layoutWidth - (playContentHorizontalPadding * 2)),
            order: $quickBoardOrder,
            dragging: $draggingQuickBoard,
            playlist: playlistSection,
            atmosphere: atmosphereSection,
            soundEffects: sfxSection
        )
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private static let quickBoardOrderKey = "playQuickBoardOrder"

    private static func loadQuickBoardOrder() -> [QuickBoardSection] {
        let saved = UserDefaults.standard.stringArray(forKey: quickBoardOrderKey) ?? []
        let mapped = saved.compactMap(QuickBoardSection.init(rawValue:))
        let missing = QuickBoardSection.allCases.filter { !mapped.contains($0) }
        let order = mapped + missing
        return order.isEmpty ? QuickBoardSection.allCases : order
    }

    private func persistQuickBoardOrder(_ order: [QuickBoardSection]) {
        let values = order.map(\.rawValue)
        UserDefaults.standard.set(values, forKey: Self.quickBoardOrderKey)
    }

    private var playlistSection: some View {
        PlaylistSectionView(
            showPlaylists: $menuState.showPlaylists,
            showPlaylistPanel: $menuState.showPlaylistPanel,
            playlistSectionTip: tipForTourStep(.bookmarksAndRecents),
            navigationTip: tipForTourStep(.navigateWithEase),
            headerColor: theme.headerColor,
            waveformStyle: theme.waveformStyle,
            isPlaying: musicPlayback.isPlaying,
            isStartingPlayback: musicPlayback.isStartingPlayback,
            premiumIsPremium: premium.isPremium,
            playlistDisplayItems: playlistDisplayItems,
            nonBookmarkedPlaylistItems: nonBookmarkedPlaylistItems,
            recentNonBookmarkedSet: recentNonBookmarkedPlaylistSet,
            bookmarkList: bookmarks.playlistBookmarkList,
            playlistListHeight: playlistListHeight,
            isPlaylistPlaying: { isPlaylistPlaying($0) },
            playlistSource: { playlistSource(for: $0) ?? .local },
            recencyText: { recencyText(for: $0, kind: .playlist) },
            playlistItemId: { playlistItemIds[$0] },
            onTapNonBookmarked: { item, source in
                handleNonBookmarkedPlaylistTap(item: item, source: source)
            },
            onTapBookmarked: { item, source in
                handleBookmarkedPlaylistTap(item: item, source: source)
            },
            onRemoveRecent: { playback.removeRecentPlaylist($0) },
            onAddBookmarkFromRecent: { item in
                bookmarks.togglePlaylist(item)
                playback.removeRecentPlaylist(item)
            },
            onEditPlaylist: { item, itemId in
                editPlaylistRequest = EditPlaylistRequest(itemId: itemId, title: item)
            },
            onRemoveBookmark: { item in
                pendingAlert = PendingAlert(kind: .removeBookmarkPlaylist, item: item)
            },
            onRemoveBookmarkDirect: { bookmarks.togglePlaylist($0) },
            onMoveBookmarks: { indices, newOffset in
                bookmarks.movePlaylistBookmarks(fromOffsets: indices, toOffset: newOffset)
            }
        )
    }

    private func handleNonBookmarkedPlaylistTap(item: String, source: PlaylistSource) {
        if musicPlayback.isStartingPlayback {
            return
        }
        if source == .local {
            guard let itemId = playlistItemIds[item] else { return }
            let wasPlaying = musicPlayback.isPlayingPlaylist(itemId)
            Task { await musicPlayback.togglePlaylist(itemId: itemId, title: item) }
            if !wasPlaying {
                if !bookmarks.playlistBookmarks.contains(item) {
                    playback.addRecentPlaylist(item)
                } else {
                    playback.markPlaylistPlayed(item)
                }
            }
        } else if premium.isPremium {
            guard let itemId = playlistItemIds[item] else { return }
            let wasPlaying = musicPlayback.isPlayingPlaylist(itemId)
            Task { await musicPlayback.togglePlaylist(itemId: itemId, title: item) }
            if !wasPlaying {
                if !bookmarks.playlistBookmarks.contains(item) {
                    playback.addRecentPlaylist(item)
                } else {
                    playback.markPlaylistPlayed(item)
                }
            }
        } else {
            showPremiumUpgrade = true
        }
    }

    private func handleBookmarkedPlaylistTap(item: String, source: PlaylistSource) {
        if musicPlayback.isStartingPlayback {
            return
        }
        if source == .local {
            guard let itemId = playlistItemIds[item] else { return }
            let wasPlaying = musicPlayback.isPlayingPlaylist(itemId)
            Task { await musicPlayback.togglePlaylist(itemId: itemId, title: item) }
            if !wasPlaying {
                playback.markPlaylistPlayed(item)
            }
        } else if premium.isPremium {
            guard let itemId = playlistItemIds[item] else { return }
            let wasPlaying = musicPlayback.isPlayingPlaylist(itemId)
            Task { await musicPlayback.togglePlaylist(itemId: itemId, title: item) }
            if !wasPlaying {
                playback.markPlaylistPlayed(item)
            }
        } else {
            showPremiumUpgrade = true
        }
    }

    private var atmosphereSection: some View {
        AtmosphereSectionView(
            showAtmospheres: $menuState.showAtmospheres,
            showAtmospherePanel: $menuState.showAtmospherePanel,
            pendingAlert: $pendingAlert,
            headerColor: theme.headerColor,
            waveformStyle: theme.waveformStyle,
            isPlaying: !playback.playingLoops.isEmpty,
            atmosphereDisplayItems: atmosphereDisplayItems,
            nonBookmarkedAtmosphereItems: nonBookmarkedAtmosphereItems,
            recentNonBookmarkedSet: recentNonBookmarkedSet,
            bookmarkList: bookmarks.loopBookmarkList,
            listHeight: atmosphereListHeight,
            containsMusic: { atmosphereContainsMusic[$0] ?? false },
            isLoopPlaying: { playback.isLoopPlaying($0) },
            recencyText: { recencyText(for: $0, kind: .loop) },
            onToggleLoop: { item in
                let wasPlaying = playback.isLoopPlaying(item)
                playback.toggleLoop(item)
                if wasPlaying {
                    backend.audioManager.stopAtmosphere(title: item)
                } else {
                    backend.audioManager.playAtmosphere(title: item)
                }
            },
            onRemoveRecent: { playback.removeRecentLoop($0) },
            onAddBookmarkFromRecent: { item in
                bookmarks.toggleLoop(item)
                playback.removeRecentLoop(item)
            },
            onEditItem: { item, itemId in
                editRequest = EditRequest(itemId: itemId, title: item, kind: .atmosphere)
            },
            onRemoveBookmark: { item in
                pendingAlert = PendingAlert(kind: .removeBookmark, item: item)
            },
            onRemoveBookmarkDirect: { bookmarks.toggleLoop($0) },
            onMoveBookmarks: { indices, newOffset in
                bookmarks.moveLoopBookmarks(fromOffsets: indices, toOffset: newOffset)
            },
            itemIdForTitle: { atmosphereItemIds[$0] }
        )
    }

    private var sfxSection: some View {
        SFXSectionView(
            showSoundEffects: $menuState.showSoundEffects,
            showSoundboardPanel: $menuState.showSoundboardPanel,
            pendingAlert: $pendingAlert,
            headerColor: theme.headerColor,
            waveformStyle: theme.waveformStyle,
            isPlaying: !playback.playingSFX.isEmpty,
            sfxDisplayItems: sfxDisplayItems,
            nonBookmarkedSFXItems: nonBookmarkedSFXItems,
            recentNonBookmarkedSet: recentNonBookmarkedSFXSet,
            bookmarkList: bookmarks.sfxBookmarkList,
            listHeight: sfxListHeight,
            isSFXPlaying: { playback.isSFXPlaying($0) },
            recencyText: { recencyText(for: $0, kind: .sfx) },
            onToggleSFX: { item in
                let wasPlaying = playback.isSFXPlaying(item)
                playback.toggleSFX(item)
                if wasPlaying {
                    backend.audioManager.stopSFX(title: item)
                } else {
                    backend.audioManager.playSFX(title: item)
                }
            },
            onRemoveRecent: { playback.removeRecentSFX($0) },
            onAddBookmarkFromRecent: { item in
                bookmarks.toggleSFX(item)
                playback.removeRecentSFX(item)
            },
            onEditItem: { item, itemId in
                editRequest = EditRequest(itemId: itemId, title: item, kind: .sfx)
            },
            onRemoveBookmark: { item in
                pendingAlert = PendingAlert(kind: .removeBookmarkSFX, item: item)
            },
            onRemoveBookmarkDirect: { bookmarks.toggleSFX($0) },
            onMoveBookmarks: { indices, newOffset in
                bookmarks.moveSFXBookmarks(fromOffsets: indices, toOffset: newOffset)
            },
            itemIdForTitle: { sfxItemIds[$0] }
        )
    }

    private var atmosphereDisplayItems: [String] {
        nonBookmarkedAtmosphereItems + bookmarks.loopBookmarkList
    }


    private var nonBookmarkedAtmosphereItems: [String] {
        recentNonBookmarkedList
    }

    private func bootstrapInitialLibraryStateIfNeeded() async {
        guard !didCompleteInitialLibraryBootstrap else { return }
        if !hasAppliedFirstLaunchDefaults && !hasSeenCantusWelcomeTourSplash {
            showFirstLaunchLoadCover = true
        }
        await backend.audioManager.prepareAudioSessionForPlayback()
        await backend.seedIfNeeded()
        await loadLibraryMetadata()
        await ensureInitialNowPlayingPlaylistIfNeeded()
        didCompleteInitialLibraryBootstrap = true
        showFirstLaunchLoadCover = false
        presentWelcomeTourIfReady()
    }

    private func loadLibraryMetadata(attempt: Int = 0) async {
        let playlistItems = try? await backend.libraryRepository.fetchItems(kind: .music, filters: Filters(), sort: .titleAsc)
        let playlistSourceMap = try? await backend.musicRepository.playlistSourceMap()
        var resolvedPlaylistSources = playlistSourceMap ?? [:]
        if let playlistItems {
            for item in playlistItems where resolvedPlaylistSources[item.id] == nil {
                guard let uuid = UUID(uuidString: item.id) else { continue }
                if let source = try? await backend.musicRepository.playlistSource(for: uuid) {
                    resolvedPlaylistSources[item.id] = source
                }
            }
        }

        let atmosphereItems = try? await backend.libraryRepository.fetchItems(kind: .atmosphere, filters: Filters(), sort: .titleAsc)
        let sfxItems = try? await backend.libraryRepository.fetchItems(kind: .sfx, filters: Filters(), sort: .titleAsc)

        await MainActor.run {
            if let atmosphereItems {
                atmosphereContainsMusic = Dictionary(uniqueKeysWithValues: atmosphereItems.map { ($0.title, $0.containsMusic) })
                atmosphereItemIds = Dictionary(uniqueKeysWithValues: atmosphereItems.map { ($0.title, $0.id) })
            }
            if let sfxItems {
                sfxItemIds = Dictionary(uniqueKeysWithValues: sfxItems.map { ($0.title, $0.id) })
            }
            if let playlistItems {
                playlistItemIds = Dictionary(uniqueKeysWithValues: playlistItems.map { ($0.title, $0.id) })
                playlistTitlesById = Dictionary(uniqueKeysWithValues: playlistItems.map { ($0.id, $0.title) })
                playlistSourcesById = resolvedPlaylistSources
            }
        }

        if let playlistItems {
            Task {
                guard premium.isPremium else { return }
                guard MusicAuthorization.currentStatus == .authorized else { return }
                var playlistIdsToPrefetch: [String] = []
                playlistIdsToPrefetch.reserveCapacity(playlistItems.count)
                for item in playlistItems {
                    guard let itemId = UUID(uuidString: item.id) else { continue }
                    if let playlistId = try? await backend.musicRepository.playlistID(for: itemId) {
                        playlistIdsToPrefetch.append(playlistId)
                    }
                }
                if !playlistIdsToPrefetch.isEmpty {
                    await musicPlayback.prefetchPlaylists(playlistIds: playlistIdsToPrefetch)
                }
            }
        }

        if (atmosphereItems == nil || sfxItems == nil || playlistItems == nil) && attempt < 2 {
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await loadLibraryMetadata(attempt: attempt + 1)
            }
        }
    }

    private func openPlaylistPanel(filter: PlaylistPanelView.InitialFilter? = nil) {
        menuState.presentPlaylistPanel(initialFilter: filter)
    }

    private var recentNonBookmarkedList: [String] {
        let libraryTitles = Set(atmosphereItemIds.keys)
        let playing = playback.playingLoops.filter { !bookmarks.loopBookmarks.contains($0) }
        let playingOrdered = playback.recentLoops.filter { playing.contains($0) && libraryTitles.contains($0) }
        let missingPlaying = playing.filter { !playingOrdered.contains($0) }.sorted()
        let playingList = playingOrdered + missingPlaying
        let slotsRemaining = max(0, 6 - playingList.count)
        guard slotsRemaining > 0 else {
            return playingList
        }
        let recent = playback.recentLoops.filter { libraryTitles.contains($0) && !bookmarks.loopBookmarks.contains($0) && !playing.contains($0) }
        let limitedRecent = Array(recent.prefix(slotsRemaining))
        return playingList + limitedRecent
    }

    private var recentNonBookmarkedSet: Set<String> {
        Set(recentNonBookmarkedList)
    }

    private var sfxDisplayItems: [String] {
        nonBookmarkedSFXItems + bookmarks.sfxBookmarkList
    }

    private var nonBookmarkedSFXItems: [String] {
        recentNonBookmarkedSFXList
    }

    private var playlistDisplayItems: [String] {
        nonBookmarkedPlaylistItems + bookmarks.playlistBookmarkList
    }

    private var nonBookmarkedPlaylistItems: [String] {
        recentNonBookmarkedPlaylistList.filter { !bookmarks.playlistBookmarks.contains($0) }
    }

    private var recentNonBookmarkedSFXList: [String] {
        let libraryTitles = Set(sfxItemIds.keys)
        let playing = playback.playingSFX.filter { !bookmarks.sfxBookmarks.contains($0) }
        let playingOrdered = playback.recentSFX.filter { playing.contains($0) && libraryTitles.contains($0) }
        let missingPlaying = playing.filter { !playingOrdered.contains($0) }
        let playingList = playingOrdered + missingPlaying
        let slotsRemaining = max(0, 6 - playingList.count)
        guard slotsRemaining > 0 else {
            return playingList
        }
        let recent = playback.recentSFX.filter { libraryTitles.contains($0) && !bookmarks.sfxBookmarks.contains($0) && !playing.contains($0) }
        let limitedRecent = Array(recent.prefix(slotsRemaining))
        return playingList + limitedRecent
    }

    private var recentNonBookmarkedSFXSet: Set<String> {
        Set(recentNonBookmarkedSFXList)
    }

    private var recentNonBookmarkedPlaylistList: [String] {
        let libraryTitles = Set(playlistItemIds.keys)
        let playingTitle = currentPlayingPlaylistTitle
        let playingIsBookmarked = playingTitle.map { bookmarks.playlistBookmarks.contains($0) } ?? false
        let playingSet = (!playingIsBookmarked ? playingTitle.map { Set([$0]) } : nil) ?? Set<String>()
        let playingOrdered = playback.recentPlaylists.filter { playingSet.contains($0) && libraryTitles.contains($0) && !bookmarks.playlistBookmarks.contains($0) }
        let missingPlaying = playingTitle.flatMap { playingOrdered.contains($0) ? nil : $0 }
        let playingList = missingPlaying.map { playingOrdered + [$0] } ?? playingOrdered
        let slotsRemaining = max(0, 6 - playingList.count)
        guard slotsRemaining > 0 else {
            return playingList
        }
        let recent = playback.recentPlaylists.filter {
            libraryTitles.contains($0) && !bookmarks.playlistBookmarks.contains($0) && !playingSet.contains($0)
        }
        let limitedRecent = Array(recent.prefix(slotsRemaining))
        return (playingList + limitedRecent).filter { !bookmarks.playlistBookmarks.contains($0) }
    }

    private var recentNonBookmarkedPlaylistSet: Set<String> {
        Set(recentNonBookmarkedPlaylistList)
    }

    private var currentPlayingPlaylistTitle: String? {
        guard let id = musicPlayback.currentPlaylistItemId else { return nil }
        return playlistTitlesById[id]
    }

    private func isPlaylistPlaying(_ title: String) -> Bool {
        guard let id = playlistItemIds[title] else { return false }
        return musicPlayback.isPlayingPlaylist(id)
    }

    private func playlistSource(for title: String) -> PlaylistSource? {
        guard let id = playlistItemIds[title] else { return nil }
        return playlistSourcesById[id]
    }

    private enum PlaybackKind {
        case loop
        case sfx
        case playlist
    }

    private func recencyText(for title: String, kind: PlaybackKind) -> String? {
        let isPlaying: Bool
        switch kind {
        case .loop:
            isPlaying = playback.isLoopPlaying(title)
        case .sfx:
            isPlaying = playback.isSFXPlaying(title)
        case .playlist:
            isPlaying = isPlaylistPlaying(title)
        }
        guard !isPlaying else { return nil }
        let lastPlayed: Date?
        switch kind {
        case .loop:
            lastPlayed = playback.lastPlayedLoop(title)
        case .sfx:
            lastPlayed = playback.lastPlayedSFX(title)
        case .playlist:
            lastPlayed = playback.lastPlayedPlaylist(title)
        }
        guard let lastPlayed else { return nil }
        let interval = max(0, now.timeIntervalSince(lastPlayed))
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

    private static let minuteTicker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var atmosphereListHeight: CGFloat {
        listHeight(
            nonBookmarkedItems: nonBookmarkedAtmosphereItems,
            bookmarkedItems: bookmarks.loopBookmarkList
        )
    }

    private var sfxListHeight: CGFloat {
        listHeight(
            nonBookmarkedItems: nonBookmarkedSFXItems,
            bookmarkedItems: bookmarks.sfxBookmarkList
        )
    }

    private var playlistListHeight: CGFloat {
        listHeight(
            nonBookmarkedItems: nonBookmarkedPlaylistItems,
            bookmarkedItems: bookmarks.playlistBookmarkList
        )
    }

    private var playSectionListRowSpacing: CGFloat {
#if os(macOS)
        2
#else
        6
#endif
    }

    private var playSectionListBottomInset: CGFloat {
#if os(macOS)
        4
#else
        6
#endif
    }

    private func listHeight(nonBookmarkedItems: [String], bookmarkedItems: [String]) -> CGFloat {
        let nonBookmarkedCount = nonBookmarkedItems.count
        let bookmarkedCount = bookmarkedItems.count
        guard nonBookmarkedCount > 0 || bookmarkedCount > 0 else { return 0 }
        let headerRows = (nonBookmarkedCount > 0 ? 1 : 0) + (bookmarkedCount > 0 ? 1 : 0)
        let rowHeights = (nonBookmarkedItems + bookmarkedItems).map(playRowHeight(for:))
        let contentHeight = rowHeights.reduce(0, +) + CGFloat(headerRows) * 36
        let totalRows = rowHeights.count + headerRows
        let totalSpacing = max(0, CGFloat(totalRows - 1)) * playSectionListRowSpacing
        return contentHeight + totalSpacing + playSectionListBottomInset
    }

    private func playRowHeight(for title: String) -> CGFloat {
        title.count > playRowMultilineThreshold ? 52 : 36
    }

    private var playRowMultilineThreshold: Int {
#if os(macOS)
        let spacing: CGFloat = 12
        let availableWidth = max(0, layoutWidth - (playContentHorizontalPadding * 2))
        guard availableWidth > 0 else { return 22 }
        let columns = quickBoardColumnCount(for: availableWidth)
        let cardWidth = (availableWidth - CGFloat(max(0, columns - 1)) * spacing) / CGFloat(max(columns, 1))
        switch cardWidth {
        case ..<330:
            return 18
        case ..<380:
            return 22
        case ..<440:
            return 26
        default:
            return 30
        }
#else
        return 26
#endif
    }

    private func quickBoardColumnCount(for width: CGFloat) -> Int {
        let spacing: CGFloat = 12
        let minCardWidth: CGFloat = 340
        let available = max(0, width)
        let rawCount = Int((available + spacing) / (minCardWidth + spacing))
        return min(3, max(1, rawCount))
    }

    private var isAppleMusicPlaylistPlaying: Bool {
        musicPlayback.isPlayingAppleMusic
    }

    private func updateSFXDuckingState(activeSFX: Set<String>? = nil, duckingEnabled: Bool? = nil) {
        let active = activeSFX ?? playback.playingSFX
        let enabled = duckingEnabled ?? playback.sfxDuckingEnabled
        let shouldDuck = enabled && !active.isEmpty
        backend.audioManager.setSFXDuckingActive(shouldDuck)
        musicPlayback.setSFXDuckingActive(shouldDuck)
    }

    private var volumeSliders: some View {
        VStack(spacing: 10) {
            MixHeaderRow(
                label: "Mix",
                value: $playback.masterVolume,
                isExpanded: $menuState.showVolumeSliders
            )
            if menuState.showVolumeSliders {
                if isAppleMusicPlaylistPlaying {
                    DisabledMusicSliderRow(
                        label: "Music",
                        note: "Apple Music Playlist volume can only be controlled by the Mix slider and device volume controls.",
                        value: 1.0
                    )
                } else {
                    SliderRow(label: "Music", value: $playback.musicVolume)
                }
                SliderRow(label: "Atmosphere", value: $playback.atmosphereVolume)
                SliderRow(
                    label: "SFX",
                    value: $playback.sfxVolume,
                    modeToggle: $playback.sfxDuckingEnabled,
                    duckingTip: tipForTourStep(.instantDucking)
                )
            }
        }
        .popoverTip(tipForTourStep(.mixItUp), arrowEdge: .top)
        .padding(12)
        .cantusGlassEffectRegular(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            backend.audioManager.syncMasterVolumeWithSystem()
            let systemVolume = backend.audioManager.currentSystemVolumeValue()
            if abs(playback.masterVolume - systemVolume) > 0.0005 {
                playback.masterVolume = systemVolume
            }
            musicPlayback.setMasterVolume(playback.masterVolume)
            backend.audioManager.setMusicVolume(playback.musicVolume)
            musicPlayback.setMusicVolume(playback.musicVolume)
            backend.audioManager.setAtmosphereVolume(playback.atmosphereVolume)
            backend.audioManager.setSFXVolume(playback.sfxVolume)
        }
        .onReceive(NotificationCenter.default.publisher(for: AudioPlaybackManager.systemVolumeDidChangeNotification)) { notification in
            let updatedVolume = (notification.userInfo?[AudioPlaybackManager.systemVolumeUserInfoKey] as? NSNumber)?.doubleValue
            guard let updatedVolume else { return }
            let clamped = min(max(updatedVolume, 0), 1)
            if abs(playback.masterVolume - clamped) > 0.0005 {
                playback.masterVolume = clamped
            }
        }
        .onChange(of: playback.masterVolume) { _, newValue in
            backend.audioManager.setMasterVolume(newValue)
            musicPlayback.setMasterVolume(newValue)
        }
        .onChange(of: playback.musicVolume) { _, newValue in
            backend.audioManager.setMusicVolume(newValue)
            musicPlayback.setMusicVolume(newValue)
        }
        .onChange(of: playback.atmosphereVolume) { _, newValue in
            backend.audioManager.setAtmosphereVolume(newValue)
        }
        .onChange(of: playback.sfxVolume) { _, newValue in
            backend.audioManager.setSFXVolume(newValue)
        }
    }

    private struct QuickPlayResult: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let kind: LibraryKind
        let containsMusic: Bool
    }

    private var quickPlayResultsOverlay: some View {
        QuickPlayResultsOverlay(
            isPresented: $quickPlayIsPresented,
            query: quickPlayQuery,
            results: quickPlayResults,
            selectedResultID: $quickPlaySelectedResultID,
            maxWidth: quickPlayOverlayWidth
        ) { result in
            handleQuickPlaySelection(result)
        }
        .padding(.top, quickPlayResultsTopOffset)
    }

    private var quickPlayResultsTopOffset: CGFloat {
#if os(macOS)
        usesSecondaryQuickPlaySearchOnMac ? 52 : 6
#else
        6
#endif
    }

    private struct QuickPlayRow: View {
        let result: QuickPlayResult

        private var kindLabel: String {
            switch result.kind {
            case .music:
                return "Playlist"
            case .atmosphere:
                return "Atmosphere"
            case .sfx:
                return "SFX"
            }
        }

        private var kindIcon: String {
            switch result.kind {
            case .music:
                return "music.note.list"
            case .atmosphere:
                return "wind"
            case .sfx:
                return "speaker.wave.2"
            }
        }

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: kindIcon)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.body)
                    if let subtitle = result.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(kindLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
    }

    private struct QuickPlayResultsOverlay: View {
        @Binding var isPresented: Bool
        let query: String
        let results: [QuickPlayResult]
        @Binding var selectedResultID: String?
        let maxWidth: CGFloat
        let onSelect: (QuickPlayResult) -> Void

        var body: some View {
            Group {
                if isPresented {
                    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            if results.isEmpty {
                                Text("No results")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                            } else {
                                ForEach(results.prefix(8)) { result in
                                    let isSelected = selectedResultID == result.id
                                    QuickPlayRow(result: result)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(isSelected ? Color.primary.opacity(0.12) : Color.clear)
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedResultID = result.id
                                            onSelect(result)
                                        }
                                }
                            }
                        }
                        .padding(8)
                        .cantusGlassEffectRegular(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .frame(width: maxWidth)
                        .padding(.top, 6)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .clipped()
        }
    }

    private struct PlaylistSectionView: View {
        @Binding var showPlaylists: Bool
        @Binding var showPlaylistPanel: Bool
        let playlistSectionTip: (any Tip)?
        let navigationTip: (any Tip)?
        let headerColor: Color
        let waveformStyle: AnyShapeStyle
        let isPlaying: Bool
        let isStartingPlayback: Bool
        let premiumIsPremium: Bool
        let playlistDisplayItems: [String]
        let nonBookmarkedPlaylistItems: [String]
        let recentNonBookmarkedSet: Set<String>
        let bookmarkList: [String]
        let playlistListHeight: CGFloat
        let isPlaylistPlaying: (String) -> Bool
        let playlistSource: (String) -> PlaylistSource
        let recencyText: (String) -> String?
        let playlistItemId: (String) -> String?
        let onTapNonBookmarked: (String, PlaylistSource) -> Void
        let onTapBookmarked: (String, PlaylistSource) -> Void
        let onRemoveRecent: (String) -> Void
        let onAddBookmarkFromRecent: (String) -> Void
        let onEditPlaylist: (String, String) -> Void
        let onRemoveBookmark: (String) -> Void
        let onRemoveBookmarkDirect: (String) -> Void
        let onMoveBookmarks: (IndexSet, Int) -> Void

        var body: some View {
            VStack(spacing: 6) {
                header
                if showPlaylists {
                    let nonBookmarkedCount = nonBookmarkedPlaylistItems.count
                    if playlistDisplayItems.isEmpty {
                        Text("No playlists yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        ZStack {
                            List {
                                if nonBookmarkedCount > 0 {
                                    listSectionHeader(systemName: "clock.fill", title: "Recents")
                                }

                                ForEach(nonBookmarkedPlaylistItems, id: \.self) { item in
                                    let source = playlistSource(item)
                                    let canPlay = source == .local || premiumIsPremium
                                    PlayRow(
                                        title: item,
                                        isPlaying: isPlaylistPlaying(item),
                                        infoItemId: playlistItemId(item),
                                        infoPlacement: .afterBadge,
                                        containsMusic: false,
                                        badgeText: source.label,
                                        showRecent: recentNonBookmarkedSet.contains(item),
                                        recencyText: recencyText(item),
                                        isDimmed: !canPlay,
                                        titleLineLimit: 2,
                                        backgroundTint: headerColor,
                                        backgroundTintOpacity: 0.2,
                                        onTap: {
                                            guard !isStartingPlayback else { return }
                                            onTapNonBookmarked(item, source)
                                        }
                                    )
                                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            onRemoveRecent(item)
                                        } label: {
                                            Label("Forget", systemImage: "clock.badge.xmark")
                                        }
                                        .tint(headerColor)
                                    }
                                    .contextMenu {
                                        Button {
                                            onAddBookmarkFromRecent(item)
                                        } label: {
                                            Label("Add to Bookmarks", systemImage: "bookmark")
                                        }
                                        Button {
                                            if let itemId = playlistItemId(item) {
                                                onEditPlaylist(item, itemId)
                                            }
                                        } label: {
                                            Label("Edit Properties", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            onRemoveRecent(item)
                                        } label: {
                                            Label("Remove from Recents", systemImage: "clock.badge.xmark")
                                        }
                                    }
                                }

                                if !bookmarkList.isEmpty {
                                    listSectionHeader(
                                        systemName: "bookmark.fill",
                                        title: "Bookmarks (\(bookmarkList.count))"
                                    )
                                }

                                ForEach(bookmarkList, id: \.self) { item in
                                    let source = playlistSource(item)
                                    let canPlay = source == .local || premiumIsPremium
                                    PlayRow(
                                        title: item,
                                        isPlaying: isPlaylistPlaying(item),
                                        infoItemId: playlistItemId(item),
                                        infoPlacement: .afterBadge,
                                        containsMusic: false,
                                        badgeText: source.label,
                                        showRecent: false,
                                        showBookmark: true,
                                        recencyText: recencyText(item),
                                        isDimmed: !canPlay,
                                        titleLineLimit: 2,
                                        backgroundTint: headerColor,
                                        backgroundTintOpacity: 0.2,
                                        onTap: {
                                            guard !isStartingPlayback else { return }
                                            onTapBookmarked(item, source)
                                        }
                                    )
                                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            onRemoveBookmark(item)
                                        } label: {
                                            Label("Unmark", systemImage: "bookmark.slash")
                                        }
                                        .tint(headerColor)
                                    }
                                    .contextMenu {
                                        Button {
                                            onRemoveBookmarkDirect(item)
                                        } label: {
                                            Label("Remove from Bookmarks", systemImage: "bookmark.slash")
                                        }
                                        Button {
                                            if let itemId = playlistItemId(item) {
                                                onEditPlaylist(item, itemId)
                                            }
                                        } label: {
                                            Label("Edit Properties", systemImage: "pencil")
                                        }
                                    }
                                }
                                .onMove { indices, newOffset in
                                    onMoveBookmarks(indices, newOffset)
                                }
                            }
                            .listStyle(.plain)
                            .environment(\.defaultMinListRowHeight, 36)
                            #if os(iOS)
                            .listRowSpacing(6)
                            .environment(\.editMode, .constant(.inactive))
                            .hoverEffectDisabled(true)
                            #endif
                            .frame(maxWidth: .infinity, minHeight: playlistListHeight, maxHeight: playlistListHeight)
                            .clipped()
                            .scrollContentBackground(.hidden)
                            .scrollDisabled(true)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: nonBookmarkedPlaylistItems)
                        }
                        .frame(maxWidth: .infinity, minHeight: playlistListHeight, maxHeight: playlistListHeight)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .background(headerColor.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(headerColor, lineWidth: 1))
            .popoverTip(playlistSectionTip, arrowEdge: .top)
            .animation(.easeInOut(duration: 0.25), value: showPlaylists)
        }

        private var header: some View {
            HStack(spacing: 8) {
                Button(action: { withAnimation(.easeInOut) { showPlaylists.toggle() } }) {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(headerColor)
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(showPlaylists ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: showPlaylists)
                }
                .buttonStyle(.plain)

                Button(action: { withAnimation(.easeInOut) { showPlaylists.toggle() } }) {
                    HStack(spacing: 6) {
                        Text("Playlists")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(headerColor)
                        WaveformIndicator(style: waveformStyle, isActive: isPlaying)
                            .frame(width: 18, height: 14)
                    }
                }
                .buttonStyle(.plain)

                Spacer()
                EllipsisGlassIconButton(action: { showPlaylistPanel = true })
                    .popoverTip(navigationTip, arrowEdge: .top)
            }
            .padding(8)
        }

        private func listSectionHeader(systemName: String, title: String) -> some View {
            HStack {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private struct AtmosphereSectionView: View {
        @Binding var showAtmospheres: Bool
        @Binding var showAtmospherePanel: Bool
        @Binding var pendingAlert: PendingAlert?
        let headerColor: Color
        let waveformStyle: AnyShapeStyle
        let isPlaying: Bool
        let atmosphereDisplayItems: [String]
        let nonBookmarkedAtmosphereItems: [String]
        let recentNonBookmarkedSet: Set<String>
        let bookmarkList: [String]
        let listHeight: CGFloat
        let containsMusic: (String) -> Bool
        let isLoopPlaying: (String) -> Bool
        let recencyText: (String) -> String?
        let onToggleLoop: (String) -> Void
        let onRemoveRecent: (String) -> Void
        let onAddBookmarkFromRecent: (String) -> Void
        let onEditItem: (String, String) -> Void
        let onRemoveBookmark: (String) -> Void
        let onRemoveBookmarkDirect: (String) -> Void
        let onMoveBookmarks: (IndexSet, Int) -> Void
        let itemIdForTitle: (String) -> String?

        var body: some View {
            VStack(spacing: 6) {
                header
                if showAtmospheres {
                    let nonBookmarkedCount = nonBookmarkedAtmosphereItems.count
                    if atmosphereDisplayItems.isEmpty {
                        Text("No bookmarks yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        ZStack {
                            List {
                                if nonBookmarkedCount > 0 {
                                    listSectionHeader(systemName: "clock.fill", title: "Recents")
                                }

                                ForEach(nonBookmarkedAtmosphereItems, id: \.self) { item in
                                    PlayRow(
                                        title: item,
                                        isPlaying: isLoopPlaying(item),
                                        infoItemId: itemIdForTitle(item),
                                        containsMusic: containsMusic(item),
                                        showRecent: recentNonBookmarkedSet.contains(item),
                                        recencyText: recencyText(item),
                                        backgroundTint: .gray,
                                        inactiveBackgroundTintOpacity: 0.16,
                                        onTap: {
                                            onToggleLoop(item)
                                        }
                                    )
                                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            onRemoveRecent(item)
                                        } label: {
                                            Label("Forget", systemImage: "clock.badge.xmark")
                                        }
                                        .tint(headerColor)
                                    }
                                    .contextMenu {
                                        Button {
                                            onAddBookmarkFromRecent(item)
                                        } label: {
                                            Label("Add to Bookmarks", systemImage: "bookmark")
                                        }
                                        Button {
                                            if let itemId = itemIdForTitle(item) {
                                                onEditItem(item, itemId)
                                            }
                                        } label: {
                                            Label("Edit Properties", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            onRemoveRecent(item)
                                        } label: {
                                            Label("Remove from Recents", systemImage: "clock.badge.xmark")
                                        }
                                    }
                                }

                                if !bookmarkList.isEmpty {
                                    listSectionHeader(
                                        systemName: "bookmark.fill",
                                        title: "Bookmarks (\(bookmarkList.count))"
                                    )
                                }

                                ForEach(bookmarkList, id: \.self) { item in
                                    PlayRow(
                                        title: item,
                                        isPlaying: isLoopPlaying(item),
                                        infoItemId: itemIdForTitle(item),
                                        containsMusic: containsMusic(item),
                                        showRecent: false,
                                        showBookmark: true,
                                        recencyText: recencyText(item),
                                        backgroundTint: .gray,
                                        inactiveBackgroundTintOpacity: 0.16,
                                        onTap: {
                                            onToggleLoop(item)
                                        }
                                    )
                                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            onRemoveBookmark(item)
                                        } label: {
                                            Label("Unmark", systemImage: "bookmark.slash")
                                        }
                                        .tint(headerColor)
                                    }
                                    .contextMenu {
                                        Button {
                                            onRemoveBookmarkDirect(item)
                                        } label: {
                                            Label("Remove from Bookmarks", systemImage: "bookmark.slash")
                                        }
                                        Button {
                                            if let itemId = itemIdForTitle(item) {
                                                onEditItem(item, itemId)
                                            }
                                        } label: {
                                            Label("Edit Properties", systemImage: "pencil")
                                        }
                                    }
                                }
                                .onMove { indices, newOffset in
                                    onMoveBookmarks(indices, newOffset)
                                }
                            }
                            .listStyle(.plain)
                            .environment(\.defaultMinListRowHeight, 36)
                            #if os(iOS)
                            .listRowSpacing(6)
                            .environment(\.editMode, .constant(.inactive))
                            .hoverEffectDisabled(true)
                            #endif
                            .frame(maxWidth: .infinity, minHeight: listHeight, maxHeight: listHeight)
                            .clipped()
                            .scrollContentBackground(.hidden)
                            .scrollDisabled(true)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: nonBookmarkedAtmosphereItems)
                        }
                        .frame(maxWidth: .infinity, minHeight: listHeight, maxHeight: listHeight)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(headerColor, lineWidth: 1))
            .animation(.easeInOut(duration: 0.25), value: showAtmospheres)
        }

        private var header: some View {
            HStack(spacing: 8) {
                Button(action: { withAnimation(.easeInOut) { showAtmospheres.toggle() } }) {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(headerColor)
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(showAtmospheres ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: showAtmospheres)
                }
                .buttonStyle(.plain)

                Button(action: { withAnimation(.easeInOut) { showAtmospheres.toggle() } }) {
                    HStack(spacing: 6) {
                        Text("Atmospheres")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(headerColor)
                        WaveformIndicator(style: waveformStyle, isActive: isPlaying)
                            .frame(width: 18, height: 14)
                    }
                }
                .buttonStyle(.plain)

                Spacer()
                EllipsisGlassIconButton(action: { showAtmospherePanel = true })
            }
            .padding(8)
        }

        private func listSectionHeader(systemName: String, title: String) -> some View {
            HStack {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private struct SFXSectionView: View {
        @Binding var showSoundEffects: Bool
        @Binding var showSoundboardPanel: Bool
        @Binding var pendingAlert: PendingAlert?
        let headerColor: Color
        let waveformStyle: AnyShapeStyle
        let isPlaying: Bool
        let sfxDisplayItems: [String]
        let nonBookmarkedSFXItems: [String]
        let recentNonBookmarkedSet: Set<String>
        let bookmarkList: [String]
        let listHeight: CGFloat
        let isSFXPlaying: (String) -> Bool
        let recencyText: (String) -> String?
        let onToggleSFX: (String) -> Void
        let onRemoveRecent: (String) -> Void
        let onAddBookmarkFromRecent: (String) -> Void
        let onEditItem: (String, String) -> Void
        let onRemoveBookmark: (String) -> Void
        let onRemoveBookmarkDirect: (String) -> Void
        let onMoveBookmarks: (IndexSet, Int) -> Void
        let itemIdForTitle: (String) -> String?

        var body: some View {
            VStack(spacing: 6) {
                header
                if showSoundEffects {
                    let nonBookmarkedCount = nonBookmarkedSFXItems.count
                    if sfxDisplayItems.isEmpty {
                        Text("No bookmarks yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        ZStack {
                            List {
                                if nonBookmarkedCount > 0 {
                                    listSectionHeader(systemName: "clock.fill", title: "Recents")
                                }

                                ForEach(nonBookmarkedSFXItems, id: \.self) { item in
                                    PlayRow(
                                        title: item,
                                        isPlaying: isSFXPlaying(item),
                                        infoItemId: itemIdForTitle(item),
                                        showRecent: recentNonBookmarkedSet.contains(item),
                                        recencyText: recencyText(item),
                                        backgroundTint: .gray,
                                        inactiveBackgroundTintOpacity: 0.16,
                                        onTap: {
                                            onToggleSFX(item)
                                        }
                                    )
                                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            onRemoveRecent(item)
                                        } label: {
                                            Label("Forget", systemImage: "clock.badge.xmark")
                                        }
                                        .tint(headerColor)
                                    }
                                    .contextMenu {
                                        Button {
                                            onAddBookmarkFromRecent(item)
                                        } label: {
                                            Label("Add to Bookmarks", systemImage: "bookmark")
                                        }
                                        Button {
                                            if let itemId = itemIdForTitle(item) {
                                                onEditItem(item, itemId)
                                            }
                                        } label: {
                                            Label("Edit Properties", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            onRemoveRecent(item)
                                        } label: {
                                            Label("Remove from Recents", systemImage: "clock.badge.xmark")
                                        }
                                    }
                                }

                                if !bookmarkList.isEmpty {
                                    listSectionHeader(
                                        systemName: "bookmark.fill",
                                        title: "Bookmarks (\(bookmarkList.count))"
                                    )
                                }

                                ForEach(bookmarkList, id: \.self) { item in
                                    PlayRow(
                                        title: item,
                                        isPlaying: isSFXPlaying(item),
                                        infoItemId: itemIdForTitle(item),
                                        showRecent: false,
                                        showBookmark: true,
                                        recencyText: recencyText(item),
                                        backgroundTint: .gray,
                                        inactiveBackgroundTintOpacity: 0.16,
                                        onTap: {
                                            onToggleSFX(item)
                                        }
                                    )
                                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            onRemoveBookmark(item)
                                        } label: {
                                            Label("Unmark", systemImage: "bookmark.slash")
                                        }
                                        .tint(headerColor)
                                    }
                                    .contextMenu {
                                        Button {
                                            onRemoveBookmarkDirect(item)
                                        } label: {
                                            Label("Remove from Bookmarks", systemImage: "bookmark.slash")
                                        }
                                        Button {
                                            if let itemId = itemIdForTitle(item) {
                                                onEditItem(item, itemId)
                                            }
                                        } label: {
                                            Label("Edit Properties", systemImage: "pencil")
                                        }
                                    }
                                }
                                .onMove { indices, newOffset in
                                    onMoveBookmarks(indices, newOffset)
                                }
                            }
                            .listStyle(.plain)
                            .environment(\.defaultMinListRowHeight, 36)
                            #if os(iOS)
                            .listRowSpacing(6)
                            .environment(\.editMode, .constant(.inactive))
                            .hoverEffectDisabled(true)
                            #endif
                            .frame(maxWidth: .infinity, minHeight: listHeight, maxHeight: listHeight)
                            .clipped()
                            .scrollContentBackground(.hidden)
                            .scrollDisabled(true)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: nonBookmarkedSFXItems)
                        }
                        .frame(maxWidth: .infinity, minHeight: listHeight, maxHeight: listHeight)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(headerColor, lineWidth: 1))
            .animation(.easeInOut(duration: 0.25), value: showSoundEffects)
        }

        private var header: some View {
            HStack(spacing: 8) {
                Button(action: { withAnimation(.easeInOut) { showSoundEffects.toggle() } }) {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(headerColor)
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(showSoundEffects ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: showSoundEffects)
                }
                .buttonStyle(.plain)

                Button(action: { withAnimation(.easeInOut) { showSoundEffects.toggle() } }) {
                    HStack(spacing: 6) {
                        Text("Sound Effects")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(headerColor)
                        WaveformIndicator(style: waveformStyle, isActive: isPlaying)
                            .frame(width: 18, height: 14)
                    }
                }
                .buttonStyle(.plain)

                Spacer()
                EllipsisGlassIconButton(action: { showSoundboardPanel = true })
            }
            .padding(8)
        }

        private func listSectionHeader(systemName: String, title: String) -> some View {
            HStack {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func activateQuickPlay() {
        quickPlayQuery = ""
        quickPlayResults = []
        quickPlaySelectedResultID = nil
        quickPlayIsPresented = true
        DispatchQueue.main.async {
            quickPlayFieldFocused = true
        }
    }

    private func toggleQuickPlay() {
        if quickPlayIsPresented {
            quickPlayFieldFocused = false
            quickPlayIsPresented = false
        } else {
            activateQuickPlay()
        }
    }

    private func clearQuickPlay() {
        quickPlaySearchTask?.cancel()
        quickPlayQuery = ""
        quickPlayResults = []
        quickPlaySelectedResultID = nil
    }

    private func performQuickPlaySearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        quickPlaySearchTask?.cancel()
        guard !trimmed.isEmpty else {
            quickPlayResults = []
            quickPlaySelectedResultID = nil
            return
        }
        quickPlaySearchTask = Task { [trimmed] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let items = (try? await backend.libraryRepository.searchItems(kind: nil, query: trimmed, filters: Filters())) ?? []
            guard !Task.isCancelled else { return }
            let mapped = items.compactMap { item -> QuickPlayResult? in
                guard let kind = LibraryKind(rawValue: item.kind) else { return nil }
                return QuickPlayResult(
                    id: item.id,
                    title: item.title,
                    subtitle: item.subtitle,
                    kind: kind,
                    containsMusic: item.containsMusic
                )
            }
            await MainActor.run {
                let current = quickPlayQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                guard current.caseInsensitiveCompare(trimmed) == .orderedSame else { return }
                quickPlayResults = mapped
                if mapped.isEmpty {
                    quickPlaySelectedResultID = nil
                } else if let selectedID = quickPlaySelectedResultID,
                          mapped.contains(where: { $0.id == selectedID }) {
                    quickPlaySelectedResultID = selectedID
                } else {
                    quickPlaySelectedResultID = mapped[0].id
                }
            }
        }
    }

    private func handleQuickPlaySelection(_ result: QuickPlayResult) {
        switch result.kind {
        case .atmosphere:
            let title = result.title
            let wasPlaying = playback.isLoopPlaying(title)
            if !wasPlaying {
                playback.toggleLoop(title)
                backend.audioManager.playAtmosphere(title: title)
            } else {
                playback.addRecentLoop(title)
            }
            dismissQuickPlay()
        case .sfx:
            let title = result.title
            let wasPlaying = playback.isSFXPlaying(title)
            if !wasPlaying {
                playback.toggleSFX(title)
            } else {
                playback.addRecentSFX(title)
            }
            backend.audioManager.playSFX(title: title)
            dismissQuickPlay()
        case .music:
            let title = result.title
            let source = playlistSourcesById[result.id] ?? .local
            let canPlay = source == .local || premium.isPremium
            guard canPlay else {
                showPremiumUpgrade = true
                return
            }
            guard !musicPlayback.isStartingPlayback else { return }
            if !musicPlayback.isPlayingPlaylist(result.id) {
                Task { await musicPlayback.togglePlaylist(itemId: result.id, title: title) }
            }
            if !bookmarks.playlistBookmarks.contains(title) {
                playback.addRecentPlaylist(title)
            } else {
                playback.markPlaylistPlayed(title)
            }
            dismissQuickPlay()
        }
    }

    private func dismissQuickPlay() {
        quickPlayFieldFocused = false
        quickPlayIsPresented = false
    }

    private func handleQuickPlaySubmit() {
        guard quickPlayIsPresented else { return }
        let trimmed = quickPlayQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let selectedID = quickPlaySelectedResultID,
           let selected = quickPlayResults.first(where: { $0.id == selectedID }) {
            handleQuickPlaySelection(selected)
            return
        }
        if let exact = quickPlayResults.first(where: { $0.title.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            handleQuickPlaySelection(exact)
            return
        }
        if let first = quickPlayResults.first {
            handleQuickPlaySelection(first)
        }
    }

    private func handleQuickPlayMove(step: Int) {
        guard quickPlayIsPresented else { return }
        guard !quickPlayResults.isEmpty else { return }

        let currentIndex: Int
        if let selectedID = quickPlaySelectedResultID,
           let index = quickPlayResults.firstIndex(where: { $0.id == selectedID }) {
            currentIndex = index
        } else {
            currentIndex = 0
        }

        let nextIndex = min(max(0, currentIndex + step), quickPlayResults.count - 1)
        quickPlaySelectedResultID = quickPlayResults[nextIndex].id
    }

    private func tipInstance(for step: CantusPlayTourStep) -> any Tip {
        switch step {
        case .controlIt:
            return Self.controlItTip
        case .fastAccessTags:
            return Self.fastAccessTagsTip
        case .bookmarksAndRecents:
            return Self.bookmarksAndRecentsTip
        case .navigateWithEase:
            return Self.navigateWithEaseTip
        case .mixItUp:
            return Self.mixItUpTip
        case .instantDucking:
            return Self.instantDuckingTip
        case .fastImport:
            return Self.fastImportTip
        case .quickPlayFast:
            return Self.quickPlayFastTip
        }
    }

    private func tipForTourStep(_ step: CantusPlayTourStep) -> (any Tip)? {
        guard isTourActive else { return nil }
        guard currentTourStep == step else { return nil }
        return tipInstance(for: step)
    }

    private func presentWelcomeTourIfReady() {
        guard didCompleteInitialLibraryBootstrap else { return }
        if !hasSeenCantusWelcomeTourSplash, musicPlayback.currentPlaylistItemId == nil {
            return
        }
        presentWelcomeTourIfNeeded()
    }

    private func ensureInitialNowPlayingPlaylistIfNeeded() async {
        guard !hasSeenCantusWelcomeTourSplash else { return }
        guard musicPlayback.currentPlaylistItemId == nil else { return }
        let match =
            playlistItemIds.first(where: {
                $0.key.caseInsensitiveCompare(defaultNowPlayingPlaylistTitle) == .orderedSame
            })
            ?? playlistItemIds.first(where: { $0.key.localizedCaseInsensitiveContains("initiative") })
            ?? playlistItemIds.sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }).first
        guard let match else { return }
        await musicPlayback.prepareInitialLocalPlaylist(itemId: match.value, title: match.key)
    }

    private func presentWelcomeTourIfNeeded() {
        guard !hasSeenCantusWelcomeTourSplash else { return }
        showWelcomeTourSplash = true
    }

    private func setTourStep(_ step: CantusPlayTourStep?) {
        tourStepStatusTask?.cancel()
        tourStepStatusTask = nil
        currentTourStep = step

        guard isTourActive, let step else { return }
        let tip = tipInstance(for: step)
        tourStepStatusTask = Task {
            for await status in tip.statusUpdates {
                guard !Task.isCancelled else { return }
                guard case .invalidated(let reason) = status else { continue }
                await MainActor.run {
                    handleTourTipInvalidation(for: step, reason: reason)
                }
                return
            }
        }
    }

    private func handleTourTipInvalidation(for step: CantusPlayTourStep, reason _: Tips.InvalidationReason) {
        guard isTourActive, currentTourStep == step else { return }
        advanceTour(from: step)
    }

    private func handleTourTipInternalTap() {
        guard isTourActive, let step = currentTourStep else { return }
        let now = Date()
        guard now.timeIntervalSince(lastTourManualInvalidateAt) > 0.16 else { return }
        lastTourManualInvalidateAt = now
        tipInstance(for: step).invalidate(reason: .tipClosed)
    }

    private func advanceTour(from step: CantusPlayTourStep) {
        guard isTourActive, currentTourStep == step else { return }
        guard let index = CantusPlayTourStep.allCases.firstIndex(of: step) else { return }
        let nextIndex = index + 1
        if CantusPlayTourStep.allCases.indices.contains(nextIndex) {
            setTourStep(CantusPlayTourStep.allCases[nextIndex])
        } else {
            finishTour()
        }
    }

    private func finishTour() {
        tourStepStatusTask?.cancel()
        tourStepStatusTask = nil
        setTourStep(nil)
        isTourActive = false
        lastTourManualInvalidateAt = .distantPast
        showTourCompletionSplash = true
    }

    private func startTour(resetProgress: Bool) {
        tourStepStatusTask?.cancel()
        tourStepStatusTask = nil
        if resetProgress {
            // Replay starts a fresh TipKit identity set so every tip can show again.
            CantusPlayTourState.bumpVersion()
            do {
                try Tips.resetDatastore()
            } catch {
                // Ignore reset failures and still try to run the tour.
            }
        }
        menuState.showVolumeSliders = true
        menuState.showPlaylists = true
        menuState.showAtmospheres = true
        menuState.showSoundEffects = true
        showWelcomeTourSplash = false
        showTourCompletionSplash = false
        isTourActive = true
        lastTourManualInvalidateAt = .distantPast
        setTourStep(.controlIt)
    }

}

private struct EditRequest: Identifiable, Equatable {
    let id = UUID()
    let itemId: String
    let title: String
    let kind: LibraryKind
}

private struct EditPlaylistRequest: Identifiable, Equatable {
    let id = UUID()
    let itemId: String
    let title: String
}

private struct CantusWelcomeTourSplashView: View {
    let onTakeTour: () -> Void
    let onSkip: () -> Void
    @EnvironmentObject private var theme: ThemeModel
    private let panelHorizontalPadding: CGFloat = 24

    private let coreFeatures: [PremiumFeatureItem] = [
        PremiumFeatureItem(
            icon: "music.note.house.fill",
            title: "Import & Play Your Sounds",
            detail: "Import and play your music, atmospheres, and sound effects",
            tint: .green
        ),
        PremiumFeatureItem(
            icon: "tag.fill",
            title: "Tag and Organize Fast",
            detail: "Tag sounds and quickly sort them by Theme, Mood, Location, and Creature",
            tint: .cyan
        ),
        PremiumFeatureItem(
            icon: "slider.horizontal.3",
            title: "Mix Perfect Moments",
            detail: "Create playlists and mix them with background atmospheres to craft those perfect moments!",
            tint: .orange
        ),
        PremiumFeatureItem(
            icon: "magnifyingglass.circle.fill",
            title: "QuickPlay in Seconds",
            detail: "Use QuickPlay to search for and play the perfect song or sound in seconds!",
            tint: .blue
        )
    ]

    private let premiumFeatures: [PremiumFeatureItem] = [
        PremiumFeatureItem(
            icon: "music.note",
            title: "Apple Music Playlist Access",
            detail: "Bring over your playlists directly from Apple Music",
            tint: .pink
        ),
        PremiumFeatureItem(
            icon: "paintpalette.fill",
            title: "Themes and App Icons",
            detail: "Customize Cantus with new themes and icons",
            tint: .indigo
        ),
        PremiumFeatureItem(
            icon: "sparkles",
            title: "Premium GM Playlists",
            detail: "Access our collection of Premium Playlists curated by Professional GMs",
            tint: .yellow
        )
    ]

    var body: some View {
        GeometryReader { proxy in
            let outerPadding: CGFloat = 16
            let availableWidth = max(proxy.size.width - (outerPadding * 2), 0)
            let availableHeight = max(proxy.size.height - (outerPadding * 2), 0)
            let panelWidth = min(780, availableWidth)
            let panelHeight = min(840, availableHeight)

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to Cantus!")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Craft and play immersive soundscapes at your table in seconds!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, panelHorizontalPadding)
                .padding(.top, 22)
                .padding(.bottom, 8)

                List {
                    Section("Features...") {
                        PremiumFeaturesCardView(items: coreFeatures)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: panelHorizontalPadding, bottom: 4, trailing: panelHorizontalPadding))
                    }

                    Section("And with Premium....") {
                        PremiumFeaturesCardView(items: premiumFeatures)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: panelHorizontalPadding, bottom: 4, trailing: panelHorizontalPadding))
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
                .scrollContentBackground(.hidden)

                HStack(spacing: 12) {
                    Button(action: onTakeTour) {
                        Text("Take the tour?")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(theme.color.opacity(0.16))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(theme.color, lineWidth: 1.4)
                    )
                    .foregroundStyle(.white)
                    .shadow(color: theme.color.opacity(0.24), radius: 8, y: 2)

                    Button(action: onSkip) {
                        Text("No, thanks")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(theme.headerColor.opacity(0.16))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(theme.headerColor, lineWidth: 1.4)
                    )
                    .foregroundStyle(.white)
                    .shadow(color: theme.headerColor.opacity(0.24), radius: 8, y: 2)
                }
                .padding(.horizontal, panelHorizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 22)
            }
            .frame(width: panelWidth, height: panelHeight, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 20, y: 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(outerPadding)
        }
    }
}

private struct CantusTourCompletionSplashView: View {
    let onDismiss: () -> Void
    @EnvironmentObject private var theme: ThemeModel

    var body: some View {
        GeometryReader { proxy in
            let outerPadding: CGFloat = 16
            let availableWidth = max(proxy.size.width - (outerPadding * 2), 0)
            let panelWidth = min(560, availableWidth)

            VStack {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 5) {
                    Text("And that's it!")
                        .font(.title2.weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("We add new features regularly, so check back here often to see what's changed. Have fun and get rolling!")
                        .font(.body)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: onDismiss) {
                        Text("Thanks!")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(theme.color.opacity(0.16))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(theme.color, lineWidth: 1.4)
                    )
                    .foregroundStyle(.white)
                    .shadow(color: theme.color.opacity(0.24), radius: 8, y: 2)
                    .padding(.top, 6)
                }
                .padding(22)
                .frame(width: panelWidth, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 20, y: 10)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(outerPadding)
        }
    }
}

private struct CantusPlayModalOverlay<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {}
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if canImport(UIKit)
private struct CantusTipTapCaptureView: UIViewRepresentable {
    let isActive: Bool
    let onTipTap: () -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var attachedWindow: UIWindow?
        var recognizer: UITapGestureRecognizer?
        var isActive = false
        var onTipTap: () -> Void

        init(onTipTap: @escaping () -> Void) {
            self.onTipTap = onTipTap
        }

        func update(onTipTap: @escaping () -> Void, isActive: Bool, anchorView: UIView) {
            self.onTipTap = onTipTap
            self.isActive = isActive
            DispatchQueue.main.async { [weak self, weak anchorView] in
                guard let self else { return }
                guard isActive, let window = anchorView?.window else {
                    self.detach()
                    return
                }
                self.attach(to: window)
            }
        }

        private func attach(to window: UIWindow) {
            if attachedWindow === window, recognizer != nil {
                return
            }
            detach()

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)

            attachedWindow = window
            recognizer = tap
        }

        func detach() {
            if let recognizer, let window = attachedWindow {
                window.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            attachedWindow = nil
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard isActive else { return }
            guard gesture.state == .ended else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onTipTap()
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard isActive else { return false }
            return isTouchInsideTipHierarchy(touch.view)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        private func isTouchInsideTipHierarchy(_ view: UIView?) -> Bool {
            var current = view
            while let node = current {
                let className = NSStringFromClass(type(of: node))
                if className.contains("TipKit") || className.contains("_TtC6TipKit") {
                    return true
                }
                current = node.superview
            }
            return false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTipTap: onTipTap)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update(onTipTap: onTipTap, isActive: isActive, anchorView: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }
}
#endif

private struct MixHeaderRow: View {
    let label: String
    @Binding var value: Double
    @Binding var isExpanded: Bool
    @State private var lastNonZero: Double = 0.5
    @State private var manualMuted = false
    @State private var programmaticMute = false
    @EnvironmentObject private var theme: ThemeModel

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggleMute) {
                Image(systemName: iconName)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 32, alignment: .leading)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            ZStack(alignment: .leading) {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                Text(label)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(width: 90, alignment: .trailing)

            GradientTrackSlider(value: $value, colors: [theme.indigoColor, theme.headerColor])
            Text(volumeText)
                .sansValue()
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.cantusTertiarySystemFill)
        )
        .onChange(of: value) { _, newValue in
            if newValue > 0.01 {
                lastNonZero = newValue
                manualMuted = false
                programmaticMute = false
            } else {
                manualMuted = !programmaticMute
                programmaticMute = false
            }
        }
    }

    private var iconName: String {
        if value <= 0.01 {
            return "speaker.slash.fill"
        } else if value < 0.34 {
            return "speaker.wave.1.fill"
        } else if value < 0.67 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    private func toggleMute() {
        if value > 0.01 {
            lastNonZero = value
            programmaticMute = true
            value = 0.0
        } else {
            if manualMuted {
                value = 0.5
                lastNonZero = 0.5
                manualMuted = false
            } else {
                let restored = lastNonZero > 0.01 ? lastNonZero : 0.5
                value = restored
            }
        }
    }

    private var volumeText: String {
        let percent = Int(round(value * 100))
        return "\(percent)"
    }
}

private struct GradientTrackSlider: View {
    @Binding var value: Double
    let colors: [Color]

    var body: some View {
        Slider(value: $value, in: 0...1)
            .tint(.clear)
            .background(
                SliderTrackOverlay(value: value, colors: colors)
                    .allowsHitTesting(false)
            )
    }
}

private struct SliderTrackOverlay: View {
    let value: Double
    let colors: [Color]
    private let trackHeight: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let clamped = min(max(value, 0), 1)
            let filledWidth = width * clamped

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: trackHeight)
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                    .frame(width: width, height: trackHeight)
                    .mask(
                        Capsule()
                            .frame(width: filledWidth, height: trackHeight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    )
            }
            .frame(height: trackHeight)
        }
        .frame(height: trackHeight)
    }
}

@available(iOS 18.0, *)
private struct EllipsisGlassIconButton: View {
    let action: () -> Void
    @State private var isHovered = false
    @EnvironmentObject private var theme: ThemeModel
    private let visualSize: CGFloat = 36
    private let tapTargetSize: CGFloat = 36

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isHovered ? 0.10 : 0.0))
                Image(systemName: "ellipsis")
                    .font(.title2.weight(.semibold))
                    .frame(width: visualSize, height: visualSize)
                    .scaleEffect(isHovered ? 1.15 : 1.0)
                    .foregroundStyle(theme.headerColor)
            }
            .frame(width: tapTargetSize, height: tapTargetSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovered = hovering
            }
        }
    }
}


@available(iOS 18.0, *)
struct NowPlayingDock: View {
    let openPlaylist: () -> Void
    let openPlaylistForTag: (PlaylistPanelView.InitialFilter) -> Void
    let tagsTip: (any Tip)?
    let controlsTip: (any Tip)?
    @ObservedObject private var playbackProgress: PlaybackProgressModel
    @EnvironmentObject private var theme: ThemeModel
    @EnvironmentObject private var musicPlayback: MusicPlaybackStore
    @EnvironmentObject private var premium: PremiumStore
    @EnvironmentObject private var backend: AppBackend
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var didBeginScrub = false
    @State private var isEllipsisHovered = false
    @State private var nowPlayingSource: PlaylistSource?
    @State private var nowPlayingTags: [NowPlayingTag] = []
    @State private var isLoadingNowPlayingTags = false

    init(
        openPlaylist: @escaping () -> Void,
        openPlaylistForTag: @escaping (PlaylistPanelView.InitialFilter) -> Void,
        playbackProgress: PlaybackProgressModel,
        tagsTip: (any Tip)? = nil,
        controlsTip: (any Tip)? = nil
    ) {
        self.openPlaylist = openPlaylist
        self.openPlaylistForTag = openPlaylistForTag
        self.tagsTip = tagsTip
        self.controlsTip = controlsTip
        _playbackProgress = ObservedObject(wrappedValue: playbackProgress)
    }

    var body: some View {
        VStack(spacing: 12) {
            nowPlayingHeader
            nowPlayingDetails
            playbackControls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .padding(16)
        .cantusGlassEffectRegular(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task {
            await musicPlayback.refresh()
        }
        .onChange(of: premium.isPremium) { _, newValue in
            if !newValue {
                Task { await musicPlayback.stopForPremiumLoss() }
            }
        }
        .onAppear {
            if !isScrubbing {
                scrubValue = playbackProgress.snapshot.time
            }
        }
        .onChange(of: playbackProgress.snapshot) { _, newSnapshot in
            if !isScrubbing {
                scrubValue = newSnapshot.time
            }
        }
        .onChange(of: musicPlayback.currentPlaylistItemId) { _, _ in
            Task { await loadNowPlayingTags() }
        }
        .task {
            await loadNowPlayingTags()
        }
    }

    private var nowPlayingHeader: some View {
        HStack {
            NowPlayingHeaderRow(
                playlistTitle: musicPlayback.playlistTitle,
                source: nowPlayingSource,
                tagSections: nowPlayingTagSections,
                isLoading: isLoadingNowPlayingTags,
                onPlaylistTap: openPlaylist,
                onTagTap: { tag in
                    openPlaylistForTag(
                        PlaylistPanelView.InitialFilter(
                            category: playlistCategory(from: tag.category),
                            tagName: tag.name
                        )
                    )
                }
            )
            .popoverTip(tagsTip, arrowEdge: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .layoutPriority(1)
            Spacer()
            Button(action: openPlaylist) {
                Image(systemName: "ellipsis")
                    .font(.title2.weight(.semibold))
                    .padding(8)
                    .background(.thinMaterial, in: Circle())
                    .scaleEffect(isEllipsisHovered ? 1.12 : 1.0)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.color)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.18)) {
                    isEllipsisHovered = hovering
                }
            }
        }
    }

    private var nowPlayingDetails: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.cantusTertiarySystemFill)
                if let artwork = musicPlayback.artworkImage {
                    artwork
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "music.quarternote.3")
                        .font(.title2)
                }
            }
            .frame(width: 70, height: 70)
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                MarqueeText(text: musicPlayback.title, font: .headline, color: .primary)
                MarqueeText(
                    text: musicPlayback.artist.isEmpty ? " " : musicPlayback.artist,
                    font: .subheadline,
                    color: .secondary
                )

                TimelineView(.periodic(from: .now, by: progressTimelineInterval)) { timeline in
                    let seekableDuration = max(0, effectiveDuration)
                    let durationForMath = max(1, seekableDuration)
                    let currentTime = displayedPlaybackTime(at: timeline.date)

                    VStack(spacing: 6) {
                        GeometryReader { proxy in
                            let width = max(1, proxy.size.width)
                            let progress = min(max(currentTime / durationForMath, 0), 1)

                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.cantusTertiarySystemFill)
                                Capsule()
                                    .fill(theme.mixSliderColor)
                                    .frame(width: width * progress)
                            }
                            .frame(height: 6)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let x = min(max(0, value.location.x), width)
                                        let rawValue = (x / width) * durationForMath
                                        let newValue = min(max(0, rawValue), seekableDuration)
                                        if !didBeginScrub {
                                            didBeginScrub = true
                                            isScrubbing = true
                                            musicPlayback.beginScrub()
                                        }
                                        scrubValue = newValue
                                        musicPlayback.updateScrub(to: newValue)
                                    }
                                    .onEnded { value in
                                        let x = min(max(0, value.location.x), width)
                                        let rawValue = (x / width) * durationForMath
                                        let newValue = min(max(0, rawValue), seekableDuration)
                                        scrubValue = newValue
                                        didBeginScrub = false
                                        isScrubbing = false
                                        Task { await musicPlayback.endScrub(to: newValue) }
                                    }
                            )
                        }
                        .frame(height: 6)

                        HStack {
                            Text(formatTime(currentTime))
                                .sansValue()
                            Spacer()
                            Text(remainingTimeLabel(currentTime: currentTime, duration: seekableDuration))
                                .sansValue()
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private var playbackControls: some View {
        ZStack {
            HStack(spacing: 28) {
                Button(action: { Task { await musicPlayback.previous() } }) {
                    Image(systemName: "backward.end.fill")
                        .font(.title3)
                }
                Button(action: { Task { await musicPlayback.togglePlayPause() } }) {
                    Image(systemName: musicPlayback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .popoverTip(controlsTip, arrowEdge: .top)
                Button(action: { Task { await musicPlayback.next() } }) {
                    Image(systemName: "forward.end.fill")
                        .font(.title3)
                }
                Button(action: { musicPlayback.cyclePlaylistPlaybackMode() }) {
                    Image(systemName: musicPlayback.playlistPlaybackMode.iconName)
                        .font(.title3)
                }
                .foregroundStyle(theme.color)
                .accessibilityLabel(musicPlayback.playlistPlaybackMode.accessibilityLabel)
            }

            HStack {
                Spacer()
                AirPlayRoutePicker()
            }
        }
    }

    private var effectiveDuration: TimeInterval {
        max(musicPlayback.duration, playbackProgress.snapshot.duration)
    }

    private var progressTimelineInterval: TimeInterval {
        if isScrubbing || playbackProgress.snapshot.isPlaying {
            return 1.0 / 30.0
        }
        return 0.5
    }

    private func displayedPlaybackTime(at date: Date) -> TimeInterval {
        if isScrubbing {
            return min(max(0, scrubValue), max(0, effectiveDuration))
        }

        let snapshot = playbackProgress.snapshot
        let upperBound = max(0, max(effectiveDuration, snapshot.duration))
        let base = min(max(0, snapshot.time), upperBound > 0 ? upperBound : max(0, snapshot.time))
        guard snapshot.isPlaying else { return base }

        let elapsed = max(0, date.timeIntervalSince(snapshot.updatedAt))
        let projected = base + elapsed
        guard upperBound > 0 else { return projected }
        return min(upperBound, projected)
    }

    private func remainingTimeLabel(currentTime: TimeInterval, duration: TimeInterval) -> String {
        guard duration > 0 else { return "--:--" }
        let remaining = max(0, duration - currentTime)
        return "-\(formatTime(remaining))"
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "--:--" }
        let totalSeconds = max(0, Int(time.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func loadNowPlayingTags() async {
        guard let itemId = musicPlayback.currentPlaylistItemId,
              let uuid = UUID(uuidString: itemId) else {
            await MainActor.run {
                nowPlayingTags = []
                nowPlayingSource = nil
            }
            return
        }
        await MainActor.run {
            isLoadingNowPlayingTags = true
        }
        let source = try? await backend.musicRepository.playlistSource(for: uuid)
        let detail = try? await backend.libraryRepository.fetchItemDetail(itemId: uuid)
        let tags = (detail?.locations.map { NowPlayingTag(name: $0.name, category: .location) } ?? [])
            + (detail?.moods.map { NowPlayingTag(name: $0.name, category: .mood) } ?? [])
            + (detail?.musicThemes.map { NowPlayingTag(name: $0.name, category: .theme) } ?? [])
        await MainActor.run {
            nowPlayingSource = source
            nowPlayingTags = tags
            isLoadingNowPlayingTags = false
        }
    }


    private var nowPlayingTagSections: [NowPlayingTagSection] {
        var sections: [NowPlayingTagSection] = []
        for category in NowPlayingTagCategory.displayOrder {
            let tags = nowPlayingTags.filter { $0.category == category }
            if !tags.isEmpty {
                sections.append(NowPlayingTagSection(category: category, tags: tags))
            }
        }
        return sections
    }

    private func playlistCategory(from category: NowPlayingTagCategory) -> PlaylistPanelView.InitialFilter.Category {
        switch category {
        case .location: return .location
        case .mood: return .mood
        case .theme: return .theme
        }
    }
}

private enum NowPlayingTagCategory: Hashable {
    case location
    case mood
    case theme

    static var displayOrder: [Self] { [.location, .mood, .theme] }

    var label: String {
        switch self {
        case .location: return "Location"
        case .mood: return "Mood"
        case .theme: return "Theme"
        }
    }
}

private struct NowPlayingTag: Hashable {
    let name: String
    let category: NowPlayingTagCategory
}

private struct NowPlayingTagSection: Hashable {
    let category: NowPlayingTagCategory
    let tags: [NowPlayingTag]
}

private struct TagPill: View {
    let text: String
    var systemImage: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) {
                pillContents
            }
            .buttonStyle(.plain)
        } else {
            pillContents
        }
    }

    private var pillContents: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.cantusTertiarySystemFill))
        .foregroundStyle(.secondary)
    }
}

private struct CategoryTagPill: View {
    let categoryText: String
    let tags: [NowPlayingTag]
    let onTagTap: (NowPlayingTag) -> Void
    @EnvironmentObject private var theme: ThemeModel

    var body: some View {
        HStack(spacing: 6) {
            Text(categoryText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                ForEach(Array(tags.enumerated()), id: \.element) { index, tag in
                    Button(action: { onTagTap(tag) }) {
                        HStack(spacing: 0) {
                            if index > 0 {
                                Text(", ")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(tag.name)
                                .font(.caption2)
                                .foregroundStyle(theme.confirmIconColor)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.cantusTertiarySystemFill))
    }
}

#if canImport(UIKit)
private struct QuickPlayInlineTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var isActive: Bool
    let onUp: () -> Void
    let onDown: () -> Void
    let onReturn: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, isActive: $isActive, onReturn: onReturn)
    }

    func makeUIView(context: Context) -> KeyAwareTextField {
        let textField = KeyAwareTextField(frame: .zero)
        textField.placeholder = "QuickPlay"
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.returnKeyType = .search
        textField.clearButtonMode = .whileEditing
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        textField.onUp = onUp
        textField.onDown = onDown
        textField.onReturn = onReturn
        textField.onEscape = onEscape
        return textField
    }

    func updateUIView(_ uiView: KeyAwareTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = $isFocused
        context.coordinator.isActive = $isActive
        context.coordinator.onReturn = onReturn
        uiView.isActive = isActive
        uiView.onUp = onUp
        uiView.onDown = onDown
        uiView.onReturn = onReturn
        uiView.onEscape = onEscape
        if uiView.text != text {
            uiView.text = text
        }
        if isFocused, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                _ = uiView.becomeFirstResponder()
            }
        } else if !isFocused, uiView.isFirstResponder {
            DispatchQueue.main.async {
                _ = uiView.resignFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>
        var isActive: Binding<Bool>
        var onReturn: () -> Void

        init(text: Binding<String>, isFocused: Binding<Bool>, isActive: Binding<Bool>, onReturn: @escaping () -> Void) {
            self.text = text
            self.isFocused = isFocused
            self.isActive = isActive
            self.onReturn = onReturn
        }

        @objc func textDidChange(_ sender: UITextField) {
            text.wrappedValue = sender.text ?? ""
        }

        func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
            isActive.wrappedValue
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isFocused.wrappedValue = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isFocused.wrappedValue = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            guard isActive.wrappedValue else { return false }
            onReturn()
            return false
        }
    }

    final class KeyAwareTextField: UITextField {
        var isActive: Bool = false
        var onUp: (() -> Void)?
        var onDown: (() -> Void)?
        var onReturn: (() -> Void)?
        var onEscape: (() -> Void)?

        override var keyCommands: [UIKeyCommand]? {
            guard isActive else { return [] }
            return [
                UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleUp)),
                UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleDown)),
                UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(handleReturn)),
                UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(handleEscape))
            ]
        }

        @objc private func handleUp() { onUp?() }
        @objc private func handleDown() { onDown?() }
        @objc private func handleReturn() { onReturn?() }
        @objc private func handleEscape() { onEscape?() }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard isActive else {
                super.pressesBegan(presses, with: event)
                return
            }
            for press in presses {
                guard let key = press.key else { continue }
                switch key.keyCode {
                case .keyboardUpArrow:
                    onUp?()
                    return
                case .keyboardDownArrow:
                    onDown?()
                    return
                case .keyboardEscape:
                    onEscape?()
                    return
                default:
                    continue
                }
            }
            super.pressesBegan(presses, with: event)
        }
    }
}
#endif

#if os(iOS) && canImport(UIKit)
private struct AirPlayRoutePicker: View {
    var body: some View {
        AirPlayRoutePickerView()
            .frame(width: 36, height: 36)
    }
}

private struct AirPlayRoutePickerView: UIViewRepresentable {
    typealias UIViewType = AVRoutePickerView

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.tintColor = UIColor.white
        view.activeTintColor = UIColor.white
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif

@available(iOS 18.0, *)
struct PlayRow: View {
    enum InfoPlacement {
        case afterTitle
        case afterBadge
    }

    let title: String
    let isPlaying: Bool
    var infoItemId: String? = nil
    var infoPlacement: InfoPlacement = .afterTitle
    var containsMusic: Bool = false
    var badgeText: String? = nil
    var showRecent: Bool = false
    var showBookmark: Bool = false
    var recencyText: String? = nil
    var isDimmed: Bool = false
    var titleLineLimit: Int? = 2
    var backgroundTint: Color? = nil
    var backgroundTintOpacity: Double = 0.0
    var inactiveBackgroundTintOpacity: Double? = nil
    var onTap: (() -> Void)? = nil
    @EnvironmentObject private var theme: ThemeModel
    @State private var showInfo = false

    var body: some View {
        let resolvedBackgroundTintOpacity = isPlaying ? backgroundTintOpacity : (inactiveBackgroundTintOpacity ?? backgroundTintOpacity)
        let tint = backgroundTint?.opacity(resolvedBackgroundTintOpacity) ?? .clear
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.color.opacity(isPlaying ? 0.45 : 0.0))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint)
                )
            HStack {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline)
                        .lineLimit(titleLineLimit)
                        .truncationMode(.tail)
                        .foregroundStyle(isDimmed ? .secondary : .primary)
                    if infoPlacement == .afterTitle {
                        infoButton
                    }
                    if containsMusic {
                        Image(systemName: "music.note")
                            .font(.caption)
                            .foregroundStyle(isDimmed ? .tertiary : .secondary)
                    }
                    if let badgeText {
                        HStack(spacing: 4) {
                            Text(badgeText)
                                .font(.caption2)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.cantusTertiarySystemFill))
                        .foregroundStyle(isDimmed ? .tertiary : .secondary)
                    }
                    if infoPlacement == .afterBadge {
                        infoButton
                    }
                }
                Spacer()
                if let recencyText {
                    Text(recencyText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if showRecent {
                    Image(systemName: "clock")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isDimmed ? .tertiary : .secondary)
                }
                if showBookmark {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isDimmed ? .tertiary : .secondary)
                }
            }
            .padding(.leading, 11.5)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .opacity(isDimmed ? 0.55 : 1.0)
        #if os(iOS)
        .hoverEffectDisabled(true)
        #endif
    }

    @ViewBuilder
    private var infoButton: some View {
        if let infoItemId {
            Button(action: { showInfo = true }) {
                Image(systemName: "info.circle")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isDimmed ? .tertiary : .secondary)
            .popover(isPresented: $showInfo) {
                TagInfoPopover(itemId: infoItemId, title: title)
                    .presentationDetents([.medium])
            }
        }
    }
}

private struct WaveformIndicator: View {
    let style: AnyShapeStyle
    let isActive: Bool
    @State private var phase: CGFloat = 0.8
    @State private var isVisible = false

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            bar(height: 4, duration: 0.42, delay: 0.05)
            bar(height: 10, duration: 0.55, delay: 0.0)
            bar(height: 6, duration: 0.48, delay: 0.12)
            bar(height: 12, duration: 0.6, delay: 0.18)
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.6), value: isVisible)
        .onAppear {
            if isActive {
                startPhaseAnimation()
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                startPhaseAnimation()
            } else {
                withAnimation(.easeInOut(duration: 0.6)) {
                    isVisible = false
                }
            }
        }
    }

    private func bar(height: CGFloat, duration: Double, delay: Double) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(style)
            .frame(width: 3, height: height)
            .scaleEffect(y: isVisible ? phase : 0.35, anchor: .center)
            .animation(.easeInOut(duration: duration).repeatForever(autoreverses: true).delay(delay), value: phase)
    }

    private func startPhaseAnimation() {
        isVisible = true
        phase = 0.6
        withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
            phase = 1.0
        }
    }
}



struct SliderRow: View {
    let label: String
    @Binding var value: Double
    var modeToggle: Binding<Bool>? = nil
    var modeToggleEnabled: Bool = true
    var duckingTip: (any Tip)? = nil
    private let baseLeadingWidth: CGFloat = 24
    private let toggleLeadingWidth: CGFloat = 62
    private let defaultLabelWidth: CGFloat = 90
    private let toggleLabelWidth: CGFloat = 52
    private let rowHeight: CGFloat = 34
    @State private var lastNonZero: Double = 0.5
    @State private var manualMuted = false
    @State private var programmaticMute = false
    @EnvironmentObject private var theme: ThemeModel

    var body: some View {
        HStack(spacing: 12) {
            leadingControls
            Text(label)
                .font(.subheadline)
                .frame(width: labelColumnWidth, alignment: .trailing)
            Slider(value: $value, in: 0...1)
                .tint(theme.otherSliderColor)
            Text(volumeText)
                .sansValue()
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
        .frame(minHeight: rowHeight)
        .padding(.horizontal, 6)
        .onChange(of: value) { _, newValue in
            if newValue > 0.01 {
                lastNonZero = newValue
                manualMuted = false
                programmaticMute = false
            } else {
                manualMuted = !programmaticMute
                programmaticMute = false
            }
        }
    }

    private var iconName: String {
        if value <= 0.01 {
            return "speaker.slash.fill"
        } else if value < 0.34 {
            return "speaker.wave.1.fill"
        } else if value < 0.67 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    private func toggleMute() {
        if value > 0.01 {
            lastNonZero = value
            programmaticMute = true
            value = 0.0
        } else {
            if manualMuted {
                value = 0.5
                lastNonZero = 0.5
                manualMuted = false
            } else {
                let restored = lastNonZero > 0.01 ? lastNonZero : 0.5
                value = restored
            }
        }
    }

    private var volumeText: String {
        let percent = Int(round(value * 100))
        return "\(percent)"
    }

    @ViewBuilder
    private var leadingControls: some View {
        if let modeToggle {
            HStack(spacing: 12) {
                speakerButton
                modeToggleButton(modeToggle)
            }
            .frame(width: toggleLeadingWidth, alignment: .leading)
        } else {
            speakerButton
                .frame(width: baseLeadingWidth, alignment: .leading)
        }
    }

    private var speakerButton: some View {
        Button(action: toggleMute) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func modeToggleButton(_ modeToggle: Binding<Bool>) -> some View {
        let isOn = modeToggle.wrappedValue

        return Button(action: { modeToggle.wrappedValue.toggle() }) {
            Image(systemName: modeToggleSymbolName())
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(modeToggleIconColor(isOn: isOn))
                .frame(width: 21, height: 21)
        }
        .buttonStyle(.plain)
        .disabled(!modeToggleEnabled)
        .accessibilityLabel("Auto Ducking")
        .popoverTip(duckingTip, arrowEdge: .top)
    }

    private var labelColumnWidth: CGFloat {
        modeToggle == nil ? defaultLabelWidth : toggleLabelWidth
    }

    private func modeToggleSymbolName() -> String {
        modeToggleEnabled ? "waveform" : "waveform.slash"
    }

    private func modeToggleIconColor(isOn: Bool) -> Color {
        if !modeToggleEnabled {
            return Color.gray.opacity(0.78)
        }
        return isOn ? theme.color : .white
    }
}

private struct DisabledMusicSliderRow: View {
    let label: String
    let note: String
    let value: Double
    private let rowHeight: CGFloat = 34
    private let leadingWidth: CGFloat = 62
    private let labelWidth: CGFloat = 52

    @State private var showNotePopover = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: speakerIconName)
                    .foregroundStyle(Color.gray.opacity(0.85))
                    .frame(width: 24, alignment: .leading)
                Button(action: { showNotePopover = true }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17.5, weight: .regular))
                        .foregroundStyle(Color.gray.opacity(0.9))
                        .frame(width: 21, height: 21)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showNotePopover, arrowEdge: .top) {
                    Text(note)
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                        .padding(12)
                        .frame(maxWidth: 280, alignment: .leading)
                        .presentationCompactAdaptation(.popover)
                }
            }
            .frame(width: leadingWidth, alignment: .leading)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.gray.opacity(0.9))
                .frame(width: labelWidth, alignment: .trailing)
            DisabledSliderTrack()
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(volumeText)
                .sansValue()
                .foregroundStyle(Color.gray.opacity(0.85))
                .frame(width: 32, alignment: .trailing)
        }
        .frame(height: rowHeight)
        .padding(.horizontal, 6)
    }

    private var speakerIconName: String {
        if value <= 0.01 {
            return "speaker.slash.fill"
        } else if value < 0.34 {
            return "speaker.wave.1.fill"
        } else if value < 0.67 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    private var volumeText: String {
        let percent = Int(round(min(max(value, 0), 1) * 100))
        return "\(percent)"
    }
}

private struct DisabledSliderTrack: View {
    var body: some View {
        Capsule()
            .fill(Color.gray.opacity(0.24))
            .frame(height: 4)
            .frame(maxHeight: .infinity, alignment: .center)
        .frame(height: 16)
    }
}

private enum QuickBoardSection: String, CaseIterable, Identifiable {
    case playlists
    case atmosphere
    case soundEffects

    var id: String { rawValue }
}

private struct QuickBoardsView<Playlist: View, Atmosphere: View, SoundEffects: View>: View {
    let availableWidth: CGFloat
    @Binding var order: [QuickBoardSection]
    @Binding var dragging: QuickBoardSection?
    let playlist: Playlist
    let atmosphere: Atmosphere
    let soundEffects: SoundEffects

    var body: some View {
        let columnCount = columnCount(for: availableWidth)
        let columns = distribute(order, into: columnCount)
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<columnCount, id: \.self) { columnIndex in
                VStack(spacing: 12) {
                    ForEach(columns[columnIndex]) { section in
                        quickBoardCard(for: section)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func columnCount(for width: CGFloat) -> Int {
        let spacing: CGFloat = 12
        let minCardWidth: CGFloat = 340
        let available = max(0, width)
        let rawCount = Int((available + spacing) / (minCardWidth + spacing))
        return min(3, max(1, rawCount))
    }

    private func distribute(_ sections: [QuickBoardSection], into columnCount: Int) -> [[QuickBoardSection]] {
        guard columnCount > 1 else { return [sections] }
        var columns = Array(repeating: [QuickBoardSection](), count: columnCount)
        for (index, section) in sections.enumerated() {
            columns[index % columnCount].append(section)
        }
        return columns
    }

    private func quickBoardCard(for section: QuickBoardSection) -> some View {
        quickBoardView(for: section)
#if os(iOS)
            .onDrag {
                dragging = section
                return NSItemProvider(object: section.rawValue as NSString)
            } preview: {
                Color.clear.frame(width: 1, height: 1)
            }
#else
            .onDrag {
                dragging = section
                return NSItemProvider(object: section.rawValue as NSString)
            }
#endif
            .onDrop(of: [UTType.text], delegate: QuickBoardDropDelegate(
                item: section,
                order: $order,
                dragging: $dragging
            ))
    }

    @ViewBuilder
    private func quickBoardView(for section: QuickBoardSection) -> some View {
        switch section {
        case .playlists:
            playlist
        case .atmosphere:
            atmosphere
        case .soundEffects:
            soundEffects
        }
    }
}

private struct PlaySheets<Content: View>: View {
    @Environment(\.openWindow) private var openWindow
    @Binding var showPremiumUpgrade: Bool
    @Binding var editRequest: EditRequest?
    @Binding var editPlaylistRequest: EditPlaylistRequest?
    let onLibraryChange: @Sendable () async -> Void
    let content: Content

    @EnvironmentObject private var theme: ThemeModel
    @EnvironmentObject private var premium: PremiumStore

    init(
        showPremiumUpgrade: Binding<Bool>,
        editRequest: Binding<EditRequest?>,
        editPlaylistRequest: Binding<EditPlaylistRequest?>,
        onLibraryChange: @escaping @Sendable () async -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self._showPremiumUpgrade = showPremiumUpgrade
        self._editRequest = editRequest
        self._editPlaylistRequest = editPlaylistRequest
        self.onLibraryChange = onLibraryChange
        self.content = content()
    }

    var body: some View {
        content
            .sheet(isPresented: $showPremiumUpgrade) {
                PremiumUpgradeView()
                    .environmentObject(theme)
                    .environmentObject(premium)
            }
            .onReceive(NotificationCenter.default.publisher(for: .cantusLibraryDidChange)) { _ in
                Task { await onLibraryChange() }
            }
            .onChange(of: editRequest) { _, newValue in
                guard let request = newValue else { return }
                openWindow(
                    value: EditAssetWindowPayload(
                        itemId: request.itemId,
                        title: request.title,
                        kind: request.kind
                    )
                )
                editRequest = nil
            }
            .onChange(of: editPlaylistRequest) { _, newValue in
                guard let request = newValue else { return }
                openWindow(
                    value: EditPlaylistWindowPayload(
                        itemId: request.itemId,
                        title: request.title
                    )
                )
                editPlaylistRequest = nil
            }
    }
}

private struct QuickBoardDropDelegate: DropDelegate {
    let item: QuickBoardSection
    @Binding var order: [QuickBoardSection]
    @Binding var dragging: QuickBoardSection?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != item,
              let fromIndex = order.firstIndex(of: dragging),
              let toIndex = order.firstIndex(of: item) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            order.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

private struct SansValue: ViewModifier {
    @EnvironmentObject private var theme: ThemeModel

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .regular))
            .environment(\.font, .system(size: 12, weight: .regular))
    }
}

private struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var height: CGFloat = 18

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animationKey = UUID()
    @State private var isOverflowing = false

    var body: some View {
        GeometryReader { proxy in
            marqueeContent(width: max(1, proxy.size.width))
        }
        .frame(height: height)
        .onChange(of: text) { _, _ in
            updateAnimation()
        }
    }

    @ViewBuilder
    private func marqueeContent(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            marqueeText
                .offset(x: offset)
                .id(animationKey)
                .background(measurementText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .clipped()
        .mask(overflowMask)
        .onAppear { updateContainerWidth(width) }
        .onChange(of: width) { _, newValue in
            updateContainerWidth(newValue)
        }
    }

    private var marqueeText: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var measurementText: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .background(GeometryReader { textProxy in
                Color.clear
                    .onAppear { updateTextWidth(textProxy.size.width) }
                    .onChange(of: textProxy.size.width) { _, newValue in
                        updateTextWidth(newValue)
                    }
            })
    }

    private func updateAnimation() {
        guard containerWidth > 0, textWidth > 0 else { return }
        let overflow = max(0, textWidth - containerWidth)
        let wasOverflowing = isOverflowing
        isOverflowing = overflow > 1
        offset = 0
        if isOverflowing != wasOverflowing || isOverflowing {
            animationKey = UUID()
        }
        guard isOverflowing else { return }
        let duration = max(4.0, Double(overflow / 20.0))
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: true)) {
            offset = -overflow
        }
    }

    private func updateTextWidth(_ newValue: CGFloat) {
        if abs(textWidth - newValue) > 0.5 {
            textWidth = newValue
            updateAnimation()
        }
    }

    private func updateContainerWidth(_ newValue: CGFloat) {
        if abs(containerWidth - newValue) > 0.5 {
            containerWidth = newValue
            updateAnimation()
        }
    }

    private var overflowMask: some View {
        Rectangle().fill(Color.black)
    }
}

private struct FadeOnOverflowScrollView<Content: View>: View {
    let content: Content
    var fadeWidth: CGFloat = 16

    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var isOverflowing = false

    init(fadeWidth: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.fadeWidth = fadeWidth
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content
                .background(GeometryReader { proxy in
                    Color.clear
                        .preference(key: WidthPreferenceKey.self, value: proxy.size.width)
                })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .background(GeometryReader { proxy in
            Color.clear
                .preference(key: ContainerWidthPreferenceKey.self, value: proxy.size.width)
        })
        .mask(overflowMask)
        .onPreferenceChange(WidthPreferenceKey.self) { newValue in
            contentWidth = newValue
            updateOverflow()
        }
        .onPreferenceChange(ContainerWidthPreferenceKey.self) { newValue in
            containerWidth = newValue
            updateOverflow()
        }
    }

    private func updateOverflow() {
        guard containerWidth > 0, contentWidth > 0 else { return }
        isOverflowing = contentWidth > containerWidth + 1
    }

    @ViewBuilder
    private var overflowMask: some View {
        if isOverflowing {
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: fadeWidth)
                Color.black
                LinearGradient(
                    colors: [Color.black, Color.black.opacity(0.0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: fadeWidth)
            }
        } else {
            Rectangle().fill(Color.black)
        }
    }
}

private struct NowPlayingHeaderRow: View {
    let playlistTitle: String
    let source: PlaylistSource?
    let tagSections: [NowPlayingTagSection]
    let isLoading: Bool
    let onPlaylistTap: () -> Void
    let onTagTap: (NowPlayingTag) -> Void
    @EnvironmentObject private var theme: ThemeModel

    var body: some View {
        FadeOnOverflowScrollView {
            HStack(spacing: 6) {
                Button(action: onPlaylistTap) {
                    Text(playlistTitle)
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.confirmIconColor)
                if let source {
                    TagPill(text: source.label)
                }
                ForEach(tagSections, id: \.category) { section in
                    CategoryTagPill(
                        categoryText: section.category.label,
                        tags: section.tags,
                        onTagTap: onTagTap
                    )
                }
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(.trailing, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

private struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct BottomDockHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ContainerWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension View {
    func sansValue() -> some View {
        modifier(SansValue())
    }
}

struct EdgeFadeOverlay: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let base = colorScheme == .dark ? Color.black : Color.white
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    base.opacity(0.92),
                    base.opacity(0.6),
                    base.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)

            Spacer()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct DockBackdropEffect: View {
    @EnvironmentObject private var theme: ThemeModel

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .white.opacity(0.42), location: 0.28),
                            .init(color: .white.opacity(0.78), location: 0.62),
                            .init(color: .white, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            LinearGradient(
                stops: [
                    .init(color: theme.indigoColor.opacity(0.0), location: 0.0),
                    .init(color: theme.indigoColor.opacity(0.16), location: 0.30),
                    .init(color: theme.backgroundColor.opacity(0.52), location: 0.68),
                    .init(color: theme.backgroundColor.opacity(0.90), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }
}

private struct BottomFadeOverlay: View {
    @EnvironmentObject private var theme: ThemeModel

    var body: some View {
        let base = theme.backgroundColor
        GeometryReader { proxy in
            LinearGradient(
                colors: [
                    base.opacity(0.0),
                    base.opacity(0.315),
                    base.opacity(0.595)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 90)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .frame(width: proxy.size.width)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

#Preview {
    if #available(iOS 18.0, *) {
        PlayView(hasCompletedSetup: .constant(true))
            .environmentObject(ThemeModel())
            .environmentObject(BookmarksStore())
            .environmentObject(PlaybackStateStore())
            .environmentObject(AppBackend.shared)
    }
}

#if !canImport(UIKit)
// QuickPlayInlineTextFieldMacFallback
private struct QuickPlayInlineTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var isActive: Bool
    let onUp: () -> Void
    let onDown: () -> Void
    let onReturn: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> QuickPlayKeyAwareTextField {
        let field = QuickPlayKeyAwareTextField(frame: .zero)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.placeholderString = "QuickPlay"
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.commandHandler = { command in
            context.coordinator.handle(command: command)
        }
        return field
    }

    func updateNSView(_ nsView: QuickPlayKeyAwareTextField, context: Context) {
        context.coordinator.parent = self

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        let hasEditor = nsView.currentEditor() != nil
        if isFocused && !hasEditor {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        } else if !isFocused && hasEditor {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nil)
            }
        }

        if !isActive && hasEditor {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nil)
                if isFocused {
                    isFocused = false
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QuickPlayInlineTextField

        init(parent: QuickPlayInlineTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if parent.text != field.stringValue {
                parent.text = field.stringValue
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard parent.isActive else { return false }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onUp()
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onDown()
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onReturn()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            return false
        }

        func handle(command: QuickPlayKeyAwareTextField.Command) -> Bool {
            guard parent.isActive else { return false }
            switch command {
            case .up:
                parent.onUp()
                return true
            case .down:
                parent.onDown()
                return true
            case .enter:
                parent.onReturn()
                return true
            case .escape:
                parent.onEscape()
                return true
            }
        }
    }
}

private final class QuickPlayKeyAwareTextField: NSTextField {
    enum Command {
        case up
        case down
        case enter
        case escape
    }

    var commandHandler: ((Command) -> Bool)?

    override func keyDown(with event: NSEvent) {
        let handled: Bool
        switch event.keyCode {
        case 126:
            handled = commandHandler?(.up) ?? false
        case 125:
            handled = commandHandler?(.down) ?? false
        case 36, 76:
            handled = commandHandler?(.enter) ?? false
        case 53:
            handled = commandHandler?(.escape) ?? false
        default:
            handled = false
        }
        if handled {
            return
        }
        super.keyDown(with: event)
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        if let movement = notification.userInfo?["NSTextMovement"] as? Int,
           movement == NSTextMovement.cancel.rawValue {
            _ = commandHandler?(.escape)
        }
    }
}
#endif

#if !os(iOS)
// AirPlayRoutePickerMacFallback
private struct AirPlayRoutePicker: View {
    var body: some View {
        EmptyView()
    }
}
#endif
