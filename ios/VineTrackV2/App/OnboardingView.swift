import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var page: Int = 0

    private struct Page: Identifiable {
        let id = UUID()
        let icon: String
        let iconColor: Color
        let title: String
        let message: String
    }

    private let pages: [Page] = [
        Page(
            icon: "leaf.fill",
            iconColor: VineyardTheme.leafGreen,
            title: "Welcome to VineTrackV2",
            message: "A practical companion for managing your vineyard — pins, trips, sprays, work tasks, and growth observations in one place."
        ),
        Page(
            icon: "mappin.and.ellipse",
            iconColor: .blue,
            title: "Track What Matters",
            message: "Drop pins for repairs and observations, log spray records and trips, and capture work and growth stage data on the go."
        ),
        Page(
            icon: "person.2.fill",
            iconColor: .purple,
            title: "Local-First, Team Synced",
            message: "Your data is stored on this device and synced securely with your vineyard team through Supabase."
        ),
        Page(
            icon: "building.2.fill",
            iconColor: VineyardTheme.earthBrown,
            title: "Choose or Create a Vineyard",
            message: "Vineyard membership controls who can see and edit data. You can create a new vineyard or accept a team invitation next."
        )
    ]

    var body: some View {
        ZStack {
            VineyardTheme.appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, p in
                        pageView(p).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                VStack(spacing: 12) {
                    Button {
                        if page < pages.count - 1 {
                            withAnimation { page += 1 }
                        } else {
                            onComplete()
                        }
                    } label: {
                        Text(page < pages.count - 1 ? "Continue" : "Get Started")
                    }
                    .buttonStyle(.vineyardPrimary)

                    if page < pages.count - 1 {
                        Button("Skip") {
                            onComplete()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private func pageView(_ p: Page) -> some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(p.iconColor.opacity(0.15))
                    .frame(width: 140, height: 140)
                Image(systemName: p.icon)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(p.iconColor)
            }
            Text(p.title)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            Text(p.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }
}

enum OnboardingState {
    private static let key = "vinetrack_onboarding_completed_v1"

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: key)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
