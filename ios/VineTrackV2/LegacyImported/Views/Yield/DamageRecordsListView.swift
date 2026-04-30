import SwiftUI
import MapKit

struct DamageRecordsListView: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(\.accessControl) private var accessControl

    private var canDelete: Bool { accessControl?.canDelete ?? false }

    private var paddocks: [Paddock] {
        store.orderedPaddocks.filter { $0.polygonPoints.count >= 3 }
    }

    private var allDamageRecords: [DamageRecord] {
        store.damageRecords.sorted { $0.date > $1.date }
    }

    private let blockColors: [Color] = [
        .blue, .green, .orange, .purple, .red, .cyan, .mint, .indigo, .pink, .teal, .yellow, .brown
    ]

    private func colorFor(_ paddock: Paddock) -> Color {
        guard let idx = paddocks.firstIndex(where: { $0.id == paddock.id }) else { return .blue }
        return blockColors[idx % blockColors.count]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if allDamageRecords.isEmpty {
                    emptyState
                } else {
                    summarySection
                    blockDamageSection
                    allRecordsSection
                }

                addDamageSection
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("Record Damage")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Damage Recorded")
                .font(.title3.weight(.semibold))
            Text("Select a block below to record damage from frost, hail, wind, or other events.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                overviewCard(
                    title: "Total Records",
                    value: "\(allDamageRecords.count)",
                    icon: "exclamationmark.triangle.fill",
                    color: .orange
                )
                overviewCard(
                    title: "Blocks Affected",
                    value: "\(Set(allDamageRecords.map(\.paddockId)).count)",
                    icon: "map.fill",
                    color: .red
                )
            }
        }
    }

    private func overviewCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }

    // MARK: - Block Damage Summary

    private var affectedPaddocks: [Paddock] {
        paddocks.filter { !store.damageRecords(for: $0.id).isEmpty }
    }

    private var blockDamageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Block Viability", systemImage: "chart.bar.xaxis")
                .font(.headline)

            ForEach(affectedPaddocks) { paddock in
                let records = store.damageRecords(for: paddock.id)
                let factor = store.damageFactor(for: paddock.id)
                let color = colorFor(paddock)

                HStack(spacing: 12) {
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(paddock.name)
                            .font(.subheadline.weight(.semibold))
                        Text("\(records.count) damage record\(records.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.0f%%", factor * 100))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(factor >= 0.8 ? .green : factor >= 0.5 ? .orange : .red)
                        Text("viable")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
            }
        }
    }

    // MARK: - All Records

    private var allRecordsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("All Damage Records", systemImage: "list.bullet.clipboard")
                .font(.headline)

            ForEach(allDamageRecords) { record in
                damageRecordCard(record)
            }
        }
    }

    private func damageRecordCard(_ record: DamageRecord) -> some View {
        let paddock = paddocks.first { $0.id == record.paddockId }
        let paddockName = paddock?.name ?? "Unknown Block"
        let color = paddock.map { colorFor($0) } ?? .gray

        return NavigationLink {
            if let paddock {
                RecordDamageView(paddock: paddock, editingRecord: record)
            }
        } label: {
            damageRecordCardContent(record, paddockName: paddockName, color: color)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let paddock {
                NavigationLink {
                    RecordDamageView(paddock: paddock, editingRecord: record)
                } label: {
                    Label("Edit Record", systemImage: "pencil")
                }
            }
            if canDelete {
                Button(role: .destructive) {
                    store.deleteDamageRecord(record)
                } label: {
                    Label("Delete Record", systemImage: "trash")
                }
            }
        }
    }

    private func damageRecordCardContent(_ record: DamageRecord, paddockName: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: record.damageType.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(record.damageType.rawValue)
                        .font(.subheadline.weight(.semibold))
                }

                Spacer()

                Text(String(format: "%.0f%%", record.damagePercent))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.red)
            }

            Divider()

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                    Text(paddockName)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(record.date, format: .dateTime.day().month().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(String(format: "%.4f Ha", record.areaHectares))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }

            if !record.notes.isEmpty {
                Text(record.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(10)
        }
    }

    // MARK: - Add Damage

    private var addDamageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Record New Damage", systemImage: "plus.circle.fill")
                .font(.headline)

            if paddocks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No blocks with boundaries found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(paddocks) { paddock in
                        let color = colorFor(paddock)
                        let existingCount = store.damageRecords(for: paddock.id).count

                        NavigationLink {
                            RecordDamageView(paddock: paddock)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(color)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(paddock.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if existingCount > 0 {
                                        Text("\(existingCount) existing")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    } else {
                                        Text(String(format: "%.2f Ha", paddock.areaHectares))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.tertiarySystemFill))
                            )
                        }
                    }
                }
            }
        }
    }
}
