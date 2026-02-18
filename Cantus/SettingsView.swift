import SwiftUI
import UniformTypeIdentifiers
import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
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
    @State private var showIconPicker = false
    @State private var importError: String?
    @State private var importSuccessMessage: String?
    @State private var showPremiumUpgrade: Bool
    @State private var showPremiumDetails = false
    private let showPremiumOnAppear: Bool

    init(showPremiumOnAppear: Bool = false) {
        self.showPremiumOnAppear = showPremiumOnAppear
        _showPremiumUpgrade = State(initialValue: showPremiumOnAppear)
    }

    var body: some View {
        mainView
#if os(iOS)
        .background(.thinMaterial, in: .rect(cornerRadius: 28))
#endif
        .sheet(isPresented: $showPremiumUpgrade) {
            PremiumUpgradeView()
                .environmentObject(premium)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showPremiumDetails) {
            PremiumSubscribedView()
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
        .confirmationDialog("Export Library", isPresented: $showExportOptions) {
            ForEach(LibraryExportScope.allCases) { scope in
                Button(scope.label) {
                    startExport(scope: scope)
                }
            }
            Button("Cancel", role: .cancel) {}
                .foregroundStyle(theme.headerColor)
        } message: {
            Text("Choose what you want to export.")
        }
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
            .navigationTitle("Settings")
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
                    showPremiumUpgrade = true
                }
            }
            .task(id: menuState.pendingSettingsAction) {
                guard let action = menuState.pendingSettingsAction else { return }
                menuState.pendingSettingsAction = nil
                switch action {
                case .importLibrary:
                    showImportPicker = true
                case .exportLibrary:
                    showExportOptions = true
                }
            }
            .navigationDestination(isPresented: $showExportInfoNav) {
                ExportInfoView(
                    summary: exportSummary,
                    fileSizeBytes: exportSizeBytes,
                    fileBaseName: $exportBaseName,
                    onCancel: { showExportInfoNav = false },
                    onExportResult: { result in
                        if case .failure = result {
                            exportError = "Failed to export library."
                        }
                    }
                ) { baseName in
                    exportBaseName = sanitizedExportBaseName(baseName)
                    showExportInfoNav = false
                    showExportPicker = true
                }
            }
        }
    }
}

private extension SettingsView {
    var manageLibrarySection: some View {
        Section(
            header: Text("Manage Library")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        ) {
            Button(action: { showImportPicker = true }) {
                Label {
                    Text("Import Sound Library")
                } icon: {
                    Image(systemName: "tray.and.arrow.down")
                        .foregroundStyle(theme.headerColor)
                }
                .font(.body)
            }
            Button {
                showExportOptions = true
            } label: {
                Label {
                    Text("Export Sound Library")
                } icon: {
                    Image(systemName: "archivebox")
                        .foregroundStyle(theme.headerColor)
                }
                .font(.body)
            }
        }
        .listRowBackground(Rectangle().fill(.thinMaterial))
    }

    var lookAndFeelSection: some View {
        Section(
            header: Text("Look & Feel")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        ) {
            Button(action: { showIconPicker = true }) {
                Label {
                    Text("App Icon")
                } icon: {
                    Image(systemName: "app.badge")
                        .foregroundStyle(theme.headerColor)
                }
                .font(.body)
            }
            Button(action: { showThemePicker = true }) {
                Label {
                    Text("App Theme")
                } icon: {
                    Image(systemName: "paintpalette")
                        .foregroundStyle(theme.headerColor)
                }
                .font(.body)
            }
        }
        .listRowBackground(Rectangle().fill(.thinMaterial))
    }

    var premiumSection: some View {
        Section(
            header: Text("Cantus Premium")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        ) {
            Button {
                if premium.isPremium {
                    showPremiumDetails = true
                } else {
                    showPremiumUpgrade = true
                }
            } label: {
                Label {
                    Text(premium.isPremium ? "Subscribed to Premium" : "Upgrade to Premium")
                } icon: {
                    Image(systemName: premium.isPremium ? "checkmark.seal.fill" : "sparkles")
                        .foregroundStyle(premium.isPremium ? theme.confirmIconColor : theme.headerColor)
                }
                .font(.body)
            }
        }
        .listRowBackground(Rectangle().fill(.thinMaterial))
    }

    var helpSection: some View {
        Section(
            header: Text("Help")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        ) {
            Button(action: triggerTourReplay) {
                Label {
                    Text("Forgot how to do something? Take the Cantus tour again.")
                } icon: {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(theme.headerColor)
                }
                .font(.body)
            }
        }
        .listRowBackground(Rectangle().fill(.thinMaterial))
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

    func triggerTourReplay() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            menuState.requestTourReplay()
        }
    }

}

private struct PremiumSubscribedView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("You are subscribed to Premium")
                                .font(.headline)
                            Text("Thanks for supporting Cantus.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(theme.confirmIconColor)
                    }
                    .padding(.vertical, 4)
                }

                Section("The Premium Experience Includes…") {
                    PremiumFeaturesCardView()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("Cantus Premium")
            .toolbar {
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
            }
        }
        .cantusGlassBackground()
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
    let onExportResult: (Result<URL, Error>) -> Void
    let onRequestExport: (String) -> Void
    @EnvironmentObject private var theme: ThemeModel
    var body: some View {
        NavigationStack {
            Form {
                Section("Filename") {
                    TextField(
                        "",
                        text: $fileBaseName,
                        prompt: Text("Cantus_Export_YYYYMMDD")
                            .foregroundStyle(theme.confirmIconColor)
                    )
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    #endif
                    .foregroundStyle(.primary)
                    .onChange(of: fileBaseName) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.lowercased().hasSuffix(".zip") {
                            fileBaseName = String(trimmed.dropLast(4))
                        }
                    }

                }
                .listRowBackground(Color(.sRGB, red: 17.0 / 255.0, green: 17.0 / 255.0, blue: 17.0 / 255.0, opacity: 1.0))

                Section("Details") {
                    if let summary {
                        LabeledContent("Scope", value: summary.scope.label)
                        LabeledContent("Filesize", value: ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file))
                        LabeledContent("Playlists", value: "\(summary.playlistItemCount)")
                        LabeledContent("Atmospheres", value: "\(summary.atmosphereCount)")
                        LabeledContent("Sound Effects", value: "\(summary.sfxCount)")
                        LabeledContent("Assets", value: "\(summary.assetCount)")
                        LabeledContent("Tags", value: "\(summary.tagCount) tags")
                    } else {
                        Text("Exporting details…")
                            .foregroundStyle(theme.headerColor)
                    }
                }
            }
            .navigationTitle("Export Library to .ZIP")
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if #available(iOS 18.0, *) {
                        ToolbarIconButton(systemName: "xmark", action: onCancel, accessibilityLabel: "Cancel")
                    } else {
                        Button(action: onCancel) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Cancel")
                        .foregroundStyle(theme.headerColor)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    let action = {
                        let trimmed = fileBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else {
                            onExportResult(.failure(CocoaError(.fileWriteInvalidFileName)))
                            return
                        }
                        onRequestExport(trimmed)
                    }
                    if #available(iOS 18.0, *) {
                        ToolbarIconButton(systemName: "checkmark", action: action, accessibilityLabel: "Save")
                    } else {
                        Button(action: action) {
                            Image(systemName: "checkmark")
                        }
                        .accessibilityLabel("Save")
                        .foregroundStyle(theme.confirmIconColor)
                    }
                }
            }
        }
    }
}

private struct ThemePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeModel
    @EnvironmentObject private var premium: PremiumStore
    @State private var showPremiumUpgrade = false

    var body: some View {
        NavigationStack {
            List {
                Section("Available Themes") {
                    ForEach(CantusThemePalette.all) { palette in
                        Button(action: {
                            if palette.id == CantusThemePalette.neon.id || premium.isPremium {
                                theme.selectPalette(palette)
                            } else {
                                showPremiumUpgrade = true
                            }
                        }) {
                            HStack(spacing: 12) {
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
                                        .foregroundStyle(theme.confirmIconColor)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(themeRowOpacity(for: palette))
                    }
                }
            }
            .navigationTitle("App Theme")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarIconButton(systemName: "xmark", action: { dismiss() }, accessibilityLabel: "Close")
                }
            }
        }
        .background(.thinMaterial, in: .rect(cornerRadius: 28))
        .sheet(isPresented: $showPremiumUpgrade) {
            PremiumUpgradeView()
                .environmentObject(premium)
                .environmentObject(theme)
        }
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
}

private struct ThemePreviewThumbnail: View {
    let palette: CantusThemePalette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.background)
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.indigo.opacity(0.9))
                    .frame(height: 10)
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(palette.accentPrimary)
                        .frame(width: 18, height: 18)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(palette.accentSecondary)
                        .frame(width: 18, height: 18)
                }
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.background.opacity(0.6))
                    .frame(height: 6)
            }
            .padding(6)
        }
        .frame(width: 58, height: 46)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct AppIconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeModel
    @EnvironmentObject private var premium: PremiumStore
    @State private var showPremiumUpgrade = false
    @State private var currentIconName: String?
    @State private var iconError: String?
    @State private var supportsAlternateIcons = false

    var body: some View {
        NavigationStack {
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
                                showPremiumUpgrade = true
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
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarIconButton(systemName: "xmark", action: { dismiss() }, accessibilityLabel: "Close")
                }
            }
        }
        .background(.thinMaterial, in: .rect(cornerRadius: 28))
        .sheet(isPresented: $showPremiumUpgrade) {
            PremiumUpgradeView()
                .environmentObject(premium)
                .environmentObject(theme)
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
}

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
