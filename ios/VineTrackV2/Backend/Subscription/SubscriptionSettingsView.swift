import SwiftUI
import RevenueCat

struct SubscriptionSettingsView: View {
    @Environment(SubscriptionService.self) private var subscription
    @State private var showPaywall: Bool = false
    @State private var statusMessage: String?

    private var entitlement: EntitlementInfo? {
        subscription.customerInfo?.entitlements[SubscriptionService.entitlementIdentifier]
    }

    var body: some View {
        Form {
            statusSection
            actionsSection
            if let entitlement {
                detailsSection(entitlement)
            }
            helpSection
        }
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await subscription.refreshCustomerInfo()
            await subscription.refreshOfferings()
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack {
                SubscriptionPaywallView(allowDismiss: true)
            }
        }
    }

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: subscription.hasAccess ? "checkmark.seal.fill" : "lock.fill")
                    .font(.title2)
                    .foregroundStyle(subscription.hasAccess ? Color.green : Color.orange)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        } header: {
            Text("Status")
        }
    }

    private var statusTitle: String {
        if subscription.isSubscribed { return "Vineyard Tracker Pro" }
        if subscription.isInInitialFreeAccessPeriod { return "Free access active" }
        return "No active subscription"
    }

    private var statusSubtitle: String {
        if subscription.isSubscribed {
            if let expiry = entitlement?.expirationDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                let prefix = entitlement?.willRenew == true ? "Renews" : "Expires"
                return "\(prefix) \(formatter.string(from: expiry))"
            }
            return "Active"
        }
        if subscription.isInInitialFreeAccessPeriod {
            if let freeAccessEndsAt = subscription.freeAccessEndsAt {
                return "Paywall hidden until \(freeAccessEndsAt.formatted(date: .abbreviated, time: .omitted))"
            }
            return "Paywall hidden during your first 3 months"
        }
        switch subscription.status {
        case .loading: return "Checking subscription…"
        case .failure(let m): return m
        default: return "Subscribe to unlock all vineyard features"
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            if !subscription.hasAccess {
                Button {
                    showPaywall = true
                } label: {
                    Label("View Plans", systemImage: "creditcard.fill")
                }
            }
            Button {
                Task {
                    let restored = await subscription.restorePurchases()
                    statusMessage = restored
                        ? "Purchases restored."
                        : (subscription.lastError ?? "No active purchases found.")
                }
            } label: {
                HStack {
                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                    Spacer()
                    if subscription.isRestoring { ProgressView() }
                }
            }
            .disabled(subscription.isRestoring)

            Button {
                Task { await subscription.refreshCustomerInfo() }
            } label: {
                Label("Refresh Status", systemImage: "arrow.triangle.2.circlepath")
            }

            if subscription.isSubscribed,
               let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                Link(destination: url) {
                    Label("Manage Subscription", systemImage: "arrow.up.right.square")
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detailsSection(_ entitlement: EntitlementInfo) -> some View {
        Section("Details") {
            LabeledContent("Plan", value: entitlement.productIdentifier)
            if let purchaseDate = entitlement.latestPurchaseDate {
                LabeledContent("Purchased", value: purchaseDate.formatted(date: .abbreviated, time: .omitted))
            }
            if let expiry = entitlement.expirationDate {
                LabeledContent(entitlement.willRenew ? "Renews" : "Expires",
                               value: expiry.formatted(date: .abbreviated, time: .omitted))
            }
            if entitlement.periodType == .trial {
                LabeledContent("Trial", value: "Active")
            }
        }
    }

    @Environment(\.openURL) private var openURL

    private var helpSection: some View {
        Section {
            Button {
                if let url = URL(string: "https://vinetrack.com.au/privacy") { openURL(url) }
            } label: {
                HStack {
                    Text("Privacy Policy")
                    Spacer()
                    Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") { openURL(url) }
            } label: {
                HStack {
                    Text("Terms of Use (EULA)")
                    Spacer()
                    Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } footer: {
            Text("Subscriptions are billed through your Apple ID. A 3-month free trial applies to new subscribers.")
        }
    }
}
