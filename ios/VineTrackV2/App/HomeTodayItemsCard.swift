import SwiftUI

/// Compact "Today" operations summary shown on the Home dashboard.
///
/// Lists today's operational items only:
///   - Planned/started trips on today's date
///   - Work tasks dated today
///   - Spray records logged today
///
/// Designed to be scannable. Use existing data — no new providers.
struct HomeTodayItemsCard: View {
    @Binding var selectedTab: Int
    @Environment(MigratedDataStore.self) private var store

    var body: some View {
        VineyardCard {
            VStack(spacing: 0) {
                row(
                    icon: "steeringwheel",
                    tint: .blue,
                    title: "Trips today",
                    count: tripsToday,
                    emptyText: "No trips today"
                ) {
                    selectedTab = 2
                }
                Divider().padding(.leading, 44)
                row(
                    icon: "person.2.badge.gearshape.fill",
                    tint: .indigo,
                    title: "Work tasks today",
                    count: workTasksToday,
                    emptyText: "No work tasks today",
                    destination: AnyView(WorkTasksHubView())
                )
                Divider().padding(.leading, 44)
                row(
                    icon: "sprinkler.and.droplets.fill",
                    tint: .purple,
                    title: "Sprays today",
                    count: spraysToday,
                    emptyText: "No spray records today"
                ) {
                    selectedTab = 3
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Derived counts

    private var todayStart: Date { Calendar.current.startOfDay(for: Date()) }
    private var todayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: todayStart) ?? Date()
    }

    private var tripsToday: Int {
        store.trips.filter { trip in
            trip.startTime >= todayStart && trip.startTime < todayEnd
        }.count
    }

    private var workTasksToday: Int {
        store.workTasks.filter { task in
            guard !task.isArchived else { return false }
            return Calendar.current.isDateInToday(task.date)
        }.count
    }

    private var spraysToday: Int {
        store.sprayRecords.filter { record in
            Calendar.current.isDateInToday(record.date)
        }.count
    }

    // MARK: - Row builders

    @ViewBuilder
    private func row(
        icon: String,
        tint: Color,
        title: String,
        count: Int,
        emptyText: String,
        destination: AnyView
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            rowContent(icon: icon, tint: tint, title: title, count: count, emptyText: emptyText)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func row(
        icon: String,
        tint: Color,
        title: String,
        count: Int,
        emptyText: String,
        tapAction: @escaping () -> Void
    ) -> some View {
        Button {
            tapAction()
        } label: {
            rowContent(icon: icon, tint: tint, title: title, count: count, emptyText: emptyText)
        }
        .buttonStyle(.plain)
    }

    private func rowContent(
        icon: String,
        tint: Color,
        title: String,
        count: Int,
        emptyText: String
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(count > 0 ? 0.18 : 0.10))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(count > 0 ? title : emptyText)
                    .font(.subheadline.weight(count > 0 ? .semibold : .regular))
                    .foregroundStyle(count > 0 ? .primary : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if count > 0 {
                Text("\(count)")
                    .font(.footnote.weight(.bold).monospacedDigit())
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.15), in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
