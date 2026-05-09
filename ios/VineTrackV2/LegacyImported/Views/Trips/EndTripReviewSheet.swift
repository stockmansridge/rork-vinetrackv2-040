import SwiftUI

/// Pre-finalisation review of planned vs covered paths. The operator can
/// tick off any rows the app missed (e.g. a short final row that didn't
/// register) before the trip is saved. Manual completions and skips are
/// recorded as audit events on the tracking service.
struct EndTripReviewSheet: View {
    let trip: Trip
    @Environment(MigratedDataStore.self) private var store
    @Environment(TripTrackingService.self) private var tracking
    @Environment(\.dismiss) private var dismiss

    @State private var manualCompletes: Set<Double> = []
    @State private var manualSkips: Set<Double> = []

    private enum Status {
        case complete
        case partial
        case missed
    }

    private struct Row: Identifiable {
        let id: Int
        let path: Double
        let status: Status
    }

    private var rows: [Row] {
        let live = tracking.activeTrip ?? trip
        let completed = Set(live.completedPaths)
        let skipped = Set(live.skippedPaths)
        let currentPath: Double? = live.rowSequence.indices.contains(live.sequenceIndex)
            ? live.rowSequence[live.sequenceIndex]
            : nil
        return live.rowSequence.enumerated().map { idx, path in
            let isCompleted = completed.contains(path) || manualCompletes.contains(path)
            let isSkipped = skipped.contains(path) || manualSkips.contains(path)
            let status: Status
            if isCompleted {
                status = .complete
            } else if isSkipped {
                status = .partial
            } else if let cp = currentPath, abs(cp - path) < 0.01 {
                status = .partial
            } else {
                status = .missed
            }
            return Row(id: idx, path: path, status: status)
        }
    }

    private var completedCount: Int { rows.filter { $0.status == .complete }.count }
    private var partialCount: Int { rows.filter { $0.status == .partial }.count }
    private var missedCount: Int { rows.filter { $0.status == .missed }.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Review rows before saving")
                            .font(.headline)
                        Text("Tick any rows you completed in the field that GPS did not detect. Manual changes will be included in the trip report.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    HStack(spacing: 0) {
                        statCell(value: "\(rows.count)", label: "Planned", tint: .primary)
                        Divider().frame(height: 36)
                        statCell(value: "\(completedCount)", label: "Complete", tint: .green)
                        Divider().frame(height: 36)
                        statCell(value: "\(partialCount)", label: "Partial", tint: .orange)
                        Divider().frame(height: 36)
                        statCell(value: "\(missedCount)", label: "Missed", tint: .red)
                    }
                    .padding(.vertical, 4)
                }

                if rows.isEmpty {
                    Section {
                        Text("No planned rows on this trip.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if missedCount > 0 {
                        Section {
                            Button {
                                let liveTrip = tracking.activeTrip ?? trip
                                let completed = Set(liveTrip.completedPaths)
                                let skipped = Set(liveTrip.skippedPaths)
                                for r in rows where r.status == .missed {
                                    if !completed.contains(r.path) && !skipped.contains(r.path) {
                                        manualCompletes.insert(r.path)
                                    }
                                }
                            } label: {
                                Label("Tick all \(missedCount) missed rows as complete", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                        } footer: {
                            Text("Use this if GPS missed rows you actually drove. The trip won't be marked failed — your manual ticks are saved in the report.")
                        }
                    }

                    Section("Planned rows") {
                        ForEach(rows) { row in
                            rowItem(row)
                        }
                    }
                }

                Section {
                    Text("Manual completions are recorded in the trip's audit log so the report shows exactly what was driven vs. ticked off after the fact.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Review & Finish Trip")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Final completion pass: credits the current/last
                // locked row if it was clearly driven but never
                // produced a normal row-end transition (typical for
                // first row started mid-way and last row with no
                // following row to trigger advance).
                tracking.finalizePendingRowsForReview()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish Trip") {
                        applyAndFinish()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func rowItem(_ row: Row) -> some View {
        let isManualCompleted = manualCompletes.contains(row.path)
        let liveTrip = tracking.activeTrip ?? trip
        let alreadyCompleted = liveTrip.completedPaths.contains(row.path)
        let alreadySkipped = liveTrip.skippedPaths.contains(row.path)

        HStack(spacing: 12) {
            Image(systemName: iconName(for: row.status))
                .font(.title2)
                .foregroundStyle(tint(for: row.status))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Path \(formatPath(row.path))")
                    .font(.headline)
                Text(label(for: row.status, manuallyCompleted: isManualCompleted))
                    .font(.caption)
                    .foregroundStyle(row.status == .missed && !isManualCompleted ? .red : .secondary)
                    .fontWeight(row.status == .missed && !isManualCompleted ? .semibold : .regular)
            }

            Spacer()

            if !alreadyCompleted && !alreadySkipped {
                Toggle("", isOn: Binding(
                    get: { manualCompletes.contains(row.path) },
                    set: { newValue in
                        if newValue {
                            manualCompletes.insert(row.path)
                        } else {
                            manualCompletes.remove(row.path)
                        }
                    }
                ))
                .labelsHidden()
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(
            row.status == .missed && !isManualCompleted
                ? Color.red.opacity(0.06)
                : Color(.secondarySystemGroupedBackground)
        )
    }

    private func statCell(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func iconName(for status: Status) -> String {
        switch status {
        case .complete: return "checkmark.circle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .missed: return "exclamationmark.circle"
        }
    }

    private func tint(for status: Status) -> Color {
        switch status {
        case .complete: return .green
        case .partial: return .orange
        case .missed: return .red
        }
    }

    private func label(for status: Status, manuallyCompleted: Bool) -> String {
        if manuallyCompleted { return "Will be ticked complete on save" }
        switch status {
        case .complete: return "Complete"
        case .partial: return "Partial / current row"
        case .missed: return "Missed — not detected by GPS"
        }
    }

    private func formatPath(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func applyAndFinish() {
        if !manualCompletes.isEmpty {
            if var live = tracking.activeTrip {
                for path in manualCompletes {
                    if !live.completedPaths.contains(path) && !live.skippedPaths.contains(path) {
                        live.completedPaths.append(path)
                    }
                }
                store.updateTrip(live)
                let summary = manualCompletes
                    .sorted()
                    .map { String(format: "%g", $0) }
                    .joined(separator: ",")
                tracking.recordManualCorrection("end_review_completed: [\(summary)]")
            }
        }
        tracking.recordManualCorrection("end_review_finalised")
        tracking.endTrip()
        dismiss()
    }
}
