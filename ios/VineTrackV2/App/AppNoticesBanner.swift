import SwiftUI

/// Dismissible banner stack shown on the Home screen for any currently
/// active, non-dismissed app-wide notice. Falls back to nothing when
/// there are no visible notices, so it never reserves space when idle.
struct AppNoticesBanner: View {
    @Environment(AppNoticeService.self) private var service

    var body: some View {
        let visible = service.visibleNotices
        if visible.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 8) {
                ForEach(visible) { notice in
                    NoticeBannerCard(notice: notice) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            service.dismiss(notice.id)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct NoticeBannerCard: View {
    let notice: BackendAppNotice
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: iconName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(notice.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
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
