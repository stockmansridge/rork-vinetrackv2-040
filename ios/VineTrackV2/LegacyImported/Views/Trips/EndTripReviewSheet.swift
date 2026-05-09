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
    /// Optional free-text completion notes typed by the operator.
    /// Persisted onto the trip and synced as `trips.completion_notes`.
    @State private var completionNotes: String = ""
    @FocusState private var notesFocused: Bool

    private struct DisplayRow: Identifiable {
        let id: Int
        let result: RowCompletionResult
        let manuallyTicked: Bool
        var path: Double { result.path }
        var status: RowCompletionStatus {
            manuallyTicked ? .complete : result.status
        }
    }

    private var liveTrip: Trip { tracking.activeTrip ?? trip }

    private var rows: [DisplayRow] {
        let live = liveTrip
        // Promote the live current row to .partial so the sheet still hints
        // at it; the rest of the derivation comes straight from the shared
        // deriver so this view shows exactly what the report will show.
        let currentPath: Double? = live.rowSequence.indices.contains(live.sequenceIndex)
            ? live.rowSequence[live.sequenceIndex]
            : nil
        let derived = RowCompletionDeriver.results(for: live)
        return derived.enumerated().map { idx, r in
            var result = r
            if result.status == .notComplete,
               let cp = currentPath,
               abs(cp - r.path) < 0.01 {
                result = RowCompletionResult(path: r.path, status: .partial, source: .auto)
            }
            let ticked = manualCompletes.contains(r.path)
            return DisplayRow(id: idx, result: result, manuallyTicked: ticked)
        }
    }

    private var completedCount: Int { rows.filter { $0.status == .complete }.count }
    private var partialCount: Int { rows.filter { $0.status == .partial }.count }
    private var missedCount: Int { rows.filter { $0.status == .notComplete }.count }

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
                        statCell(value: "\(missedCount)", label: "Not done", tint: .red)
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
                                let live = liveTrip
                                let completed = Set(live.completedPaths)
                                let skipped = Set(live.skippedPaths)
                                for r in rows where r.status == .notComplete {
                                    if !completed.contains(r.path) && !skipped.contains(r.path) {
                                        manualCompletes.insert(r.path)
                                    }
                                }
                            } label: {
                                Label("Tick all \(missedCount) not-done rows as complete", systemImage: "checkmark.circle.fill")
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Completion notes")
                            .font(.subheadline.weight(.semibold))
                        TextField(
                            "e.g. Finished block but last row was wet.",
                            text: $completionNotes,
                            axis: .vertical
                        )
                        .lineLimit(2...5)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                        .focused($notesFocused)
                    }
                    .padding(.vertical, 2)
                } footer: {
                    Text("Optional notes for this completed job. These will appear in reports.")
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
                // Pre-fill any existing notes (e.g. when reopening the
                // sheet after dismissing without finishing).
                if completionNotes.isEmpty,
                   let existing = tracking.activeTrip?.completionNotes,
                   !existing.isEmpty {
                    completionNotes = existing
                }
            }
            .scrollDismissesKeyboard(.interactively)
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
    private func rowItem(_ row: DisplayRow) -> some View {
        let isManualCompleted = row.manuallyTicked
        let live = liveTrip
        let alreadyCompleted = live.completedPaths.contains(where: { abs($0 - row.path) < 0.01 })
        let alreadySkipped = live.skippedPaths.contains(where: { abs($0 - row.path) < 0.01 })
        let displayStatus = row.status

        HStack(spacing: 12) {
            Image(systemName: displayStatus.iconName)
                .font(.title2)
                .foregroundStyle(tint(for: displayStatus))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Path \(row.result.formattedPath)")
                    .font(.headline)
                Text(detailLabel(for: row, manuallyCompleted: isManualCompleted))
                    .font(.caption)
                    .foregroundStyle(displayStatus == .notComplete && !isManualCompleted ? .red : .secondary)
                    .fontWeight(displayStatus == .notComplete && !isManualCompleted ? .semibold : .regular)
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
            displayStatus == .notComplete && !isManualCompleted
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

    private func tint(for status: RowCompletionStatus) -> Color {
        switch status {
        case .complete: return .green
        case .partial: return .orange
        case .notComplete: return .red
        }
    }

    private func detailLabel(for row: DisplayRow, manuallyCompleted: Bool) -> String {
        if manuallyCompleted { return "Will be ticked Complete — End review" }
        switch row.status {
        case .complete:
            if let source = row.result.source { return "Complete — \(source.label)" }
            return "Complete"
        case .partial:
            return "Partial — Auto"
        case .notComplete:
            return "Not complete — not detected by GPS"
        }
    }

    private func applyAndFinish() {
        // Persist any manual ticks AND the optional completion notes
        // onto the live trip in a single update so the saved record
        // (and the synced row) reflects everything in one shot.
        let trimmedNotes = completionNotes
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if var live = tracking.activeTrip {
            var changed = false
            if !manualCompletes.isEmpty {
                for path in manualCompletes {
                    if !live.completedPaths.contains(path) && !live.skippedPaths.contains(path) {
                        live.completedPaths.append(path)
                        changed = true
                    }
                }
            }
            if (live.completionNotes ?? "") != trimmedNotes {
                live.completionNotes = trimmedNotes.isEmpty ? nil : trimmedNotes
                changed = true
            }
            if changed {
                store.updateTrip(live)
            }
            if !manualCompletes.isEmpty {
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
