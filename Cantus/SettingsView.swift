import SwiftUI
import UniformTypeIdentifiers
import Foundation
#if os(macOS)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var theme: ThemeModel
    @EnvironmentObject private var backend: AppBackend
    @EnvironmentObject private var bookmarks: BookmarksStore
    @EnvironmentObject private var playback: PlaybackStateStore
    @EnvironmentObject private var premium: PremiumStore
    @EnvironmentObject private var menuState: AppMenuState
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = true
    @State private var showImportPicker = false
    @State private var showExportPicker = false
    @State private var exportDocument: ExportBundleDocument?
    @State private var showExportInfoNav = false
    @State private var isExporting = false
    @State private var exportSummary: LibraryExportSummary?
    @State private var exportSizeBytes: Int64 = 0
    @State private var exportBaseName: String = ""
    @State private var exportError: String?
    @State private var showExportOptions = false
    @State private var showThemePicker = false
    @State private var showThemePickerDestination = false
#if os(iOS)
    @State private var showIconPicker = false
#endif
    @State private var importError: String?
    @State private var importSuccessMessage: String?
    @State private var showPremiumUpgrade: Bool
    @State private var showPremiumUpgradeDestination = false
    @State private var showPremiumDetailsDestination = false
    @State private var showPremiumDetails = false
    @State private var showSubscriptionManagementError = false
    private let showPremiumOnAppear: Bool

    init(showPremiumOnAppear: Bool = false) {
        self.showPremiumOnAppear = showPremiumOnAppear
        _showPremiumUpgrade = State(initialValue: showPremiumOnAppear)
    }

    var body: some View {
        mainView
#if os(iOS)
        .background(.thinMaterial, in: .rect(cornerRadius: 28))
        .sheet(isPresented: $showPremiumUpgrade) {
            PremiumUpgradeView()
                .environmentObject(premium)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showPremiumDetails) {
            PremiumUpgradeView(mode: .subscribed)
                .environmentObject(premium)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showThemePicker) {
            ThemePickerView()
                .environmentObject(theme)
                .environmentObject(premium)
        }
        .sheet(isPresented: $showIconPicker) {
            AppIconPickerView()
                .environmentObject(theme)
                .environmentObject(premium)
        }
#endif
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false
        ) { result in
            handleImportSelection(result)
        }
        .fileExporter(
            isPresented: $showExportPicker,
            document: exportDocument,
            contentType: .zip,
            defaultFilename: exportBaseName
        ) { result in
            if case .failure(let error) = result,
               (error as? CocoaError)?.code != .userCancelled {
                exportError = "Failed to export library."
            }
        }
        .alert("Export Error", isPresented: Binding(get: { exportError != nil }, set: { _ in exportError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .alert("Import Error", isPresented: Binding(get: { importError != nil }, set: { _ in importError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .alert("Import Complete", isPresented: Binding(get: { importSuccessMessage != nil }, set: { _ in importSuccessMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importSuccessMessage ?? "")
        }
        .alert("Unable to Open Subscriptions", isPresented: $showSubscriptionManagementError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please open the App Store and manage your subscription there.")
        }
#if os(iOS)
        .confirmationDialog("Export Library", isPresented: $showExportOptions) {
            Button("Everything") { startExport(scope: .everything) }
            Button("Playlists") { startExport(scope: .playlists) }
            Button("Atmospheres") { startExport(scope: .atmospheres) }
            Button("Sound Effects") { startExport(scope: .soundEffects) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose what you want to export.")
        }
#endif
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Exporting…")
                            .font(.headline)
                            .foregroundStyle(theme.headerColor)
                    }
                    .padding(24)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

}

private extension SettingsView {
    var mainView: some View {
        NavigationStack {
            List {
#if os(macOS)
                settingsHeader
#endif
                premiumSection
                manageLibrarySection
                lookAndFeelSection
                helpSection
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            #endif
            .tint(.primary)
            #if os(iOS)
            .hoverEffectDisabled(true)
            #endif
            .scrollContentBackground(.hidden)
#if os(iOS)
            .navigationTitle("Settings")
#else
            .navigationTitle("")
            .toolbar(removing: .title)
#endif
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .cancellationAction) {
                    if #available(iOS 18.0, *) {
                        ToolbarIconButton(systemName: "xmark", action: { dismiss() }, accessibilityLabel: "Close")
                    } else {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close")
                    }
                }
#endif
            }
            .onAppear {
                Task { await premium.refresh() }
                if showPremiumOnAppear {
                    presentPremiumUpgrade()
                }
            }
            .task(id: menuState.pendingSettingsAction) {
                guard let action = menuState.pendingSettingsAction else { return }
                menuState.pendingSettingsAction = nil
                switch action {
                case .importLibrary:
                    showImportPicker = true
                case .exportLibrary:
#if os(macOS)
                    presentExportScopeDialog()
#else
                    showExportOptions = true
#endif
                }
            }
            .navigationDestination(isPresented: $showExportInfoNav) {
                ExportInfoView(
                    summary: exportSummary,
                    fileSizeBytes: exportSizeBytes,
                    fileBaseName: $exportBaseName,
                    onCancel: { showExportInfoNav = false }
                ) { baseName in
                    exportBaseName = sanitizedExportBaseName(baseName)
                    showExportInfoNav = false
                    showExportPicker = true
                }
            }
            .navigationDestination(isPresented: $showPremiumUpgradeDestination) {
                PremiumUpgradeView(
                    embedInNavigationStack: false,
                    showsCloseButton: false
                )
                .navigationBarBackButtonHidden(false)
            }
            .navigationDestination(isPresented: $showPremiumDetailsDestination) {
                PremiumUpgradeView(
                    mode: .subscribed,
                    embedInNavigationStack: false,
                    showsCloseButton: false
                )
                .navigationBarBackButtonHidden(false)
            }
            .navigationDestination(isPresented: $showThemePickerDestination) {
                ThemePickerView(
                    embedInNavigationStack: false,
                    showsCloseButton: false
                )
                .environmentObject(theme)
                .environmentObject(premium)
                .navigationBarBackButtonHidden(false)
            }
        }
    }
}

private extension SettingsView {
    var settingsCardHorizontalInset: CGFloat { 10 }

    var settingsHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(theme.headerColor)
            Text("Settings")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .listRowInsets(EdgeInsets(
            top: 10,
            leading: settingsCardHorizontalInset,
            bottom: 10,
            trailing: settingsCardHorizontalInset
        ))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .textCase(nil)
            .padding(.leading, settingsCardHorizontalInset)
            .padding(.bottom, 2)
    }

    var settingsCardSeparator: some View {
        Rectangle()
            .fill(.primary.opacity(0.12))
            .frame(height: 0.5)
            .padding(.leading, 42)
    }

    func settingsCardActionRow(
        title: String,
        systemImage: String,
        iconColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 20)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func settingsCardGroup<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 0.5)
        )
        .listRowInsets(EdgeInsets(
            top: 1,
            leading: settingsCardHorizontalInset,
            bottom: 1,
            trailing: settingsCardHorizontalInset
        ))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    var manageLibrarySection: some View {
        Section(
            header: settingsSectionHeader("Manage Library")
        ) {
            settingsCardGroup {
                settingsCardActionRow(
                    title: "Import Sound Library",
                    systemImage: "tray.and.arrow.down",
                    iconColor: theme.headerColor
                ) {
                    showImportPicker = true
                }
                settingsCardSeparator
                settingsCardActionRow(
                    title: "Export Sound Library",
                    systemImage: "archivebox",
                    iconColor: theme.headerColor
                ) {
#if os(macOS)
                    presentExportScopeDialog()
#else
                    showExportOptions = true
#endif
                }
            }
        }
        .listSectionSeparator(.hidden, edges: .all)
    }

    var lookAndFeelSection: some View {
        Section(
            header: settingsSectionHeader("Look & Feel")
        ) {
            settingsCardGroup {
#if os(iOS)
                settingsCardActionRow(
                    title: "App Icon",
                    systemImage: "app.badge",
                    iconColor: theme.headerColor
                ) {
                    presentIconPicker()
                }
                settingsCardSeparator
#endif
                settingsCardActionRow(
                    title: "App Theme",
                    systemImage: "paintpalette",
                    iconColor: theme.headerColor
                ) {
                    presentThemePicker()
                }
            }
        }
        .listSectionSeparator(.hidden, edges: .all)
    }

    var premiumSection: some View {
        Section(
            header: settingsSectionHeader("Cantus Premium")
        ) {
            settingsCardGroup {
                settingsCardActionRow(
                    title: premium.isPremium ? "Subscribed to Premium" : "Upgrade to Premium",
                    systemImage: premium.isPremium ? "checkmark.seal.fill" : "sparkles",
                    iconColor: premium.isPremium ? theme.confirmIconColor : theme.headerColor
                ) {
                    if premium.isPremium {
                        presentPremiumDetails()
                    } else {
                        presentPremiumUpgrade()
                    }
                }
                if premium.isPremium {
                    settingsCardSeparator
                    settingsCardActionRow(
                        title: "Unsubscribe from Premium",
                        systemImage: "minus.circle",
                        iconColor: .red
                    ) {
                        openSubscriptionManagement()
                    }
                }
            }
        }
        .listSectionSeparator(.hidden, edges: .all)
    }

    var helpSection: some View {
        Section(
            header: settingsSectionHeader("Help")
        ) {
            settingsCardGroup {
                settingsCardActionRow(
                    title: "Forgot how to do something? Take the Cantus tour again.",
                    systemImage: "questionmark.circle",
                    iconColor: theme.headerColor
                ) {
                    triggerTourReplay()
                }
            }
        }
        .listSectionSeparator(.hidden, edges: .all)
    }

    func defaultExportBaseName(timestampToken: String, scope: LibraryExportScope) -> String {
        let suffix: String
        switch scope {
        case .everything:
            suffix = "Export"
        case .playlists:
            suffix = "Playlists"
        case .atmospheres:
            suffix = "Atmospheres"
        case .soundEffects:
            suffix = "SoundEffects"
        }
        return "Cantus_\(suffix)_\(timestampToken)"
    }

    func sanitizedExportBaseName(_ baseName: String) -> String {
        let trimmed = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Cantus_Export" }
        if trimmed.lowercased().hasSuffix(".zip") {
            return String(trimmed.dropLast(4))
        }
        return trimmed
    }

    func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    try await importLibrary(from: url)
                } catch {
                    await MainActor.run {
                        importError = "Failed to import library. \(error.localizedDescription)"
                    }
                }
            }
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled {
                return
            }
            importError = "Failed to import library."
        }
    }

    func importLibrary(from url: URL) async throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cantus_Import_\(UUID().uuidString).zip")
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }
        try FileManager.default.copyItem(at: url, to: tempURL)

        var setup = hasCompletedSetup
        try await LibraryExportManager.shared.importBundle(
            zipURL: tempURL,
            backend: backend,
            bookmarks: bookmarks,
            playback: playback,
            hasCompletedSetup: &setup
        )
        await MainActor.run {
            hasCompletedSetup = setup
            importSuccessMessage = "Library imported successfully."
        }
    }

    func startExport(scope: LibraryExportScope) {
        Task {
            isExporting = true
            do {
                let bundle = try await LibraryExportManager.shared.exportBundle(
                    backend: backend,
                    bookmarks: bookmarks,
                    playback: playback,
                    hasCompletedSetup: hasCompletedSetup,
                    scope: scope
                )
                await MainActor.run {
                    exportDocument = ExportBundleDocument(fileURL: bundle.zipURL)
                    exportSummary = bundle.summary
                    exportSizeBytes = bundle.zipSizeBytes
                    exportBaseName = defaultExportBaseName(
                        timestampToken: bundle.timestampToken,
                        scope: bundle.summary.scope
                    )
                    showExportInfoNav = true
                }
            } catch {
                await MainActor.run {
                    exportError = "Failed to export library."
                }
            }
            await MainActor.run {
                isExporting = false
            }
        }
    }

#if os(macOS)
    @MainActor
    func presentExportScopeDialog() {
        let alert = NSAlert()
        alert.messageText = "Export Library"
        alert.informativeText = "Choose what you want to export."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Everything")
        alert.addButton(withTitle: "Playlists")
        alert.addButton(withTitle: "Atmospheres")
        alert.addButton(withTitle: "Sound Effects")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { response in
                handleExportScopeResponse(response)
            }
        } else {
            handleExportScopeResponse(alert.runModal())
        }
    }

    @MainActor
    func handleExportScopeResponse(_ response: NSApplication.ModalResponse) {
        switch response {
        case .alertFirstButtonReturn:
            startExport(scope: .everything)
        case .alertSecondButtonReturn:
            startExport(scope: .playlists)
        case .alertThirdButtonReturn:
            startExport(scope: .atmospheres)
        case NSApplication.ModalResponse(rawValue: 1003):
            startExport(scope: .soundEffects)
        default:
            break
        }
    }
#endif

    func triggerTourReplay() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            menuState.requestTourReplay()
        }
    }

    func presentPremiumUpgrade() {
#if os(macOS)
        showPremiumUpgradeDestination = true
#else
        showPremiumUpgrade = true
#endif
    }

    func presentPremiumDetails() {
#if os(macOS)
        showPremiumDetailsDestination = true
#else
        showPremiumDetails = true
#endif
    }

    func presentThemePicker() {
#if os(macOS)
        showThemePickerDestination = true
#else
        showThemePicker = true
#endif
    }

    #if os(iOS)
    func presentIconPicker() {
        showIconPicker = true
    }
    #endif

    func openSubscriptionManagement() {
        guard let manageURL = URL(string: "https://apps.apple.com/account/subscriptions") else {
            showSubscriptionManagementError = true
            return
        }
        openURL(manageURL) { accepted in
            if !accepted {
                showSubscriptionManagementError = true
            }
        }
    }

}

private struct ExportBundleDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadNoPermission)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: fileURL, options: .immediate)
    }
}

private struct ExportInfoView: View {
    let summary: LibraryExportSummary?
    let fileSizeBytes: Int64
    @Binding var fileBaseName: String
    let onCancel: () -> Void
    let onRequestExport: (String) -> Void
    @EnvironmentObject private var theme: ThemeModel

    private var cardHorizontalInset: CGFloat { 10 }

    private var trimmedFileBaseName: String {
        fileBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSaveDisabled: Bool {
        trimmedFileBaseName.isEmpty
    }

    private var detailRows: [(label: String, value: String)] {
        guard let summary else { return [] }
        return [
            ("Scope", summary.scope.label),
            ("Filesize", ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)),
            ("Playlists", "\(summary.playlistItemCount)"),
            ("Atmospheres", "\(summary.atmosphereCount)"),
            ("Sound Effects", "\(summary.sfxCount)"),
            ("Assets", "\(summary.assetCount)"),
            ("Tags", "\(summary.tagCount) tags")
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Text("Export Library to .ZIP")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                    .listRowInsets(EdgeInsets(
                        top: 8,
                        leading: cardHorizontalInset,
                        bottom: 2,
                        trailing: cardHorizontalInset
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                sectionLabel("Filename")

                TextField(
                    "",
                    text: $fileBaseName,
                    prompt: Text("Cantus_Export_YYYYMMDD")
                        .foregroundStyle(.secondary)
                )
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                #endif
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                )
                .onChange(of: fileBaseName) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.lowercased().hasSuffix(".zip") {
                        fileBaseName = String(trimmed.dropLast(4))
                    }
                }
                .listRowInsets(EdgeInsets(
                    top: 2,
                    leading: cardHorizontalInset,
                    bottom: 12,
                    trailing: cardHorizontalInset
                ))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                sectionLabel("Details")

                if detailRows.isEmpty {
                    Text("Exporting details…")
                        .font(.headline)
                        .foregroundStyle(theme.headerColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.thinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 0.5)
                        )
                        .listRowInsets(EdgeInsets(
                            top: 2,
                            leading: cardHorizontalInset,
                            bottom: 2,
                            trailing: cardHorizontalInset
                        ))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(detailRows.enumerated()), id: \.offset) { index, row in
                            HStack(alignment: .center, spacing: 12) {
                                Text(row.label)
                                    .font(.title3.weight(.medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(row.value)
                                    .font(.title3.weight(.regular))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            if index < detailRows.count - 1 {
                                Rectangle()
                                    .fill(.primary.opacity(0.14))
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(.thinMaterial)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .listRowInsets(EdgeInsets(
                        top: 2,
                        leading: cardHorizontalInset,
                        bottom: 2,
                        trailing: cardHorizontalInset
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Export")
#if os(iOS)
            .navigationBarBackButtonHidden(true)
#else
            .navigationBarBackButtonHidden(false)
#endif
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCancel) {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back")
                    .foregroundStyle(theme.headerColor)
                }
#endif

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        guard !isSaveDisabled else { return }
                        onRequestExport(trimmedFileBaseName)
                    }) {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Save")
                    .foregroundStyle(theme.confirmIconColor)
                    .disabled(isSaveDisabled)
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(
                top: 2,
                leading: cardHorizontalInset + 4,
                bottom: 2,
                trailing: cardHorizontalInset
            ))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

private struct ThemePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeModel
    @EnvironmentObject private var premium: PremiumStore
    @State private var showPremiumUpgrade = false
    @State private var showPremiumUpgradeDestination = false
    private let embedInNavigationStack: Bool
    private let showsCloseButton: Bool

    init(embedInNavigationStack: Bool = true, showsCloseButton: Bool = true) {
        self.embedInNavigationStack = embedInNavigationStack
        self.showsCloseButton = showsCloseButton
    }
    private var cardHorizontalInset: CGFloat { 10 }

    var body: some View {
        Group {
            if embedInNavigationStack {
                NavigationStack {
                    themeContent
                }
            } else {
                themeContent
            }
        }
#if os(iOS)
        .background(.thinMaterial, in: .rect(cornerRadius: 28))
        .sheet(isPresented: $showPremiumUpgrade) {
            PremiumUpgradeView()
                .environmentObject(premium)
                .environmentObject(theme)
        }
#endif
    }

    private var themeContent: some View {
        List {
            themeCardGroup {
                ForEach(Array(CantusThemePalette.all.enumerated()), id: \.element.id) { index, palette in
                    themeOptionRow(palette)
                    if index < CantusThemePalette.all.count - 1 {
                        themeCardSeparator
                    }
                }
            }
            .listSectionSeparator(.hidden, edges: .all)
        }
        .navigationTitle("App Theme")
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarIconButton(systemName: "xmark", action: { dismiss() }, accessibilityLabel: "Close")
                }
            }
        }
        .navigationDestination(isPresented: $showPremiumUpgradeDestination) {
            PremiumUpgradeView(
                embedInNavigationStack: false,
                showsCloseButton: false
            )
            .environmentObject(premium)
            .environmentObject(theme)
            .navigationBarBackButtonHidden(false)
        }
        .scrollContentBackground(.hidden)
    }

    private var themeCardSeparator: some View {
        Rectangle()
            .fill(.primary.opacity(0.12))
            .frame(height: 0.5)
    }

    private func themeCardGroup<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 0.5)
        )
        .listRowInsets(EdgeInsets(
            top: 1,
            leading: cardHorizontalInset,
            bottom: 1,
            trailing: cardHorizontalInset
        ))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func themeOptionRow(_ palette: CantusThemePalette) -> some View {
        Button(action: {
            if palette.id == CantusThemePalette.neon.id || premium.isPremium {
                theme.selectPalette(palette)
            } else {
                presentPremiumUpgrade()
            }
        }) {
            HStack(alignment: .center, spacing: 12) {
                Text(palette.name)
                    .font(.headline)
                Spacer()
                if isLocked(palette) {
                    Text("Premium")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(theme.headerColor.opacity(0.18))
                        )
                        .foregroundStyle(theme.headerColor)
                }
                ThemePreviewThumbnail(palette: palette)
                if theme.palette.id == palette.id {
                    Image(systemName: "checkmark.circle.fill")
                        .frame(width: 18, alignment: .center)
                        .foregroundStyle(theme.confirmIconColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(themeRowOpacity(for: palette))
    }

    private func themeRowOpacity(for palette: CantusThemePalette) -> Double {
        if !isLocked(palette) {
            return 1.0
        }
        return 0.5
    }

    private func isLocked(_ palette: CantusThemePalette) -> Bool {
        !(palette.id == CantusThemePalette.neon.id || premium.isPremium)
    }

    private func presentPremiumUpgrade() {
#if os(macOS)
        showPremiumUpgradeDestination = true
#else
        showPremiumUpgrade = true
#endif
    }
}

private struct ThemePreviewThumbnail: View {
    let palette: CantusThemePalette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.background)
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(palette.indigo.opacity(0.9))
                    .frame(height: 8)
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(palette.accentPrimary)
                        .frame(width: 14, height: 14)
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(palette.accentSecondary)
                        .frame(width: 14, height: 14)
                }
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(palette.background.opacity(0.6))
                    .frame(height: 5)
            }
            .padding(5)
        }
        .frame(width: 48, height: 38, alignment: .center)
        .padding(.vertical, 2)
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

#if os(iOS)
private struct AppIconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeModel
    @EnvironmentObject private var premium: PremiumStore
    @State private var showPremiumUpgrade = false
    @State private var showPremiumUpgradeDestination = false
    @State private var currentIconName: String?
    @State private var iconError: String?
    @State private var supportsAlternateIcons = false
    private let embedInNavigationStack: Bool
    private let showsCloseButton: Bool

    init(embedInNavigationStack: Bool = true, showsCloseButton: Bool = true) {
        self.embedInNavigationStack = embedInNavigationStack
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        Group {
            if embedInNavigationStack {
                NavigationStack {
                    iconContent
                }
            } else {
                iconContent
            }
        }
#if os(iOS)
        .background(.thinMaterial, in: .rect(cornerRadius: 28))
        .sheet(isPresented: $showPremiumUpgrade) {
            PremiumUpgradeView()
                .environmentObject(premium)
                .environmentObject(theme)
        }
#endif
    }

    private var iconContent: some View {
        List {
            Section("App Icons") {
                ForEach(appIconOptions) { option in
                    Button(action: {
                        if option.isDefault || premium.isPremium {
                            Task {
                                do {
                                    try await AppIconManager.setAlternateIconName(option.alternateName)
                                    currentIconName = AppIconManager.currentAlternateName()
                                } catch {
                                    iconError = error.localizedDescription.isEmpty
                                    ? "Unable to change app icon."
                                    : error.localizedDescription
                                }
                            }
                        } else {
                            presentPremiumUpgrade()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Text(option.name)
                                .font(.headline)
                            Spacer()
                            if isLocked(option) {
                                Text("Premium")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(theme.headerColor.opacity(0.18))
                                    )
                                    .foregroundStyle(theme.headerColor)
                            }
                            AppIconPreviewPair(
                                lightName: option.previewLightName,
                                darkName: option.previewDarkName,
                                isDefault: option.isDefault
                            )
                            if isSelected(option) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(theme.confirmIconColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(iconRowOpacity(for: option))
                }
            }
        }
        .navigationTitle("App Icon")
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarIconButton(systemName: "xmark", action: { dismiss() }, accessibilityLabel: "Close")
                }
            }
        }
        .navigationDestination(isPresented: $showPremiumUpgradeDestination) {
            PremiumUpgradeView(
                embedInNavigationStack: false,
                showsCloseButton: false
            )
            .environmentObject(premium)
            .environmentObject(theme)
            .navigationBarBackButtonHidden(false)
        }
        .alert("Icon Error", isPresented: Binding(get: { iconError != nil }, set: { _ in iconError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(iconError ?? "")
        }
        .task {
            supportsAlternateIcons = AppIconManager.supportsAlternateIcons
            currentIconName = AppIconManager.currentAlternateName()
        }
    }

    private var appIconOptions: [AppIconOption] {
        [
            AppIconOption(
                id: "default",
                name: "Default",
                alternateName: nil,
                previewLightName: "Cantus-Icon-Default_01a-iOS-Default-1024x1024@1x",
                previewDarkName: "Cantus-Icon-Default_01a-iOS-Dark-1024x1024@1x",
                isDefault: true
            ),
            AppIconOption(
                id: "dungeon_red",
                name: "Dungeon Red",
                alternateName: "Cantus-Icon-DungeonRed_01a",
                previewLightName: "Cantus-Icon-DungeonRed_01a-iOS-Default-1024x1024@1x",
                previewDarkName: "Cantus-Icon-DungeonRed_01a-iOS-Dark-1024x1024@1x",
                isDefault: false
            ),
            AppIconOption(
                id: "sage_rose",
                name: "Sage Rose",
                alternateName: "Cantus-Icon-SageRose_01a",
                previewLightName: "Cantus-Icon-SageRose_01a-iOS-Default-1024x1024@1x",
                previewDarkName: "Cantus-Icon-SageRose_01a-iOS-Dark-1024x1024@1x",
                isDefault: false
            ),
            AppIconOption(
                id: "electric_lime",
                name: "Electric Lime",
                alternateName: "Cantus-Icon-ElectricLime_01a",
                previewLightName: "Cantus-Icon-ElectricLime_01a-iOS-Default-1024x1024@1x",
                previewDarkName: "Cantus-Icon-ElectricLime_01a-iOS-Dark-1024x1024@1x",
                isDefault: false
            ),
            AppIconOption(
                id: "soft_orchid",
                name: "Soft Orchid",
                alternateName: "Cantus-Icon-SoftOrchid_01a",
                previewLightName: "Cantus-Icon-SoftOrchid_01a-iOS-Default-1024x1024@1x",
                previewDarkName: "Cantus-Icon-SoftOrchid_01a-iOS-Dark-1024x1024@1x",
                isDefault: false
            )
        ]
    }

    private func iconRowOpacity(for option: AppIconOption) -> Double {
        if !isLocked(option) {
            return 1.0
        }
        return 0.45
    }

    private func isLocked(_ option: AppIconOption) -> Bool {
        !(option.isDefault || premium.isPremium)
    }

    private func isSelected(_ option: AppIconOption) -> Bool {
        if option.isDefault {
            return currentIconName == nil
        }
        return currentIconName == option.alternateName
    }

    private func presentPremiumUpgrade() {
#if os(macOS)
        showPremiumUpgradeDestination = true
#else
        showPremiumUpgrade = true
#endif
    }
}
#endif

private struct AppIconOption: Identifiable {
    let id: String
    let name: String
    let alternateName: String?
    let previewLightName: String?
    let previewDarkName: String?
    let isDefault: Bool
}

private struct AppIconPreviewPair: View {
    let lightName: String?
    let darkName: String?
    let isDefault: Bool

    var body: some View {
        HStack(spacing: 6) {
            AppIconPreviewThumbnail(previewName: lightName, isDefault: isDefault)
            AppIconPreviewThumbnail(previewName: darkName, isDefault: isDefault)
        }
    }
}

private struct AppIconPreviewThumbnail: View {
    let previewName: String?
    let isDefault: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.cantusTertiarySystemFill)
            iconPreview
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var iconPreview: some View {
#if canImport(UIKit)
        if let image = loadPreviewImage() {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isDefault ? .primary : .secondary)
        }
#else
        Image(systemName: "app.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isDefault ? .primary : .secondary)
#endif
    }

#if canImport(UIKit)
    private func loadPreviewImage() -> UIImage? {
        if let previewName, let image = UIImage(named: previewName) {
            return image
        }
        guard let previewName,
              let url = Bundle.main.url(forResource: previewName, withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        return image
    }
#endif
}
