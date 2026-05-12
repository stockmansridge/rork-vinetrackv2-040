import SwiftUI

struct NewBackendRootView: View {
    @Environment(NewBackendAuthService.self) private var auth
    @Environment(MigratedDataStore.self) private var store
    @Environment(SubscriptionService.self) private var subscription
    @Environment(BiometricAuthService.self) private var biometric
    @Environment(\.scenePhase) private var scenePhase

    @State private var didAttemptRestore: Bool = false
    @State private var showBiometricEnrollment: Bool = false
    @State private var lastSignedInState: Bool = false
    @State private var onboardingCompleted: Bool = OnboardingState.isCompleted
    @State private var disclaimerAccepted: Bool = false
    @State private var didCheckDisclaimer: Bool = false
    @State private var isCheckingDisclaimer: Bool = false
    @State private var disclaimerError: String?
    @State private var didApplyDefaultVineyard: Bool = false
    @State private var isLoadingVineyards: Bool = false

    private let disclaimerRepository: any DisclaimerRepositoryProtocol = SupabaseDisclaimerRepository(currentVersion: DisclaimerInfo.version)
    private let vineyardRepository: any VineyardRepositoryProtocol = SupabaseVineyardRepository()

    var body: some View {
        Group {
            if !didAttemptRestore {
                loadingView
            } else if auth.isSignedIn && biometric.requiresUnlock {
                BiometricLockView()
            } else if !auth.isSignedIn {
                NewBackendLoginView()
            } else if !onboardingCompleted {
                OnboardingView {
                    OnboardingState.markCompleted()
                    onboardingCompleted = true
                }
            } else if !didCheckDisclaimer {
                disclaimerLoadingView
            } else if !disclaimerAccepted {
                DisclaimerAcceptanceView {
                    disclaimerAccepted = true
                }
            } else if !didApplyDefaultVineyard {
                vineyardLoadingView
            } else if store.selectedVineyard == nil {
                BackendVineyardListView()
            } else if subscription.hasAccess {
                NewMainTabView()
            } else if !subscription.hasResolvedStatus {
                subscriptionLoadingView
            } else {
                NavigationStack {
                    SubscriptionPaywallView(allowDismiss: false)
                }
            }
        }
        .task {
            if !didAttemptRestore {
                await auth.restoreSession()
                if auth.isSignedIn {
                    biometric.lockIfEnabled()
                    biometric.updateSavedEmailIfEnabled(auth.userEmail)
                }
                lastSignedInState = auth.isSignedIn
                didAttemptRestore = true
            }
        }
        .onChange(of: auth.isSignedIn) { _, newValue in
            handleSignedInChange(newValue: newValue)
        }
        .sheet(isPresented: $showBiometricEnrollment) {
            BiometricEnrollmentSheet()
        }
        .task(id: auth.isSignedIn) {
            if auth.isSignedIn {
                await checkDisclaimer()
                if let userId = auth.userId {
                    await subscription.login(userId: userId, userCreatedAt: auth.userCreatedAt)
                }
            } else {
                disclaimerAccepted = false
                didCheckDisclaimer = false
                didApplyDefaultVineyard = false
                await subscription.logout()
            }
        }
        .task(id: disclaimerAccepted) {
            if disclaimerAccepted && !didApplyDefaultVineyard {
                await loadVineyardsAndApplyDefault()
            }
        }
        .task(id: store.selectedVineyardId) {
            if store.selectedVineyardId != nil {
                DefaultDataSeeder.seedIfNeeded(store: store)
            }
        }
        .task(id: auth.isSignedIn) {
            if auth.isSignedIn {
                await auth.loadPendingInvitations()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && auth.isSignedIn {
                Task { await auth.loadPendingInvitations() }
            }
        }
    }

    private func handleSignedInChange(newValue: Bool) {
        defer { lastSignedInState = newValue }
        // Only react on transitions, not initial value.
        guard newValue != lastSignedInState else { return }
        if newValue {
            // User just signed in.
            biometric.updateSavedEmailIfEnabled(auth.userEmail)
            // Offer biometric enrollment once if supported and not enabled.
            if (biometric.deviceSupportsBiometrics || biometric.deviceSupportsAnyAuth),
               !biometric.isEnabled,
               !biometric.hasShownEnrollmentPrompt {
                // Defer slightly so the login screen dismiss animation completes.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    if auth.isSignedIn && !biometric.isEnabled {
                        showBiometricEnrollment = true
                    }
                }
            }
        } else {
            // Signed out — clear the unlock gate so a future sign-in starts fresh.
            biometric.markUnlocked()
        }
    }

    private var subscriptionLoadingView: some View {
        ZStack {
            VineyardTheme.appBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                Text("Checking subscription…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var vineyardLoadingView: some View {
        ZStack {
            VineyardTheme.appBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                Text(isLoadingVineyards ? "Loading vineyards…" : "Preparing…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadVineyardsAndApplyDefault() async {
        isLoadingVineyards = true
        defer { isLoadingVineyards = false }
        do {
            let backendVineyards = try await vineyardRepository.listMyVineyards()
            store.mapBackendVineyardsIntoLocal(backendVineyards)
            store.applyDefaultVineyardSelection(defaultId: auth.defaultVineyardId)
            // If profile pointed at a vineyard the user no longer belongs to, clear it remotely.
            if let defaultId = auth.defaultVineyardId,
               !store.vineyards.contains(where: { $0.id == defaultId }) {
                _ = await auth.setDefaultVineyard(nil)
            }
        } catch {
            // Network/listing failed — fall back to whatever local state exists.
            store.applyDefaultVineyardSelection(defaultId: auth.defaultVineyardId)
        }
        didApplyDefaultVineyard = true
    }

    private var loadingView: some View {
        LoadingSplashView()
    }

    private var disclaimerLoadingView: some View {
        ZStack {
            VineyardTheme.appBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                if isCheckingDisclaimer {
                    ProgressView()
                    Text("Checking disclaimer status…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let disclaimerError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                    Text("Couldn't verify disclaimer")
                        .font(.headline)
                    Text(disclaimerError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Retry") {
                        Task { await checkDisclaimer() }
                    }
                    .buttonStyle(.vineyardPrimary)
                    .padding(.horizontal, 40)
                }
            }
        }
    }

    private func checkDisclaimer() async {
        isCheckingDisclaimer = true
        disclaimerError = nil
        defer { isCheckingDisclaimer = false }
        do {
            let accepted = try await disclaimerRepository.hasAcceptedCurrentDisclaimer()
            disclaimerAccepted = accepted
            didCheckDisclaimer = true
        } catch {
            disclaimerError = error.localizedDescription
            didCheckDisclaimer = false
        }
    }
}
