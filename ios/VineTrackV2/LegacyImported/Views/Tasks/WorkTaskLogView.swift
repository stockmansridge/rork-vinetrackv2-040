import SwiftUI

struct WorkTaskLogView: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(WorkTaskSyncService.self) private var workTaskSync
    @Environment(WorkTaskLabourLineSyncService.self) private var workTaskLabourLineSync
    @Environment(WorkTaskPaddockSyncService.self) private var workTaskPaddockSync
    @Environment(\.accessControl) private var accessControl

    enum SortOption: String, CaseIterable, Identifiable {
        case dateDesc = "Date (newest)"
        case dateAsc = "Date (oldest)"
        case task = "Task Type"
        case block = "Block"
        case costDesc = "Cost (high-low)"

        var id: String { rawValue }
    }

    @State private var searchText: String = ""
    @State private var sort: SortOption = .dateDesc
    @State private var taskFilter: String = ""
    @State private var blockFilter: String = ""
    @State private var selectedTask: WorkTask?
    @State private var showAdd: Bool = false

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var allTaskTypes: [String] {
        Array(Set(store.workTasks.map { $0.taskType }).union(WorkTaskTypeCatalog.defaults)).sorted()
    }

    private var allBlocks: [String] {
        Array(Set(store.workTasks.map { $0.paddockName }).filter { !$0.isEmpty }).sorted()
    }

    private var filtered: [WorkTask] {
        var items = store.workTasks.filter { !$0.isArchived }
        if !taskFilter.isEmpty {
            items = items.filter { $0.taskType == taskFilter }
        }
        if !blockFilter.isEmpty {
            items = items.filter { $0.paddockName == blockFilter }
        }
        if !searchText.isEmpty {
            items = items.filter {
                $0.taskType.localizedStandardContains(searchText) ||
                $0.paddockName.localizedStandardContains(searchText) ||
                $0.notes.localizedStandardContains(searchText)
            }
        }
        switch sort {
        case .dateDesc:
            items.sort { $0.date > $1.date }
        case .dateAsc:
            items.sort { $0.date < $1.date }
        case .task:
            items.sort { $0.taskType.localizedStandardCompare($1.taskType) == .orderedAscending }
        case .block:
            items.sort { $0.paddockName.localizedStandardCompare($1.paddockName) == .orderedAscending }
        case .costDesc:
            items.sort { $0.totalCost > $1.totalCost }
        }
        return items
    }

    private var totalCost: Double { filtered.reduce(0) { $0 + $1.totalCost } }
    private var totalHours: Double { filtered.reduce(0) { $0 + $1.durationHours } }
    private var totalPeople: Int { filtered.reduce(0) { $0 + $1.totalPeople } }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                summaryCard
                filterBar
                listSection
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Task Log")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search tasks...")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddEditWorkTaskView()
        }
        .sheet(item: $selectedTask) { task in
            AddEditWorkTaskView(existingTask: task)
        }
        .refreshable {
            await workTaskSync.syncForSelectedVineyard()
            await workTaskLabourLineSync.syncForSelectedVineyard()
            await workTaskPaddockSync.syncForSelectedVineyard()
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Filtered Totals")
                        .font(.title3.weight(.bold))
                    Text("\(filtered.count) task\(filtered.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if accessControl?.canViewFinancials ?? false {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Cost")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(totalCost, format: .currency(code: currencyCode))
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(VineyardTheme.leafGreen)
                    }
                }
            }
            .padding(.bottom, 16)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                metric(value: String(format: "%.1f", totalHours), label: "Hours", icon: "clock.fill", color: .orange)
                metric(value: "\(totalPeople)", label: "Worker-Entries", icon: "person.2.fill", color: .blue)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private func metric(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sort & Filter")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !taskFilter.isEmpty || !blockFilter.isEmpty {
                    Button("Clear") {
                        taskFilter = ""
                        blockFilter = ""
                    }
                    .font(.caption)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(SortOption.allCases) { opt in
                            Button {
                                sort = opt
                            } label: {
                                if sort == opt {
                                    Label(opt.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(opt.rawValue)
                                }
                            }
                        }
                    } label: {
                        chipLabel(icon: "arrow.up.arrow.down", text: sort.rawValue, active: true)
                    }

                    Menu {
                        Button("All Tasks") { taskFilter = "" }
                        Divider()
                        ForEach(allTaskTypes, id: \.self) { t in
                            Button(t) { taskFilter = t }
                        }
                    } label: {
                        chipLabel(icon: "checklist", text: taskFilter.isEmpty ? "Task" : taskFilter, active: !taskFilter.isEmpty)
                    }

                    Menu {
                        Button("All Blocks") { blockFilter = "" }
                        Divider()
                        ForEach(allBlocks, id: \.self) { b in
                            Button(b) { blockFilter = b }
                        }
                    } label: {
                        chipLabel(icon: "square.grid.2x2", text: blockFilter.isEmpty ? "Block" : blockFilter, active: !blockFilter.isEmpty)
                    }
                }
            }
            .contentMargins(.horizontal, 0)
        }
    }

    private func chipLabel(icon: String, text: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            active ? Color.accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground),
            in: Capsule()
        )
        .foregroundStyle(active ? Color.accentColor : .primary)
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No tasks found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            } else {
                ForEach(filtered) { task in
                    Button {
                        selectedTask = task
                    } label: {
                        WorkTaskLogRow(task: task)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct WorkTaskLogRow: View {
    let task: WorkTask
    @Environment(\.accessControl) private var accessControl

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack {
                Image(systemName: "person.2.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .background(VineyardTheme.olive.gradient, in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(task.taskType.isEmpty ? "Task" : task.taskType)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !task.paddockName.isEmpty {
                    Text(task.paddockName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Label(String(format: "%.1fh", task.durationHours), systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Label("\(task.totalPeople)", systemImage: "person.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if task.costPerPerson > 0 && (accessControl?.canViewFinancials ?? false) {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("\(task.costPerPerson, format: .currency(code: currencyCode))/pp")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if accessControl?.canViewFinancials ?? false {
                    Text(task.totalCost, format: .currency(code: currencyCode))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(VineyardTheme.leafGreen)
                }
                Text(task.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }
}
