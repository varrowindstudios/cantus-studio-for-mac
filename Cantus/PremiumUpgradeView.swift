import SwiftUI
import StoreKit
import MusicKit

struct PremiumUpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var premium: PremiumStore
    @EnvironmentObject private var theme: ThemeModel
    @State private var purchaseError: String?
    @State private var didPromptAppleMusic = false

    var body: some View {
        NavigationStack {
            List {
                Section("The Premium Experience Includes…") {
                    PremiumFeaturesCardView()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section("Plans") {
                    if premium.products.isEmpty {
                        fallbackPlanButton(
                            title: "Premium Monthly",
                            subtitle: "Full access to Apple Music and curated playlists",
                            price: "$1.99 / month"
                        )
                        fallbackPlanButton(
                            title: "Premium Yearly",
                            subtitle: "Best value for full access",
                            price: "$19.99 / year"
                        )
                    } else {
                        ForEach(premium.products) { product in
                            Button {
                                Task {
                                    let success = await premium.purchase(product)
                                    if success {
                                        await requestAppleMusicAccessIfNeeded()
                                        dismiss()
                                    } else if let error = premium.lastError {
                                        purchaseError = error
                                    }
                                }
                            } label: {
                                pricingRow(
                                    title: product.displayName,
                                    subtitle: product.description.nonEmpty,
                                    price: product.displayPrice,
                                    highlight: product.id == "cantus_premium_yearly"
                                )
                            }
                        }
                    }
                }

                Section {
                    Button("Restore Purchases") {
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
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("Upgrade to Premium")
            .toolbar {
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
            .alert("Purchase Error", isPresented: Binding(get: { purchaseError != nil }, set: { _ in purchaseError = nil })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(purchaseError ?? "")
            }
        }
        .cantusGlassBackground()
        .task {
            await premium.refresh()
        }
        .onChange(of: premium.isPremium) { _, newValue in
            if newValue {
                Task { await requestAppleMusicAccessIfNeeded() }
            }
        }
    }

    @MainActor
    private func requestAppleMusicAccessIfNeeded() async {
        guard !didPromptAppleMusic else { return }
        guard MusicAuthorization.currentStatus == .notDetermined else { return }
        didPromptAppleMusic = true
        try? await Task.sleep(nanoseconds: 200_000_000)
        _ = await MusicAuthorization.request()
    }

    @ViewBuilder
    private func fallbackPlanButton(title: String, subtitle: String, price: String) -> some View {
        Button {
            premium.enableDebugPremium()
            dismiss()
        } label: {
            pricingRow(
                title: title,
                subtitle: subtitle,
                price: price,
                highlight: title.lowercased().contains("year")
            )
        }
    }

    private func pricingRow(title: String, subtitle: String?, price: String, highlight: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(theme.headerColor)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.primary)
                }
            }
            Spacer()
            Text(price)
                .font(.headline)
                .foregroundStyle(theme.confirmIconColor)
        }
        .contentShape(Rectangle())
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

    private static let defaultItems: [PremiumFeatureItem] = [
        PremiumFeatureItem(icon: "music.note", title: "Connect to Apple Music", detail: "Add and playback your playlists, plus individual songs."),
        PremiumFeatureItem(icon: "sparkles", title: "Curated Playlists", detail: "Dozens of custom mood playlists for your game."),
        PremiumFeatureItem(icon: "paintpalette", title: "Themes & Icons", detail: "Personalize Cantus to match your style.")
    ]

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
