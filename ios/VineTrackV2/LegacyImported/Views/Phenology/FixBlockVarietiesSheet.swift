import SwiftUI

/// Focused correction sheet opened from the Optimal Ripeness setup
/// checklist when one or more blocks have a missing or unrecognised
/// variety. Lists the problem blocks first and lets the user pick a
/// recognised variety inline — writes straight back to the paddock
/// via `MigratedDataStore.updatePaddock`, so changes are reflected in
/// Block Settings and the checklist immediately.
struct FixBlockVarietiesSheet: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let id: UUID
        let paddock: Paddock
        let resolution: RipenessVarietyResolution
    }

    private var allRows: [Row] {
        store.orderedPaddocks.map { p in
            Row(id: p.id, paddock: p, resolution: RipenessVarietyResolver.resolve(p, store: store))
        }
    }

    private var problemRows: [Row] {
        allRows.filter { !$0.resolution.isReady }
    }

    private var resolvedRows: [Row] {
        allRows.filter { $0.resolution.isReady }
    }

    private var managedVarieties: [GrapeVariety] {
        let vineyardId = store.selectedVineyardId
        var seen = Set<String>()
        return store.grapeVarieties
            .filter { v in
                if let vid = vineyardId, v.vineyardId != vid { return false }
                let key = RipenessVarietyResolver.canonicalName(v.name)
                if seen.contains(key) { return false }
                seen.insert(key)
                return true
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            if !problemRows.isEmpty {
                Section {
                    ForEach(problemRows) { row in
                        rowView(row)
                    }
                } header: {
                    Text("Needs Attention")
                } footer: {
                    Text("Pick the matching variety from your managed list. Saves immediately to the block's settings.")
                        .font(.caption)
                }
            } else {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(VineyardTheme.leafGreen)
                        Text("All blocks have a recognised variety.")
                            .font(.subheadline)
                    }
                }
            }

            if !resolvedRows.isEmpty {
                Section("Already Configured") {
                    ForEach(resolvedRows) { row in
                        rowView(row)
                    }
                }
            }
        }
        .navigationTitle("Fix Block Varieties")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.paddock.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                statusBadge(row.resolution)
            }
            Text(currentSummary(row))
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu {
                ForEach(managedVarieties) { variety in
                    Button {
                        applyVariety(variety, to: row.paddock)
                    } label: {
                        HStack {
                            Text(variety.name)
                            if variety.optimalGDD > 0 {
                                Text("\u{2022} \(Int(variety.optimalGDD)) GDD")
                            } else {
                                Text("\u{2022} no target")
                            }
                        }
                    }
                }
                if managedVarieties.isEmpty {
                    Text("No varieties available — add some under Grape Varieties.")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(row.resolution.isReady ? "Change Variety" : "Choose Variety")
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption.weight(.semibold))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusBadge(_ resolution: RipenessVarietyResolution) -> some View {
        switch resolution.status {
        case .ready:
            Label("Ready", systemImage: "checkmark.seal.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(VineyardTheme.leafGreen)
        case .missingTarget:
            Label("No GDD target", systemImage: "exclamationmark.circle")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        case .unrecognised:
            Label("Unrecognised", systemImage: "questionmark.circle")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        case .missing:
            Label("No variety", systemImage: "exclamationmark.circle")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }

    private func currentSummary(_ row: Row) -> String {
        switch row.resolution.status {
        case .ready(let v):
            return "Current: \(v.name) \u{2022} \(Int(v.optimalGDD)) GDD"
        case .missingTarget(let v):
            return "Current: \(v.name) \u{2022} no GDD target set"
        case .unrecognised:
            return "Variety is not in the ripeness variety list."
        case .missing:
            return "No variety assigned to this block."
        }
    }

    private func applyVariety(_ variety: GrapeVariety, to paddock: Paddock) {
        var updated = paddock
        if let idx = updated.varietyAllocations.firstIndex(where: { $0.id == paddock.varietyAllocations.max(by: { $0.percent < $1.percent })?.id }) {
            // Replace the primary allocation's varietyId, preserve percent.
            updated.varietyAllocations[idx] = PaddockVarietyAllocation(
                id: updated.varietyAllocations[idx].id,
                varietyId: variety.id,
                percent: updated.varietyAllocations[idx].percent
            )
        } else {
            updated.varietyAllocations = [
                PaddockVarietyAllocation(varietyId: variety.id, percent: 100)
            ]
        }
        store.updatePaddock(updated)
    }
}
