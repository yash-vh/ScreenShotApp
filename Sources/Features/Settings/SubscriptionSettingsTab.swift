import StoreKit
import SwiftUI

/// ScreenMint Pro: Apple's subscription store when not subscribed, plan status and management when subscribed.
struct SubscriptionSettingsTab: View {
    @ObservedObject private var subscriptions = SubscriptionManager.shared
    @State private var isRestoring = false
    /// nil while loading; empty when the App Store returned no plans
    @State private var availableProducts: [Product]?

    var body: some View {
        Group {
            if subscriptions.isPro {
                activePlan
            } else if availableProducts?.isEmpty == true {
                unavailable
            } else {
                store
            }
        }
        .task {
            await subscriptions.refreshEntitlements()
            availableProducts = (try? await Product.products(for: SubscriptionManager.productIDs)) ?? []
        }
    }

    // MARK: - Store unreachable

    /// Shown when no plans load (offline, or products not yet live in App Store Connect)
    private var unavailable: some View {
        VStack(spacing: 18) {
            ProMarketingHeader()
            VStack(spacing: 4) {
                Text("Plans aren't available right now")
                    .font(.headline)
                Text("Check your internet connection and try again.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button("Try Again") {
                    availableProducts = nil
                    Task { availableProducts = (try? await Product.products(for: SubscriptionManager.productIDs)) ?? [] }
                }
                .buttonStyle(.borderedProminent)
                Button(isRestoring ? "Restoring…" : "Restore Purchases") {
                    isRestoring = true
                    Task {
                        await subscriptions.restorePurchases()
                        isRestoring = false
                    }
                }
                .disabled(isRestoring)
            }
            .controlSize(.large)
            HStack(spacing: 16) {
                Link("Privacy Policy", destination: AppBranding.privacyPolicyURL)
                Text("·").foregroundStyle(.tertiary)
                Link("Terms of Use", destination: AppBranding.termsOfUseURL)
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Not subscribed

    private var store: some View {
        SubscriptionStoreView(productIDs: SubscriptionManager.productIDs) {
            ProMarketingHeader()
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .subscriptionStoreButtonLabel(.multiline)
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.hidden, for: .cancellation)
        .subscriptionStorePolicyDestination(url: AppBranding.privacyPolicyURL, for: .privacyPolicy)
        .subscriptionStorePolicyDestination(url: AppBranding.termsOfUseURL, for: .termsOfService)
        .onInAppPurchaseCompletion { _, _ in
            await subscriptions.refreshEntitlements()
        }
    }

    // MARK: - Subscribed

    private var activePlan: some View {
        Form {
            Section {
                LabeledContent {
                    Label("Active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } label: {
                    SettingsRowLabel(
                        title: subscriptions.activeProductName ?? "\(AppBranding.appName) Pro",
                        subtitle: renewalText
                    )
                }
                LabeledContent {
                    Button("Manage…") { subscriptions.openManageSubscriptions() }
                } label: {
                    SettingsRowLabel(title: "Change or cancel", subtitle: "Billing is handled by the App Store.")
                }
            } header: {
                Text("Your Plan")
            }

            Section {
                LabeledContent {
                    Button(isRestoring ? "Restoring…" : "Restore Purchases") {
                        isRestoring = true
                        Task {
                            await subscriptions.restorePurchases()
                            isRestoring = false
                        }
                    }
                    .disabled(isRestoring)
                } label: {
                    SettingsRowLabel(title: "Restore Purchases", subtitle: "Use this after reinstalling or on another Mac.")
                }
                LabeledContent("Privacy Policy") {
                    Link("Open", destination: AppBranding.privacyPolicyURL)
                }
                LabeledContent("Terms of Use") {
                    Link("Open", destination: AppBranding.termsOfUseURL)
                }
            } header: {
                Text("Account")
            }
        }
        .formStyle(.grouped)
    }

    private var renewalText: String {
        guard let transaction = subscriptions.activeTransaction else { return "" }
        if let expires = transaction.expirationDate {
            return "Renews \(expires.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Purchased \(transaction.purchaseDate.formatted(date: .abbreviated, time: .omitted))"
    }
}

/// Marketing header shown above Apple's plan picker
private struct ProMarketingHeader: View {
    // PLACEHOLDER: describe what ScreenMint Pro unlocks; every line here must match a real benefit.
    private let benefits: [(String, String)] = [
        ("icloud.and.arrow.up.fill", "Uploads to ImgBB and your own S3 bucket"),
        ("sparkles", "Every new \(AppBranding.appName) feature as it ships"),
        ("heart.fill", "Supports independent development")
    ]

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: AppBranding.logo(size: 72))
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
            VStack(spacing: 4) {
                Text("\(AppBranding.appName) Pro")
                    .font(.largeTitle.weight(.bold))
                Text("Capture, annotate and share without limits.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(benefits, id: \.1) { symbol, text in
                    Label {
                        Text(text)
                    } icon: {
                        Image(systemName: symbol)
                            .foregroundStyle(.yellow.gradient)
                    }
                    .font(.body)
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 12)
        .multilineTextAlignment(.center)
    }
}
