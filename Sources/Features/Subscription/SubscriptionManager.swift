import AppKit
import StoreKit

/// Tracks the YnShot Pro auto-renewable subscription with StoreKit 2.
/// Product IDs must match App Store Connect; `Configuration/YnShot.storekit` mirrors them for local testing.
@MainActor
public final class SubscriptionManager: ObservableObject {
    public static let shared = SubscriptionManager()

    // PLACEHOLDER: replace with the product IDs created in App Store Connect.
    public static let productIDs = ["com.screenshotapp.mac.pro.monthly", "com.screenshotapp.mac.pro.yearly"]

    public static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    /// The active Pro transaction, or nil when not subscribed
    @Published public private(set) var activeTransaction: StoreKit.Transaction?
    @Published public private(set) var activeProductName: String?

    public var isPro: Bool { activeTransaction != nil }

    private var updatesTask: Task<Void, Never>?

    private init() {
        // Renewals, refunds and purchases made on other Macs arrive here
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task { await refreshEntitlements() }
    }

    deinit {
        updatesTask?.cancel()
    }

    public func refreshEntitlements() async {
        var active: StoreKit.Transaction?
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            active = transaction
        }
        activeTransaction = active
        if let productID = active?.productID {
            activeProductName = try? await Product.products(for: [productID]).first?.displayName
        } else {
            activeProductName = nil
        }
        AppLogger.shared.app.info("Subscription status: \(active == nil ? "free" : "pro", privacy: .public)")
    }

    public func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    public func openManageSubscriptions() {
        NSWorkspace.shared.open(Self.manageSubscriptionsURL)
    }
}
