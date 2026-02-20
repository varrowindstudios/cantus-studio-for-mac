import SwiftUI
import StoreKit
import MusicKit

struct PremiumUpgradeView: View {
    enum Mode: Equatable {
        case upgrade
        case subscribed

        var iOSNavigationTitle: String {
            switch self {
            case .upgrade:
                return "Upgrade to Premium"
            case .subscribed:
                return "Cantus Premium"
            }
        }

        var macHeaderTitle: String {
            switch self {
            case .upgrade:
                return "Upgrade to Premium"
            case .subscribed:
                return "You’re Premium"
            }
        }

        var macHeaderIcon: String {
            switch self {
            case .upgrade:
                return "sparkles"
            case .subscribed:
                return "checkmark.seal.fill"
            }
        }

        var benefitsSectionTitle: String {
            switch self {
            case .upgrade:
                return "The Premium Experience Includes…"
            case .subscribed:
                return "Your Premium Benefits"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var premium: PremiumStore
    @EnvironmentObject private var theme: ThemeModel
    @State private var purchaseError: String?
    @State private var didPromptAppleMusic = false
    @State private var showSubscriptionManagementError = false
    private let mode: Mode
    private let embedInNavigationStack: Bool
    private let showsCloseButton: Bool
    private var cardHorizontalInset: CGFloat { 10 }

    init(
        mode: Mode = .upgrade,
        embedInNavigationStack: Bool = true,
        showsCloseButton: Bool = true
    ) {
        self.mode = mode
        self.embedInNavigationStack = embedInNavigationStack
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        Group {
            if embedInNavigationStack {
                NavigationStack { premiumContent }
            } else {
                premiumContent
            }
        }
        .cantusGlassBackground()
        .task {
            await premium.refresh()
        }
        .onChange(of: premium.isPremium) { _, newValue in
            guard newValue else { return }
            Task { await requestAppleMusicAccessIfNeeded() }
        }
    }

    @ViewBuilder
    private var premiumContent: some View {
        List {
#if os(macOS)
            premiumHeader
#endif
            Section(header: premiumSectionHeader(mode.benefitsSectionTitle)) {
                premiumCardGroup {
                    ForEach(Array(PremiumFeaturesCardView.defaultItems.enumerated()), id: \.offset) { index, item in
                        premiumFeatureRow(item: item)
                        if index < PremiumFeaturesCardView.defaultItems.count - 1 {
                            premiumCardSeparator
                        }
                    }
                }
            }
            .listSectionSeparator(.hidden, edges: .all)

            if mode == .upgrade {
                plansSection
                accountRestoreSection
            } else {
                membershipSection
            }
        }
#if os(iOS)
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle(mode.iOSNavigationTitle)
#else
        .listStyle(.plain)
        .navigationTitle("")
        .toolbar(removing: .title)
#endif
        .scrollContentBackground(.hidden)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    if #available(iOS 18.0, *) {
                        ToolbarIconButton(systemName: "xmark", action: { dismiss() }, accessibilityLabel: "Close")
                    } else {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close")
                        .foregroundStyle(theme.headerColor)
                    }
                }
            }
        }
        .alert("Purchase Error", isPresented: Binding(get: { purchaseError != nil }, set: { _ in purchaseError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(purchaseError ?? "")
        }
        .alert("Unable to Open Subscriptions", isPresented: $showSubscriptionManagementError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please open the App Store and manage your subscription there.")
        }
    }

    private var plansSection: some View {
        Section(header: premiumSectionHeader("Plans")) {
            if premium.products.isEmpty {
                premiumCardGroup {
                    premiumPlanRow(
                        title: "Premium Monthly",
                        subtitle: "Full access to Apple Music and curated playlists",
                        price: "$1.99 / month",
                        highlight: false
                    ) {
                        premium.enableDebugPremium()
                        dismiss()
                    }
                    premiumCardSeparator
                    premiumPlanRow(
                        title: "Premium Yearly",
                        subtitle: "Best value for full access",
                        price: "$19.99 / year",
                        highlight: true
                    ) {
                        premium.enableDebugPremium()
                        dismiss()
                    }
                }
            } else {
                premiumCardGroup {
                    ForEach(Array(premium.products.enumerated()), id: \.element.id) { index, product in
                        premiumPlanRow(
                            title: product.displayName,
                            subtitle: product.description.nonEmpty,
                            price: product.displayPrice,
                            highlight: product.id == "cantus_premium_yearly"
                        ) {
                            Task {
                                let success = await premium.purchase(product)
                                if success {
                                    await requestAppleMusicAccessIfNeeded()
                                    dismiss()
                                } else if let error = premium.lastError {
                                    purchaseError = error
                                }
                            }
                        }
                        if index < premium.products.count - 1 {
                            premiumCardSeparator
                        }
                    }
                }
            }
        }
        .listSectionSeparator(.hidden, edges: .all)
    }

    private var accountRestoreSection: some View {
        Section(header: premiumSectionHeader("Account")) {
            premiumCardGroup {
                premiumActionRow(
                    title: "Restore Purchases",
                    systemImage: "arrow.clockwise",
                    iconColor: theme.headerColor
                ) {
                    Task {
                        await premium.restore()
                        if premium.isPremium {
                            await requestAppleMusicAccessIfNeeded()
                            dismiss()
                        }
                    }
                }
            }
        }
        .listSectionSeparator(.hidden, edges: .all)
    }

    private var membershipSection: some View {
        Section(header: premiumSectionHeader("Membership")) {
            premiumCardGroup {
                premiumStatusRow
                premiumCardSeparator
                premiumActionRow(
                    title: "Manage Subscription",
                    systemImage: "arrow.up.right.square",
                    iconColor: theme.headerColor
                ) {
                    openSubscriptionManagement()
                }
                premiumCardSeparator
                premiumActionRow(
                    title: "Restore Purchases",
                    systemImage: "arrow.clockwise",
                    iconColor: theme.headerColor
                ) {
                    Task { await premium.restore() }
                }
            }
        }
        .listSectionSeparator(.hidden, edges: .all)
    }

    @MainActor
    private func requestAppleMusicAccessIfNeeded() async {
        guard mode == .upgrade else { return }
        guard !didPromptAppleMusic else { return }
        guard MusicAuthorization.currentStatus == .notDetermined else { return }
        didPromptAppleMusic = true
        try? await Task.sleep(nanoseconds: 200_000_000)
        _ = await MusicAuthorization.request()
    }

    private var premiumHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: mode.macHeaderIcon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(mode == .upgrade ? theme.headerColor : theme.confirmIconColor)
            Text(mode.macHeaderTitle)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .listRowInsets(EdgeInsets(
            top: 10,
            leading: cardHorizontalInset,
            bottom: 10,
            trailing: cardHorizontalInset
        ))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func premiumSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .textCase(nil)
            .padding(.leading, cardHorizontalInset)
            .padding(.bottom, 2)
    }

    private var premiumCardSeparator: some View {
        Rectangle()
            .fill(.primary.opacity(0.12))
            .frame(height: 0.5)
            .padding(.leading, 42)
    }

    private func premiumCardGroup<Content: View>(
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

    private var premiumStatusRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .frame(width: 20)
                .foregroundStyle(theme.confirmIconColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("Subscription Active")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Thanks for supporting Cantus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func premiumActionRow(
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

    private func premiumPlanRow(
        title: String,
        subtitle: String?,
        price: String,
        highlight: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: highlight ? "star.circle.fill" : "sparkles")
                    .frame(width: 20)
                    .foregroundStyle(highlight ? theme.confirmIconColor : theme.headerColor)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if highlight {
                            Text("Best Value")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(theme.confirmIconColor.opacity(0.18)))
                                .foregroundStyle(theme.confirmIconColor)
                        }
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(price)
                    .font(.headline)
                    .foregroundStyle(theme.confirmIconColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func premiumFeatureRow(item: PremiumFeatureItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.icon)
                .frame(width: 20)
                .foregroundStyle(featureIconTint(for: item))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func featureIconTint(for item: PremiumFeatureItem) -> Color {
        if let tint = item.tint {
            return tint
        }
        switch item.icon {
        case "music.note":
            return theme.headerColor
        case "sparkles":
            return theme.confirmIconColor
        case "paintpalette":
            return theme.indigoColor
        default:
            return theme.confirmIconColor
        }
    }

    private func openSubscriptionManagement() {
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

struct PremiumFeatureItem {
    let icon: String
    let title: String
    let detail: String?
    let tint: Color?

    init(icon: String, title: String, detail: String? = nil, tint: Color? = nil) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.tint = tint
    }
}

struct PremiumFeaturesCardView: View {
    let items: [PremiumFeatureItem]
    @EnvironmentObject private var theme: ThemeModel

    init(items: [PremiumFeatureItem] = PremiumFeaturesCardView.defaultItems) {
        self.items = items
    }

#if os(macOS)
    static let defaultItems: [PremiumFeatureItem] = [
        PremiumFeatureItem(icon: "music.note", title: "Connect to Apple Music", detail: "Add and playback your playlists, plus individual songs."),
        PremiumFeatureItem(icon: "sparkles", title: "Curated Playlists", detail: "Dozens of custom mood playlists for your game."),
        PremiumFeatureItem(icon: "paintpalette", title: "Premium Themes", detail: "Unlock additional theme palettes.")
    ]
#else
    static let defaultItems: [PremiumFeatureItem] = [
        PremiumFeatureItem(icon: "music.note", title: "Connect to Apple Music", detail: "Add and playback your playlists, plus individual songs."),
        PremiumFeatureItem(icon: "sparkles", title: "Curated Playlists", detail: "Dozens of custom mood playlists for your game."),
        PremiumFeatureItem(icon: "paintpalette", title: "Themes & Icons", detail: "Personalize Cantus to match your style.")
    ]
#endif

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(items.indices, id: \.self) { index in
                featureRow(item: items[index])
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private func featureRow(item: PremiumFeatureItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.icon)
                .font(.title3)
                .foregroundStyle(iconTint(for: item))
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func iconTint(for item: PremiumFeatureItem) -> Color {
        if let tint = item.tint {
            return tint
        }
        switch item.icon {
        case "music.note":
            return theme.headerColor
        case "sparkles":
            return theme.confirmIconColor
        case "paintpalette":
            return theme.indigoColor
        default:
            return theme.confirmIconColor
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
