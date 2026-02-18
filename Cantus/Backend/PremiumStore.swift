import Foundation
import StoreKit

@MainActor
final class PremiumStore: ObservableObject {
    static let shared = PremiumStore()
    static let didSubscribeNotification = Notification.Name("Cantus.PremiumDidSubscribe")
    private static let pendingAppleMusicPromptKey = "cantus_pending_apple_music_prompt"

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPremium: Bool = false
    @Published private(set) var lastError: String?

    private let productIDs = [
        "cantus_premium_monthly",
        "cantus_premium_yearly"
    ]
    private let debugOverrideKey = "cantus_debug_premium"

    private var updateTask: Task<Void, Never>?

    private init() {
        updateTask = Task { [weak self] in
            await self?.refresh()
            await self?.listenForTransactions()
        }
    }

    deinit {
        updateTask?.cancel()
    }

    func refresh() async {
        do {
            let storeProducts = try await Product.products(for: productIDs)
            products = storeProducts.sorted { lhs, rhs in
                if lhs.id == "cantus_premium_monthly" { return true }
                if rhs.id == "cantus_premium_monthly" { return false }
                return lhs.displayName < rhs.displayName
            }
            isPremium = await hasActiveSubscription()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    isPremium = await hasActiveSubscription()
                    if isPremium {
                        markPendingAppleMusicPrompt()
                        NotificationCenter.default.post(name: Self.didSubscribeNotification, object: nil)
                    }
                    return true
                } else {
                    lastError = "Purchase verification failed."
                }
            case .userCancelled:
                return false
            case .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
        }
        return false
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        _ = await hasActiveSubscription()
        if isPremium {
            markPendingAppleMusicPrompt()
            NotificationCenter.default.post(name: Self.didSubscribeNotification, object: nil)
        }
    }

    private func hasActiveSubscription() async -> Bool {
        if debugOverride {
            isPremium = true
            return true
        }
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard productIDs.contains(transaction.productID) else { continue }
            if let expiration = transaction.expirationDate, expiration < Date() {
                continue
            }
            if transaction.revocationDate != nil {
                continue
            }
            active = true
            break
        }
        isPremium = active
        return active
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            if productIDs.contains(transaction.productID) {
                _ = await hasActiveSubscription()
                await transaction.finish()
                if isPremium {
                    markPendingAppleMusicPrompt()
                    NotificationCenter.default.post(name: Self.didSubscribeNotification, object: nil)
                }
            }
        }
    }

    func consumePendingAppleMusicPrompt() -> Bool {
        let pending = UserDefaults.standard.bool(forKey: Self.pendingAppleMusicPromptKey)
        if pending {
            UserDefaults.standard.set(false, forKey: Self.pendingAppleMusicPromptKey)
        }
        return pending
    }

    private func markPendingAppleMusicPrompt() {
        UserDefaults.standard.set(true, forKey: Self.pendingAppleMusicPromptKey)
    }

    var debugOverride: Bool {
        get { UserDefaults.standard.bool(forKey: debugOverrideKey) }
        set { UserDefaults.standard.set(newValue, forKey: debugOverrideKey) }
    }

    func enableDebugPremium() {
        debugOverride = true
        isPremium = true
    }

    func disableDebugPremium() {
        debugOverride = false
        isPremium = false
    }
}
