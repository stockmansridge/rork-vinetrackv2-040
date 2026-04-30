import SwiftUI

/// Restored Maintenance Start Trip sheet styled to match the original app:
/// hero header, block selector card, tracking pattern grid, starting row /
/// direction options, operator field, and a prominent Start button.
///
/// Backend-neutral: uses `MigratedDataStore` and `TripTrackingService` only.
struct StartTripSheet: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(TripTrackingService.self) private var tracking
    @Environment(NewBackendAuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPaddockId: UUID?
    @State private var trackingPattern: TrackingPattern = .sequential
    @State private var startingRow: Int = 1
    @State private var reversedDirection: Bool = false
    @State private var personName: String = ""
    @State private var showPaddockPicker: Bool = false

    private var selectedPaddock: Paddock? {
        guard let id = selectedPaddockId else { return nil }
        return store.paddocks.first(where: { $0.id == id })
    }

    private var totalRows: Int {
        selectedPaddock?.rows.count ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    heroHeader
                    blockSection
                    if selectedPaddock != nil {
                        directionSection
                    }
                    patternSection
                    operatorSection
                    if let error = tracking.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                    startButton
                        .padding(.top, 4)
                    Spacer(minLength: 24)
                }
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Start Maintenance Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if personName.isEmpty, let name = auth.userName {
                    personName = name
                }
                if selectedPaddockId == nil {
                    selectedPaddockId = store.paddocks.first?.id
                }
            }
            .sheet(isPresented: $showPaddockPicker) {
                PaddockPickerSheet(selectedId: $selectedPaddockId)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Hero

    private var heroHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(VineyardTheme.earthBrown.opacity(0.15))
                    .frame(width: 76, height: 76)
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(VineyardTheme.earthBrown)
            }
            VStack(spacing: 4) {
                Text("Maintenance Trip")
                    .font(.title2.bold())
                Text("Track a general vineyard trip with row guidance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal)
    }

    // MARK: Block

    private var blockSection: some View {
        sectionContainer(title: "Block", icon: "square.grid.2x2.fill", tint: VineyardTheme.leafGreen) {
            Button {
                showPaddockPicker = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(VineyardTheme.leafGreen.opacity(0.15))
                            .frame(width: 44, height: 44)
                        GrapeLeafIcon(size: 22, color: VineyardTheme.leafGreen)
                    }
                    if let paddock = selectedPaddock {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(paddock.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            blockMetaLine(for: paddock)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("No block selected")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Tap to choose a block (optional)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            if let paddock = selectedPaddock, !paddock.rows.isEmpty {
                blockStatsRow(for: paddock)
            }
        }
    }

    private func blockMetaLine(for paddock: Paddock) -> some View {
        let variety = paddock.varietyAllocations.first.map { _ in
            paddock.varietyAllocations.compactMap { allocationName($0) }.joined(separator: ", ")
        } ?? ""
        return HStack(spacing: 6) {
            if !variety.isEmpty {
                Text(variety)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if paddock.rows.isEmpty {
                Text("No rows mapped yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(paddock.rows.count) rows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func allocationName(_ allocation: PaddockVarietyAllocation) -> String? {
        let name = store.grapeVarieties.first(where: { $0.id == allocation.varietyId })?.name
        return (name?.isEmpty == false) ? name : nil
    }

    private func blockStatsRow(for paddock: Paddock) -> some View {
        HStack(spacing: 0) {
            statCell(value: "\(paddock.rows.count)", label: "Rows")
            Divider().frame(height: 32)
            statCell(value: String(format: "%.2f", paddock.areaHectares), label: "Hectares")
            Divider().frame(height: 32)
            statCell(value: "\(paddock.effectiveVineCount)", label: "Vines")
        }
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Direction & starting row

    private var directionSection: some View {
        sectionContainer(title: "Starting Row & Direction", icon: "arrow.up.arrow.down", tint: .blue) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Text("Start Row")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Stepper(value: $startingRow, in: 1...max(totalRows, 1)) {
                        Text("\(startingRow)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    .labelsHidden()
                    Text("\(startingRow) of \(max(totalRows, 1))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 12))

                Toggle(isOn: $reversedDirection) {
                    HStack(spacing: 8) {
                        Image(systemName: reversedDirection ? "arrow.left" : "arrow.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reverse direction")
                                .font(.subheadline.weight(.semibold))
                            Text(reversedDirection ? "Run sequence in reverse" : "Run sequence forwards")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 12))
            }
        }
    }

    // MARK: Pattern

    private var patternSection: some View {
        sectionContainer(title: "Tracking Pattern", icon: "arrow.triangle.swap", tint: .purple) {
            VStack(spacing: 10) {
                ForEach(TrackingPattern.allCases) { pattern in
                    patternRow(pattern: pattern)
                }
            }
        }
    }

    private func patternRow(pattern: TrackingPattern) -> some View {
        let isSelected = trackingPattern == pattern
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                trackingPattern = pattern
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill((isSelected ? Color.purple : Color.secondary).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: pattern.icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isSelected ? .purple : .secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(pattern.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(pattern.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.purple : Color.secondary.opacity(0.5))
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.purple.opacity(0.5) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Operator

    private var operatorSection: some View {
        sectionContainer(title: "Operator", icon: "person.fill", tint: .orange) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: 32)
                TextField("Name (optional)", text: $personName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    // MARK: Start button

    private var startButton: some View {
        Button {
            handleStart()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.headline)
                Text("Start Trip")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.blue, in: .rect(cornerRadius: 14))
            .foregroundStyle(.white)
            .shadow(color: Color.blue.opacity(0.25), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    // MARK: Helpers

    @ViewBuilder
    private func sectionContainer<Content: View>(
        title: String,
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            content()
        }
        .padding(.horizontal)
    }

    private func handleStart() {
        let paddockName: String = selectedPaddock?.name ?? ""

        tracking.startTrip(
            type: .maintenance,
            paddockId: selectedPaddockId,
            paddockName: paddockName,
            trackingPattern: trackingPattern,
            personName: personName
        )

        if let paddock = selectedPaddock,
           !paddock.rows.isEmpty,
           var trip = tracking.activeTrip {
            let sequence = trackingPattern.generateSequence(
                startRow: max(1, min(startingRow, paddock.rows.count)),
                totalRows: paddock.rows.count,
                reversed: reversedDirection
            )
            if let first = sequence.first {
                trip.rowSequence = sequence
                trip.sequenceIndex = 0
                trip.currentRowNumber = first
                trip.nextRowNumber = sequence.dropFirst().first ?? first
                store.updateTrip(trip)
            }
        }

        if tracking.errorMessage == nil {
            dismiss()
        }
    }
}

// MARK: - Paddock Picker Sheet

private struct PaddockPickerSheet: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedId: UUID?
    @State private var searchText: String = ""

    private var filtered: [Paddock] {
        let all = store.paddocks.sorted { $0.name.lowercased() < $1.name.lowercased() }
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.paddocks.isEmpty {
                    ContentUnavailableView {
                        Label("No Blocks", systemImage: "square.grid.2x2")
                    } description: {
                        Text("Create blocks first to assign trips to a specific block.")
                    }
                } else {
                    List {
                        Section {
                            Button {
                                selectedId = nil
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(.secondary)
                                    Text("No block (general trip)")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedId == nil {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }

                        Section {
                            ForEach(filtered) { paddock in
                                Button {
                                    selectedId = paddock.id
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        GrapeLeafIcon(size: 20, color: VineyardTheme.leafGreen)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(paddock.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Text("\(paddock.rows.count) rows · \(String(format: "%.2f", paddock.areaHectares)) ha")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if selectedId == paddock.id {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $searchText, prompt: "Search blocks")
                }
            }
            .navigationTitle("Select Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Active Trip Card (unchanged)

struct ActiveTripCard: View {
    @Environment(TripTrackingService.self) private var tracking
    @Environment(LocationService.self) private var locationService

    var body: some View {
        if let trip = tracking.activeTrip {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(tracking.isPaused ? Color.orange : VineyardTheme.leafGreen)
                        .frame(width: 10, height: 10)
                    Text(tracking.isPaused ? "Trip Paused" : "Trip Active")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if locationService.location == nil {
                        Label("No GPS", systemImage: "location.slash")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 16) {
                    stat("Time", value: formatDuration(tracking.elapsedTime))
                    stat("Distance", value: formatDistance(tracking.currentDistance))
                    stat("Points", value: "\(trip.pathPoints.count)")
                }

                guidanceSection(trip: trip)

                HStack(spacing: 8) {
                    if tracking.isPaused {
                        Button {
                            tracking.resumeTrip()
                        } label: {
                            Label("Resume", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(VineyardTheme.leafGreen)
                    } else {
                        Button {
                            tracking.pauseTrip()
                        } label: {
                            Label("Pause", systemImage: "pause.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    Button(role: .destructive) {
                        tracking.endTrip()
                    } label: {
                        Label("End", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private func guidanceSection(trip: Trip) -> some View {
        let paddockName: String? = tracking.currentPaddockName ?? (trip.paddockName.isEmpty ? nil : trip.paddockName)
        VStack(alignment: .leading, spacing: 4) {
            if let paddockName {
                Label { Text(paddockName) } icon: { GrapeLeafIcon(size: 12) }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if tracking.rowGuidanceAvailable, let row = tracking.currentRowNumber {
                HStack(spacing: 12) {
                    Label("Row " + formatRow(row), systemImage: "arrow.left.and.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VineyardTheme.leafGreen)
                    if let dist = tracking.currentRowDistance {
                        Text("±\(Int(dist))m")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if tracking.rowsCoveredCount > 0 {
                        Text("\(tracking.rowsCoveredCount) covered")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if paddockName != nil {
                Text("Row guidance unavailable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatRow(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters))m" }
        return String(format: "%.2fkm", meters / 1000)
    }
}
