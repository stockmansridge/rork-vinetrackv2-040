import Foundation
import Observation
import RevenueCat

/// RevenueCat subscription service.
///
/// V1 product configuration (managed in RevenueCat dashboard + App Store Connect):
///   - Entitlement: `pro` (a.k.a. "Vineyard Tracker Pro")
///   - Default offering exposes the legacy products only:
///       • $9.99 / month with 3-month introductory free trial
///       • $99   / year  with 3-month introductory free trial
///
/// Product IDs / package IDs / offering ID live in the RevenueCat dashboard;
/// the SDK fetches them at runtime so we don't hard-code them in the app.
///
/// IMPORTANT: do NOT add the Basic ($5/$30) products to the default offering.
@Observable
@MainActor
final class SubscriptionService {

    /// RevenueCat entitlement identifier for full app access.
    static let entitlementIdentifier = "pro"

    enum Status: Equatable {
        case unknown
        case loading
        case subscribed
        case notSubscribed
        case failure(String)
    }

    var status: Status = .unknown
    var customerInfo: CustomerInfo?
    var currentOffering: Offering?
    var isPurchasing: Bool = false
    var isRestoring: Bool = false
    var lastError: String?
    var userCreatedAt: Date?

    private var didConfigure: Bool = false
    private var customerInfoStreamTask: Task<Void, Never>?

    var isSubscribed: Bool {
        guard let info = customerInfo else { return false }
        return info.entitlements[Self.entitlementIdentifier]?.isActive == true
    }

    var isInInitialFreeAccessPeriod: Bool {
        guard let userCreatedAt else { return false }
        let calendar = Calendar(identifier: .gregorian)
        guard let freeAccessEndsAt = calendar.date(byAdding: .month, value: 3, to: userCreatedAt) else { return false }
        return Date() < freeAccessEndsAt
    }

    var freeAccessEndsAt: Date? {
        guard let userCreatedAt else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(byAdding: .month, value: 3, to: userCreatedAt)
    }

    var hasAccess: Bool {
        isSubscribed || isInInitialFreeAccessPeriod
    }

    var hasResolvedStatus: Bool {
        switch status {
        case .subscribed, .notSubscribed, .failure: return true
        case .unknown, .loading: return false
        }
    }

    // MARK: - Configuration

    func configureIfNeeded() {
        guard !didConfigure else { return }
        let key = AppConfig.revenueCatIOSAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            #if DEBUG
            print("[Subscription] RevenueCat API key missing — skipping configure().")
            #endif
            status = .failure("Subscription service is not configured.")
            return
        }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: key)
        didConfigure = true
        startCustomerInfoStream()
    }

    private func startCustomerInfoStream() {
        customerInfoStreamTask?.cancel()
        customerInfoStreamTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                await MainActor.run {
                    guard let self else { return }
                    self.applyCustomerInfo(info)
                }
            }
        }
    }

    /// Identify RevenueCat with the Supabase auth user UUID.
    func login(userId: UUID, userCreatedAt: Date?) async {
        self.userCreatedAt = userCreatedAt
        configureIfNeeded()
        guard didConfigure else { return }
        do {
            let result = try await Purchases.shared.logIn(userId.uuidString)
            applyCustomerInfo(result.customerInfo)
            await refreshOfferings()
        } catch {
            lastError = error.localizedDescription
            status = .failure(error.localizedDescription)
        }
    }

    /// Reset RevenueCat identity on sign out.
    func logout() async {
        userCreatedAt = nil
        guard didConfigure else { return }
        do {
            let info = try await Purchases.shared.logOut()
            applyCustomerInfo(info)
        } catch {
            // Logging out of an anonymous user throws; ignore.
            customerInfo = nil
            status = .notSubscribed
        }
        currentOffering = nil
    }

    // MARK: - Refresh

    func refreshCustomerInfo() async {
        configureIfNeeded()
        guard didConfigure else { return }
        status = .loading
        do {
            let info = try await Purchases.shared.customerInfo()
            applyCustomerInfo(info)
        } catch {
            lastError = error.localizedDescription
            status = .failure(error.localizedDescription)
        }
    }

    func refreshOfferings() async {
        configureIfNeeded()
        guard didConfigure else { return }
        do {
            let offerings = try await Purchases.shared.offerings()
            currentOffering = offerings.current
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Purchase / Restore

    @discardableResult
    func purchase(package: Package) async -> Bool {
        configureIfNeeded()
        guard didConfigure else { return false }
        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            applyCustomerInfo(result.customerInfo)
            return result.customerInfo.entitlements[Self.entitlementIdentifier]?.isActive == true
        } catch {
            if (error as? ErrorCode) == .purchaseCancelledError {
                return false
            }
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        configureIfNeeded()
        guard didConfigure else { return false }
        isRestoring = true
        lastError = nil
        defer { isRestoring = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            applyCustomerInfo(info)
            return info.entitlements[Self.entitlementIdentifier]?.isActive == true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Helpers

    private func applyCustomerInfo(_ info: CustomerInfo) {
        customerInfo = info
        let active = info.entitlements[Self.entitlementIdentifier]?.isActive == true
        status = active ? .subscribed : .notSubscribed
    }
}
