import SwiftUI

/// Dismissible, swipable banner shown on the Home screen for currently
/// active, non-dismissed app-wide notices. Multiple notices are paged
/// horizontally so the banner only ever takes a single card's worth of
/// vertical space.
struct AppNoticesBanner: View {
    @Environment(AppNoticeService.self) private var service
    @State private var selection: UUID?

    var body: some View {
        let visible = service.visibleNotices
        if visible.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 6) {
                TabView(selection: $selection) {
                    ForEach(visible) { notice in
                        NoticeBannerCard(notice: notice) {
                            dismiss(notice.id, visible: visible)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, visible.count > 1 ? 18 : 0)
                        .tag(Optional(notice.id))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: visible.count > 1 ? .always : .never))
                .indexViewStyle(.page(backgroundDisplayMode: .never))
                .frame(height: visible.count > 1 ? 96 : 78)
                .animation(.easeInOut(duration: 0.18), value: visible.map(\.id))
            }
            .onAppear { ensureSelection(visible: visible) }
            .onChange(of: visible.map(\.id)) { _, _ in ensureSelection(visible: visible) }
        }
    }

    private func ensureSelection(visible: [BackendAppNotice]) {
        if let current = selection, visible.contains(where: { $0.id == current }) { return }
        selection = visible.first?.id
    }

    private func dismiss(_ id: UUID, visible: [BackendAppNotice]) {
        // Advance selection to the next visible notice before dismissing so
        // the pager doesn't snap awkwardly.
        if let idx = visible.firstIndex(where: { $0.id == id }) {
            let next = visible.indices.contains(idx + 1) ? visible[idx + 1].id : visible.first(where: { $0.id != id })?.id
            selection = next
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            service.dismiss(id)
        }
    }
}

private struct NoticeBannerCard: View {
    let notice: BackendAppNotice
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: iconName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(notice.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Color(.tertiarySystemFill), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notice")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 1)
        )
    }

    private var tint: Color {
        switch notice.typedNoticeType {
        case .info: return .blue
        case .warning: return .orange
        case .success: return .green
        case .critical: return .red
        }
    }

    private var iconName: String {
        switch notice.typedNoticeType {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.seal.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
}
