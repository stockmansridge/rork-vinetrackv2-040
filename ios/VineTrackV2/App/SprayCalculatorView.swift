import SwiftUI
import CoreLocation

enum GrowthStageMode: String, CaseIterable {
    case same
    case perPaddock
}

/// Backend-safe Spray Calculator.
///
/// Restores the original spray-job setup workflow visually and functionally:
/// paddock selection, operation type, growth stage, equipment, water rate
/// (canopy size + density + row spacing), chemicals (rate per ha or per 100L),
/// optional manual weather, notes, calculation results and (when permitted)
/// costing summary.
///
/// Wired only to MigratedDataStore + TripTrackingService + BackendAccessControl.
/// No DataStore, AuthService, CloudSyncService, SupabaseManager or
/// WeatherDataService imports.
struct SprayCalculatorView: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(TripTrackingService.self) private var tracking
    @Environment(NewBackendAuthService.self) private var auth
    @Environment(BackendAccessControl.self) private var accessControl
    @Environment(LocationService.self) private var locationService
    @Environment(\.dismiss) private var dismiss

    // Selection
    @State private var sprayName: String = ""
    @State private var operationType: OperationType = .foliarSpray
    @State private var selectedPaddockIds: Set<UUID> = []
    @State private var selectedEquipmentId: UUID?
    @State private var selectedTractorId: UUID?
    @State private var canopySize: CanopySize = .medium
    @State private var canopyDensity: CanopyDensity = .low
    @State private var sharedGrowthStageId: UUID?
    @State private var growthStageMode: GrowthStageMode = .same
    @State private var paddockPhenologyStages: [UUID: UUID] = [:]
    @State private var chemicalLines: [ChemicalLine] = []
    @State private var showAddChemicalToList: Bool = false
    @State private var sprayRateText: String = ""
    @State private var hasEditedSprayRate: Bool = false
    @State private var notes: String = ""

    // Trip setup
    @State private var numberOfFansJets: String = ""
    @State private var trackingPatternChoice: TrackingPattern = .sequential
    @State private var startingRow: Int = 1
    @State private var reversedDirection: Bool = false

    // Captured at job start
    @State private var capturedTemperature: Double?
    @State private var capturedWindSpeed: Double?
    @State private var capturedWindDirection: String = ""
    @State private var capturedHumidity: Double?

    // UI
    @State private var isPaddocksExpanded: Bool = true
    @State private var isEquipmentExpanded: Bool = true
    @State private var showAddEquipment: Bool = false
    @State private var calculationResult: SprayCalculationResult?
    @State private var showResults: Bool = false
    @State private var showSummary: Bool = false
    @State private var summaryMode: SprayCalculationSummaryMode = .savedForLater
    @State private var pendingTanks: [SprayTank] = []
    @State private var savedFeedback: Bool = false
    @State private var errorMessage: String?
    @State private var showStartConfirmation: Bool = false
    @State private var isStartingJob: Bool = false
    @State private var showWeatherDataSettings: Bool = false

    // Prefill (duplicate / template)
    private let prefillRecord: SprayRecord?
    @State private var prefillApplied: Bool = false

    init(prefillRecord: SprayRecord? = nil) {
        self.prefillRecord = prefillRecord
        if let r = prefillRecord {
            let baseName = r.sprayReference.isEmpty ? "" : r.sprayReference
            let prefilledName: String = {
                if r.isTemplate { return baseName }
                return baseName.isEmpty ? "" : "\(baseName) (Copy)"
            }()
            _sprayName = State(initialValue: prefilledName)
            _operationType = State(initialValue: r.operationType)
            _notes = State(initialValue: r.notes)
            _numberOfFansJets = State(initialValue: r.numberOfFansJets)
            if let firstTank = r.tanks.first, firstTank.sprayRatePerHa > 0 {
                _sprayRateText = State(initialValue: String(format: "%.0f", firstTank.sprayRatePerHa))
                _hasEditedSprayRate = State(initialValue: true)
            }
        }
    }

    // MARK: - Computed

    private var phenologyStages: [PhenologyStage] { PhenologyStage.allStages }

    private var selectedPaddocks: [Paddock] {
        store.paddocks.filter { selectedPaddockIds.contains($0.id) }
    }

    private var totalAreaHectares: Double {
        selectedPaddocks.reduce(0) { $0 + $1.areaHectares }
    }

    private var averageRowSpacing: Double {
        guard !selectedPaddocks.isEmpty else { return 2.5 }
        return selectedPaddocks.reduce(0) { $0 + $1.rowSpacingMetres } / Double(selectedPaddocks.count)
    }

    private var waterRateEntry: CanopyWaterRate.RateEntry {
        CanopyWaterRate.rate(
            size: canopySize,
            density: canopyDensity,
            rowSpacingMetres: averageRowSpacing,
            settings: store.settings.canopyWaterRates
        )
    }

    private var chosenSprayRate: Double {
        Double(sprayRateText) ?? waterRateEntry.litresPerHa
    }

    private var concentrationFactor: Double {
        guard chosenSprayRate > 0 else { return 1.0 }
        return waterRateEntry.litresPerHa / chosenSprayRate
    }

    private var formIsValid: Bool {
        !selectedPaddockIds.isEmpty && selectedEquipmentId != nil && !chemicalLines.isEmpty
    }

    private var previewPaddock: Paddock? {
        selectedPaddocks.first(where: { !$0.rows.isEmpty }) ?? selectedPaddocks.first
    }

    private var totalPreviewRows: Int { previewPaddock?.rows.count ?? 0 }

    private var pathSequencePreview: [Double] {
        guard let p = previewPaddock, !p.rows.isEmpty else { return [] }
        return trackingPatternChoice.generateSequence(
            startRow: max(1, min(startingRow, p.rows.count)),
            totalRows: p.rows.count,
            reversed: reversedDirection
        )
    }

    private var selectedTractorName: String {
        selectedTractorId.flatMap { id in
            store.tractors.first(where: { $0.id == id })?.displayName
        } ?? "Not selected"
    }

    private var selectedEquipmentName: String {
        selectedEquipmentId.flatMap { id in
            store.sprayEquipment.first(where: { $0.id == id })?.name
        } ?? "Not selected"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    sprayNameSection
                    operationTypeSection
                    paddockSelection
                    growthStageSection
                    equipmentSelection
                    waterRateSection
                    chemicalLinesSection
                    notesSection
                    actionButtons

                    if showResults, let result = calculationResult {
                        ResultsCard(result: result)
                        if let costing = result.costingSummary, accessControl.canViewFinancials {
                            CostingsCard(summary: costing)
                        }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 8))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Spray Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.success, trigger: savedFeedback)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .sheet(isPresented: $showSummary, onDismiss: { dismiss() }) {
                if let result = calculationResult {
                    SprayCalculationSummarySheet(
                        result: result,
                        sprayName: sprayName,
                        mode: summaryMode,
                        canViewFinancials: accessControl.canViewFinancials,
                        onContinue: summaryMode == .readyToStart ? { finalizeStartFromMixSummary() } : nil
                    )
                }
            }
            .sheet(isPresented: $showAddEquipment) {
                EquipmentFormSheet(equipment: nil)
            }
            .sheet(isPresented: $showAddChemicalToList) {
                EditSavedChemicalSheet(chemical: nil)
            }
            .sheet(isPresented: $showStartConfirmation) {
                startConfirmationSheet
            }
            .onAppear { applyPrefillIfNeeded() }
        }
    }

    private func applyPrefillIfNeeded() {
        guard let r = prefillRecord, !prefillApplied else { return }
        prefillApplied = true

        if !r.equipmentType.isEmpty {
            selectedEquipmentId = store.sprayEquipment.first(where: { $0.name == r.equipmentType })?.id
        }
        if !r.tractor.isEmpty {
            selectedTractorId = store.tractors.first(where: { $0.displayName == r.tractor || $0.name == r.tractor })?.id
        }
        if let trip = store.trips.first(where: { $0.id == r.tripId }) {
            selectedPaddockIds = Set(trip.paddockIds)
        }

        if let firstTank = r.tanks.first {
            var lines: [ChemicalLine] = []
            for chem in firstTank.chemicals {
                guard let saved = store.savedChemicals.first(where: {
                    $0.name.caseInsensitiveCompare(chem.name) == .orderedSame
                }) else { continue }
                let basis: RateBasis = chem.ratePer100L > 0 ? .per100Litres : .perHectare
                let rate = saved.rates.first(where: { $0.basis == basis }) ?? saved.rates.first
                lines.append(
                    ChemicalLine(
                        chemicalId: saved.id,
                        selectedRateId: rate?.id ?? UUID(),
                        basis: rate?.basis ?? basis
                    )
                )
            }
            chemicalLines = lines
        }
    }

    // MARK: - Sections

    private var sprayNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Spray Name", icon: "tag")
            TextField("e.g. Downy Mildew Spray #3", text: $sprayName)
                .font(.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 10))
        }
    }

    private var operationTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Operation Type", icon: "gearshape.2")
            VStack(spacing: 0) {
                ForEach(OperationType.allCases, id: \.self) { type in
                    let isSelected = operationType == type
                    Button {
                        operationType = type
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(isSelected ? AnyShapeStyle(VineyardTheme.olive) : AnyShapeStyle(.tertiary))
                            Image(systemName: type.iconName)
                                .font(.subheadline)
                                .foregroundStyle(isSelected ? VineyardTheme.olive : .secondary)
                                .frame(width: 24)
                            Text(type.rawValue).foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    if type != OperationType.allCases.last {
                        Divider().padding(.leading, 48)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 10))
        }
    }

    private var paddockSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(duration: 0.3)) { isPaddocksExpanded.toggle() }
            } label: {
                HStack {
                    PaddockSectionHeader(title: "Paddocks")
                    Spacer()
                    if !selectedPaddockIds.isEmpty {
                        Text("\(selectedPaddockIds.count) selected")
                            .font(.caption)
                            .foregroundStyle(VineyardTheme.olive)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isPaddocksExpanded ? 90 : 0))
                }
            }

            if isPaddocksExpanded {
                VStack(spacing: 0) {
                    if store.paddocks.isEmpty {
                        Text("No paddocks configured")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(store.paddocks) { paddock in
                        let isSelected = selectedPaddockIds.contains(paddock.id)
                        Button {
                            if isSelected {
                                selectedPaddockIds.remove(paddock.id)
                            } else {
                                selectedPaddockIds.insert(paddock.id)
                            }
                        } label: {
                            HStack {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? AnyShapeStyle(VineyardTheme.olive) : AnyShapeStyle(.tertiary))
                                Text(paddock.name).foregroundStyle(.primary)
                                Spacer()
                                Text("\(paddock.areaHectares, specifier: "%.2f") ha")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        if paddock.id != store.paddocks.last?.id {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 10))
            }

            if !selectedPaddockIds.isEmpty {
                Text("Total: \(totalAreaHectares, specifier: "%.2f") ha selected")
                    .font(.caption)
                    .foregroundStyle(VineyardTheme.olive)
            }
        }
    }

    private var growthStageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Growth Stage", icon: "leaf.arrow.circlepath")

            if selectedPaddockIds.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("Select paddocks above to assign growth stages")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 10))
            } else {
                Picker("", selection: $growthStageMode) {
                    Text("Same for All").tag(GrowthStageMode.same)
                    Text("Per Paddock").tag(GrowthStageMode.perPaddock)
                }
                .pickerStyle(.segmented)
                .onChange(of: growthStageMode) { _, newMode in
                    if newMode == .same, let shared = sharedGrowthStageId {
                        for pid in selectedPaddockIds {
                            paddockPhenologyStages[pid] = shared
                        }
                    }
                }

                if growthStageMode == .same {
                    sameGrowthStageList
                } else {
                    perPaddockGrowthStageList
                }
            }
        }
    }

    private var sameGrowthStageList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("E-L Growth Stages")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Button {
                sharedGrowthStageId = nil
                for pid in selectedPaddockIds {
                    paddockPhenologyStages.removeValue(forKey: pid)
                }
            } label: {
                HStack {
                    Image(systemName: sharedGrowthStageId == nil ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(sharedGrowthStageId == nil ? AnyShapeStyle(VineyardTheme.olive) : AnyShapeStyle(.tertiary))
                    Text("Not Set").foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            Divider().padding(.leading, 40)

            ForEach(phenologyStages) { stage in
                let isSelected = sharedGrowthStageId == stage.id
                Button {
                    sharedGrowthStageId = stage.id
                    for pid in selectedPaddockIds {
                        paddockPhenologyStages[pid] = stage.id
                    }
                } label: {
                    HStack {
                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(isSelected ? AnyShapeStyle(VineyardTheme.olive) : AnyShapeStyle(.tertiary))
                        Text(stage.code)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 56, alignment: .leading)
                        Text(stage.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                if stage.id != phenologyStages.last?.id {
                    Divider().padding(.leading, 40)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 10))
    }

    private var perPaddockGrowthStageList: some View {
        let paddocks = selectedPaddocks
        return VStack(spacing: 0) {
            ForEach(paddocks) { paddock in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(paddock.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        if let stageId = paddockPhenologyStages[paddock.id],
                           let stage = phenologyStages.first(where: { $0.id == stageId }) {
                            Text("\(stage.name) (\(stage.code))")
                                .font(.caption2)
                                .foregroundStyle(VineyardTheme.leafGreen)
                        }
                    }
                    Spacer()
                    Menu {
                        Button("Not Set") { paddockPhenologyStages.removeValue(forKey: paddock.id) }
                        ForEach(phenologyStages) { stage in
                            Button("\(stage.code) – \(stage.name)") {
                                paddockPhenologyStages[paddock.id] = stage.id
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if let stageId = paddockPhenologyStages[paddock.id],
                               let stage = phenologyStages.first(where: { $0.id == stageId }) {
                                Text(stage.code).font(.caption.weight(.semibold))
                            } else {
                                Text("Select").font(.caption)
                            }
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .foregroundStyle(VineyardTheme.olive)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(VineyardTheme.olive.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                if paddock.id != paddocks.last?.id {
                    Divider().padding(.leading, 12)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 10))
    }

    private var equipmentSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(duration: 0.3)) { isEquipmentExpanded.toggle() }
            } label: {
                HStack {
                    SectionHeader(title: "Equipment", icon: "wrench.and.screwdriver")
                    Spacer()
                    if let id = selectedEquipmentId,
                       let eq = store.sprayEquipment.first(where: { $0.id == id }) {
                        Text(eq.name)
                            .font(.caption)
                            .foregroundStyle(VineyardTheme.olive)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isEquipmentExpanded ? 90 : 0))
                }
            }
            .overlay(alignment: .trailing) {
                Button {
                    showAddEquipment = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(VineyardTheme.olive)
                        .padding(.trailing, 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add Equipment")
            }

            if isEquipmentExpanded {
                VStack(spacing: 0) {
                    if store.sprayEquipment.isEmpty {
                        Button {
                            showAddEquipment = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(VineyardTheme.olive)
                                Text("Add Equipment")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(store.sprayEquipment) { item in
                        let isSelected = selectedEquipmentId == item.id
                        Button {
                            selectedEquipmentId = item.id
                        } label: {
                            HStack {
                                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(isSelected ? AnyShapeStyle(VineyardTheme.olive) : AnyShapeStyle(.tertiary))
                                Text(item.name).foregroundStyle(.primary)
                                Spacer()
                                Text("\(item.tankCapacityLitres, specifier: "%.0f") L")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        if item.id != store.sprayEquipment.last?.id {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 10))
            }
        }
    }

    private var waterRateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Calculated Water Rate", icon: "drop.fill")
            Text("Based on row widths & canopy status")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("VSP Canopy Size")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Picker("Canopy Size", selection: $canopySize) {
                        ForEach(CanopySize.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(canopySize.description)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let imageURL = canopySize.referenceImageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            case .failure:
                                Image(systemName: "leaf")
                                    .font(.title)
                                    .foregroundStyle(.tertiary)
                            case .empty:
                                ProgressView()
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .padding(8)
                        .background(Color.white)
                        .clipShape(.rect(cornerRadius: 8))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Canopy Density")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Picker("Canopy Density", selection: $canopyDensity) {
                        ForEach(CanopyDensity.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Volume")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(String(format: "%.0f", waterRateEntry.litresPerHa)) L/ha")
                            .font(.title3.bold())
                            .foregroundStyle(VineyardTheme.olive)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Per 100m row")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(String(format: "%.0f", waterRateEntry.litresPer100m)) L")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(12)
                .background(VineyardTheme.olive.opacity(0.08))
                .clipShape(.rect(cornerRadius: 10))

                Text("Row spacing: \(String(format: "%.1f", averageRowSpacing))m")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if operationType.useConcentrationFactor {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Spray Rate & Concentration Factor")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Chosen Spray Rate (L/ha)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("L/ha", text: $sprayRateText)
                                    .keyboardType(.decimalPad)
                                    .font(.body.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color(.tertiarySystemGroupedBackground))
                                    .clipShape(.rect(cornerRadius: 8))
                                    .onChange(of: sprayRateText) { _, _ in hasEditedSprayRate = true }
                            }
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("CF").font(.caption).foregroundStyle(.secondary)
                                Text(String(format: "%.2f", concentrationFactor))
                                    .font(.title2.bold())
                                    .foregroundStyle(concentrationFactor == 1.0 ? VineyardTheme.olive : .orange)
                            }
                            .frame(minWidth: 60)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 10))
        }
        .onChange(of: waterRateEntry.litresPerHa) { _, newValue in
            if !hasEditedSprayRate {
                sprayRateText = String(format: "%.0f", newValue)
            }
        }
        .onAppear {
            if sprayRateText.isEmpty {
                sprayRateText = String(format: "%.0f", waterRateEntry.litresPerHa)
            }
        }
    }

    private var confirmTractorPicker: some View { tractorSelection }

    private var confirmTripSetup: some View { tripSetupSection }

    private var tractorSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Tractor (optional)", icon: "truck.pickup.side.fill")
            VStack(spacing: 0) {
                Button {
                    selectedTractorId = nil
                } label: {
                    HStack {
                        Image(systemName: selectedTractorId == nil ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selectedTractorId == nil ? AnyShapeStyle(VineyardTheme.olive) : AnyShapeStyle(.tertiary))
                        Text("Not Set").foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                ForEach(store.tractors) { tractor in
                    let isSelected = selectedTractorId == tractor.id
                    Divider().padding(.leading, 40)
                    Button {
                        selectedTractorId = tractor.id
                    } label: {
                        HStack {
                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(isSelected ? AnyShapeStyle(VineyardTheme.olive) : AnyShapeStyle(.tertiary))
                            Text(tractor.displayName).foregroundStyle(.primary)
                            Spacer()
                            if tractor.fuelUsageLPerHour > 0 {
                                Text("\(String(format: "%.1f", tractor.fuelUsageLPerHour)) L/hr")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 10))
        }
    }

    private var chemicalLinesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Chemicals", icon: "flask")

            ForEach($chemicalLines) { $line in
                CalcChemicalLineCard(
                    line: $line,
                    chemicals: store.savedChemicals
                ) {
                    chemicalLines.removeAll { $0.id == line.id }
                }
            }

            Button {
                if let chem = store.savedChemicals.first {
                    let rate = chem.rates.first
                    chemicalLines.append(
                        ChemicalLine(
                            chemicalId: chem.id,
                            selectedRateId: rate?.id ?? UUID(),
                            basis: rate?.basis ?? .perHectare
                        )
                    )
                }
            } label: {
                Label("Add Chemical", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VineyardTheme.olive)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(VineyardTheme.olive.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 10))
            }
            .disabled(store.savedChemicals.isEmpty)

            Button {
                showAddChemicalToList = true
            } label: {
                Label("Add New Chemical to List", systemImage: "flask.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VineyardTheme.leafGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(VineyardTheme.leafGreen.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 10))
            }

            if store.savedChemicals.isEmpty {
                Text("No chemicals configured. Tap “Add New Chemical to List” to create one.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var tripSetupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Trip Setup", icon: "map")

            VStack(spacing: 0) {
                HStack {
                    Label("No. Fans/Jets", systemImage: "fan")
                        .font(.subheadline)
                    Spacer()
                    TextField("e.g. 6", text: $numberOfFansJets)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().padding(.leading, 12)

                HStack {
                    Label("Tracking Pattern", systemImage: "arrow.triangle.swap")
                        .font(.subheadline)
                    Spacer()
                    Menu {
                        ForEach(TrackingPattern.allCases) { pattern in
                            Button(pattern.title) { trackingPatternChoice = pattern }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(trackingPatternChoice.title)
                                .font(.subheadline.weight(.medium))
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .foregroundStyle(VineyardTheme.olive)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().padding(.leading, 12)

                HStack {
                    Label("Start From Row", systemImage: "flag")
                        .font(.subheadline)
                    Spacer()
                    Stepper(value: $startingRow, in: 1...max(totalPreviewRows, 1)) {
                        Text("\(startingRow)\(totalPreviewRows > 0 ? " of \(totalPreviewRows)" : "")")
                            .font(.subheadline.weight(.medium).monospacedDigit())
                    }
                    .labelsHidden()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().padding(.leading, 12)

                Toggle(isOn: $reversedDirection) {
                    Label("Reverse Direction", systemImage: reversedDirection ? "arrow.left" : "arrow.right")
                        .font(.subheadline)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 10))

            if previewPaddock == nil {
                Text("Select paddocks to enable row sequencing.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var weatherNoteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "cloud.sun.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weather captured automatically")
                        .font(.subheadline.weight(.semibold))
                    Text("Temperature, wind and humidity will be recorded when the job starts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let label = sprayWeatherSourceLabel {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    Button {
                        showWeatherDataSettings = true
                    } label: {
                        Text("Manage")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .clipShape(.rect(cornerRadius: 10))
        .sheet(isPresented: $showWeatherDataSettings) {
            NavigationStack {
                WeatherDataSettingsView()
            }
        }
    }

    private var sprayWeatherSourceLabel: String? {
        guard let vid = store.selectedVineyardId else { return nil }
        let status = WeatherProviderResolver.resolve(
            for: vid,
            weatherStationId: store.settings.weatherStationId
        )
        switch status.provider {
        case .automatic:
            return "Source: Automatic Forecast"
        case .wunderground:
            let id = status.detailLabel
            return id.isEmpty ? "Source: Weather Underground PWS" : "Source: Weather Underground PWS — \(id)"
        case .davis:
            return "Source: Davis WeatherLink configured — fetch currently uses fallback"
        }
    }

    @ViewBuilder
    private var startConfirmationSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: "checklist")
                            .font(.system(size: 40))
                            .foregroundStyle(VineyardTheme.olive)
                        Text("Confirm Spray Job")
                            .font(.title2.bold())
                        Text("Review the details before starting.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)

                    VStack(spacing: 0) {
                        confirmRow(label: "Operator", value: auth.userName?.isEmpty == false ? (auth.userName ?? "") : "—", icon: "person.fill")
                        Divider().padding(.leading, 44)
                        confirmRow(label: "Equipment", value: selectedEquipmentName, icon: "wrench.and.screwdriver.fill")
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(.rect(cornerRadius: 12))
                    .padding(.horizontal)

                    confirmTractorPicker
                        .padding(.horizontal)

                    confirmTripSetup
                        .padding(.horizontal)

                    if !pathSequencePreview.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(VineyardTheme.olive)
                                Text("Path Sequence Preview")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(pathSequencePreview.count) paths")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(pathSequenceText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color(.tertiarySystemGroupedBackground))
                                .clipShape(.rect(cornerRadius: 8))
                        }
                        .padding(.horizontal)
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "cloud.sun.fill")
                            .foregroundStyle(.blue)
                        Text("Weather data will be captured automatically at the start.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(.rect(cornerRadius: 10))
                    .padding(.horizontal)

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 8))
                            .padding(.horizontal)
                    }

                    VStack(spacing: 8) {
                        Button {
                            Task { await confirmAndStartJob() }
                        } label: {
                            HStack(spacing: 8) {
                                if isStartingJob {
                                    ProgressView().controlSize(.small).tint(.white)
                                } else {
                                    Image(systemName: "play.fill")
                                }
                                Text(isStartingJob ? "Starting…" : "Start Job Now")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(VineyardTheme.olive)
                        .disabled(isStartingJob)

                        Button("Cancel") {
                            showStartConfirmation = false
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .disabled(isStartingJob)
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Confirm & Start")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isStartingJob)
        }
    }

    private var pathSequenceText: String {
        let preview = pathSequencePreview.prefix(40)
        let formatted = preview.map { value -> String in
            value.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", value)
                : String(format: "%.1f", value)
        }
        let suffix = pathSequencePreview.count > preview.count ? " …" : ""
        return formatted.joined(separator: " → ") + suffix
    }

    private func confirmRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(VineyardTheme.olive)
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Notes", icon: "note.text")
            TextField("Add notes about this spray job...", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 10))
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                saveAndStartJob()
            } label: {
                Label("Create Spray Job & Start", systemImage: "play.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(VineyardTheme.olive)
            .disabled(!formIsValid)

            Button {
                saveForLater()
            } label: {
                Label("Save Job for Future Use", systemImage: "clock.badge.checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(VineyardTheme.leafGreen)
            .disabled(!formIsValid)
        }
    }

    // MARK: - Calculation & Save

    private func performCalculation(jobDurationHours: Double = 0) {
        guard let equipId = selectedEquipmentId,
              let equip = store.sprayEquipment.first(where: { $0.id == equipId }) else { return }

        let tractor: Tractor? = selectedTractorId.flatMap { id in
            store.tractors.first(where: { $0.id == id })
        }

        calculationResult = SprayCalculator.calculate(
            selectedPaddocks: selectedPaddocks,
            waterRateLitresPerHectare: chosenSprayRate,
            tankCapacity: equip.tankCapacityLitres,
            chemicalLines: chemicalLines,
            chemicals: store.savedChemicals,
            concentrationFactor: concentrationFactor,
            operationType: operationType,
            tractor: tractor,
            jobDurationHours: jobDurationHours,
            fuelCostPerLitre: store.seasonFuelCostPerLitre
        )
        withAnimation(.spring(duration: 0.4)) { showResults = true }
    }

    private func buildSprayTanks(result: SprayCalculationResult, tankCapacity: Double) -> [SprayTank] {
        let totalTanks = result.fullTankCount + (result.lastTankLitres > 0 ? 1 : 0)
        guard totalTanks > 0 else {
            return [SprayTank(tankNumber: 1, waterVolume: 0, sprayRatePerHa: chosenSprayRate, concentrationFactor: concentrationFactor)]
        }

        var tanks: [SprayTank] = []
        for i in 0..<totalTanks {
            let isLast = (i == totalTanks - 1)
            let waterVolume = isLast && result.lastTankLitres > 0 ? result.lastTankLitres : tankCapacity
            let chemicals: [SprayChemical] = result.chemicalResults.map { chemResult in
                let amount = isLast ? chemResult.amountInLastTank : chemResult.amountPerFullTank
                // Snapshot the saved chemical's costPerBaseUnit (if any) so
                // TripCostService can calculate chemical cost reliably without
                // having to re-resolve the saved chemical later.
                return SprayChemical(
                    name: chemResult.chemicalName,
                    volumePerTank: amount,
                    ratePerHa: chemResult.basis == .perHectare ? chemResult.selectedRate : 0,
                    ratePer100L: chemResult.basis == .per100Litres ? chemResult.selectedRate : 0,
                    costPerUnit: chemResult.costPerBaseUnit ?? 0,
                    unit: chemResult.unit,
                    savedChemicalId: chemResult.savedChemicalId
                )
            }
            tanks.append(
                SprayTank(
                    tankNumber: i + 1,
                    waterVolume: waterVolume,
                    sprayRatePerHa: chosenSprayRate,
                    concentrationFactor: concentrationFactor,
                    chemicals: chemicals
                )
            )
        }
        return tanks
    }

    private func currentWeatherSnapshot() -> (temperature: Double?, windSpeed: Double?, windDirection: String, humidity: Double?) {
        (capturedTemperature, capturedWindSpeed, capturedWindDirection, capturedHumidity)
    }

    private func resolveWeatherCoordinate() -> CLLocationCoordinate2D? {
        for paddock in selectedPaddocks {
            let pts = paddock.polygonPoints
            guard !pts.isEmpty else { continue }
            let lat = pts.map(\.latitude).reduce(0, +) / Double(pts.count)
            let lon = pts.map(\.longitude).reduce(0, +) / Double(pts.count)
            if lat != 0 || lon != 0 {
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }
        return locationService.location?.coordinate
    }

    private func captureWeather() async {
        guard let coordinate = resolveWeatherCoordinate() else { return }
        let stationId = store.settings.weatherStationId
        let service = WeatherCurrentService()
        do {
            let snapshot = try await service.fetch(coordinate: coordinate, stationId: stationId)
            capturedTemperature = snapshot.temperatureC
            capturedWindSpeed = snapshot.windSpeedKmh
            if !snapshot.windDirection.isEmpty {
                capturedWindDirection = snapshot.windDirection
            }
            capturedHumidity = snapshot.humidityPercent
        } catch {
            // Weather capture is best-effort; ignore errors.
        }
    }

    private func saveAndStartJob() {
        guard formIsValid else { return }
        guard !accessControl.isLoading else { return }
        guard accessControl.canCreateOperationalRecords else {
            errorMessage = "Your role does not allow creating spray records."
            return
        }
        guard store.selectedVineyardId != nil else {
            errorMessage = "No vineyard selected."
            return
        }
        if tracking.activeTrip != nil {
            errorMessage = "A trip is already in progress. End it before starting a new spray."
            return
        }
        errorMessage = nil
        showStartConfirmation = true
    }

    private func confirmAndStartJob() async {
        guard formIsValid, !isStartingJob else { return }
        guard let equipId = selectedEquipmentId,
              let equip = store.sprayEquipment.first(where: { $0.id == equipId }) else { return }
        guard let vineyardId = store.selectedVineyardId else {
            errorMessage = "No vineyard selected."
            return
        }
        if tracking.activeTrip != nil {
            errorMessage = "A trip is already in progress. End it before starting a new spray."
            return
        }
        errorMessage = nil
        isStartingJob = true
        defer { isStartingJob = false }

        await captureWeather()
        performCalculation()

        let tanks: [SprayTank] = {
            guard let result = calculationResult else { return [] }
            return buildSprayTanks(result: result, tankCapacity: equip.tankCapacityLitres)
        }()
        pendingTanks = tanks

        _ = vineyardId
        summaryMode = .readyToStart
        showStartConfirmation = false
        showSummary = true
    }

    private func finalizeStartFromMixSummary() {
        guard let equipId = selectedEquipmentId,
              let equip = store.sprayEquipment.first(where: { $0.id == equipId }) else { return }
        guard let vineyardId = store.selectedVineyardId else {
            errorMessage = "No vineyard selected."
            return
        }
        if tracking.activeTrip != nil {
            errorMessage = "A trip is already in progress."
            return
        }

        let firstPaddock = selectedPaddocks.first
        let paddockNames = selectedPaddocks.map { $0.name }.joined(separator: ", ")

        tracking.startTrip(
            type: .spray,
            paddockId: firstPaddock?.id,
            paddockName: paddockNames,
            trackingPattern: trackingPatternChoice,
            personName: auth.userName ?? "",
            tractorId: selectedTractorId,
            operatorUserId: auth.userId
        )

        guard let activeTrip = tracking.activeTrip else {
            errorMessage = tracking.errorMessage ?? "Could not start trip."
            return
        }

        let weather = currentWeatherSnapshot()
        let tanks = pendingTanks.isEmpty
            ? (calculationResult.map { buildSprayTanks(result: $0, tankCapacity: equip.tankCapacityLitres) } ?? [])
            : pendingTanks

        var tripWithTanks = activeTrip
        tripWithTanks.totalTanks = tanks.count
        if let preview = previewPaddock, !preview.rows.isEmpty {
            let sequence = trackingPatternChoice.generateSequence(
                startRow: max(1, min(startingRow, preview.rows.count)),
                totalRows: preview.rows.count,
                reversed: reversedDirection
            )
            if let first = sequence.first {
                tripWithTanks.rowSequence = sequence
                tripWithTanks.sequenceIndex = 0
                tripWithTanks.currentRowNumber = first
                tripWithTanks.nextRowNumber = sequence.dropFirst().first ?? first
            }
        }
        store.updateTrip(tripWithTanks)

        let tractorName = selectedTractorId.flatMap { id in
            store.tractors.first(where: { $0.id == id })?.displayName
        } ?? ""

        let record = SprayRecord(
            tripId: activeTrip.id,
            vineyardId: vineyardId,
            date: Date(),
            startTime: Date(),
            temperature: weather.temperature,
            windSpeed: weather.windSpeed,
            windDirection: weather.windDirection,
            humidity: weather.humidity,
            sprayReference: sprayName,
            tanks: tanks,
            notes: notes,
            numberOfFansJets: numberOfFansJets,
            equipmentType: equip.name,
            tractor: tractorName,
            isTemplate: false,
            operationType: operationType
        )
        store.addSprayRecord(record)

        savedFeedback.toggle()
        showSummary = false
    }

    private func saveForLater() {
        guard formIsValid else { return }
        guard accessControl.canCreateOperationalRecords else {
            errorMessage = "Your role does not allow creating spray records."
            return
        }
        guard let equipId = selectedEquipmentId,
              let equip = store.sprayEquipment.first(where: { $0.id == equipId }) else { return }
        guard let vineyardId = store.selectedVineyardId else {
            errorMessage = "No vineyard selected."
            return
        }
        errorMessage = nil

        performCalculation()

        // Create a placeholder inactive trip so the record shows up under
        // "Not Started" in the spray program picker.
        let firstPaddock = selectedPaddocks.first
        let paddockNames = selectedPaddocks.map { $0.name }.joined(separator: ", ")
        let placeholderTrip = Trip(
            id: UUID(),
            vineyardId: vineyardId,
            paddockId: firstPaddock?.id,
            paddockName: paddockNames,
            paddockIds: selectedPaddocks.map { $0.id },
            startTime: Date(),
            endTime: nil,
            isActive: false
        )
        store.addInactiveTrip(placeholderTrip)

        let weather = currentWeatherSnapshot()
        let tanks: [SprayTank] = {
            guard let result = calculationResult else { return [] }
            return buildSprayTanks(result: result, tankCapacity: equip.tankCapacityLitres)
        }()

        let tractorName = selectedTractorId.flatMap { id in
            store.tractors.first(where: { $0.id == id })?.displayName
        } ?? ""

        let record = SprayRecord(
            tripId: placeholderTrip.id,
            vineyardId: vineyardId,
            date: Date(),
            startTime: Date(),
            temperature: weather.temperature,
            windSpeed: weather.windSpeed,
            windDirection: weather.windDirection,
            humidity: weather.humidity,
            sprayReference: sprayName,
            tanks: tanks,
            notes: notes,
            numberOfFansJets: numberOfFansJets,
            equipmentType: equip.name,
            tractor: tractorName,
            isTemplate: false,
            operationType: operationType
        )
        store.addSprayRecord(record)

        savedFeedback.toggle()
        summaryMode = .savedForLater
        showSummary = true
    }
}

// MARK: - Chemical Line Card

private struct CalcChemicalLineCard: View {
    @Binding var line: ChemicalLine
    let chemicals: [SavedChemical]
    let onDelete: () -> Void

    private var selectedChemical: SavedChemical? {
        chemicals.first(where: { $0.id == line.chemicalId })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "flask.fill")
                    .foregroundStyle(VineyardTheme.leafGreen)
                    .font(.subheadline)
                Text(selectedChemical?.name ?? "Select Chemical")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let chem = selectedChemical, !chem.rates.isEmpty {
                    Menu {
                        let haRates = chem.rates.filter { $0.basis == .perHectare }
                        let per100LRates = chem.rates.filter { $0.basis == .per100Litres }
                        if !haRates.isEmpty {
                            Section("Per Hectare") {
                                ForEach(haRates) { rate in
                                    Button {
                                        line.selectedRateId = rate.id
                                        line.basis = rate.basis
                                    } label: {
                                        Text("\(rate.label): \(String(format: "%.0f", chem.unit.fromBase(rate.value))) \(chem.unit.rawValue)/ha")
                                    }
                                }
                            }
                        }
                        if !per100LRates.isEmpty {
                            Section("Per 100L Water") {
                                ForEach(per100LRates) { rate in
                                    Button {
                                        line.selectedRateId = rate.id
                                        line.basis = rate.basis
                                    } label: {
                                        Text("\(rate.label): \(String(format: "%.0f", chem.unit.fromBase(rate.value))) \(chem.unit.rawValue)/100L")
                                    }
                                }
                            }
                        }
                    } label: {
                        let currentBasis = chem.rates.first(where: { $0.id == line.selectedRateId })?.basis ?? line.basis
                        HStack(spacing: 4) {
                            Text(currentBasis == .perHectare ? "Per Ha" : "Per 100L")
                                .font(.caption2.weight(.medium))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(currentBasis == .perHectare ? VineyardTheme.olive.opacity(0.15) : Color.blue.opacity(0.15))
                        .foregroundStyle(currentBasis == .perHectare ? VineyardTheme.olive : .blue)
                        .clipShape(Capsule())
                    }
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().padding(.leading, 14)

            VStack(alignment: .leading, spacing: 2) {
                Text("Chemical").font(.caption).foregroundStyle(.secondary)
                Picker("Chemical", selection: $line.chemicalId) {
                    ForEach(chemicals) { chem in
                        Text(chem.name).tag(chem.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: line.chemicalId) { _, newValue in
                    if let chem = chemicals.first(where: { $0.id == newValue }),
                       let firstRate = chem.rates.first {
                        line.selectedRateId = firstRate.id
                        line.basis = firstRate.basis
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if let chem = selectedChemical, !chem.rates.isEmpty {
                let haRates = chem.rates.filter { $0.basis == .perHectare }
                let per100LRates = chem.rates.filter { $0.basis == .per100Litres }

                Divider().padding(.leading, 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Rate").font(.caption).foregroundStyle(.secondary)
                    Picker("Rate", selection: $line.selectedRateId) {
                        if !haRates.isEmpty {
                            Section("Per Hectare") {
                                ForEach(haRates) { rate in
                                    Text("\(rate.label): \(String(format: "%.0f", chem.unit.fromBase(rate.value))) \(chem.unit.rawValue)/ha")
                                        .tag(rate.id)
                                }
                            }
                        }
                        if !per100LRates.isEmpty {
                            Section("Per 100L Water") {
                                ForEach(per100LRates) { rate in
                                    Text("\(rate.label): \(String(format: "%.0f", chem.unit.fromBase(rate.value))) \(chem.unit.rawValue)/100L")
                                        .tag(rate.id)
                                }
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .onChange(of: line.selectedRateId) { _, newRateId in
                        if let rate = chem.rates.first(where: { $0.id == newRateId }) {
                            line.basis = rate.basis
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 10))
    }
}

// MARK: - Results Card

private struct ResultsCard: View {
    let result: SprayCalculationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Results").font(.title2.bold())

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                CalcStatTile(title: "Total Area", value: "\(String(format: "%.2f", result.totalAreaHectares)) ha", icon: "square.dashed", color: VineyardTheme.olive)
                CalcStatTile(title: "Total Water", value: "\(String(format: "%.0f", result.totalWaterLitres)) L", icon: "drop.fill", color: .blue)
                CalcStatTile(title: "Full Tanks", value: "\(result.fullTankCount)", icon: "fuelpump.fill", color: VineyardTheme.earthBrown)
                CalcStatTile(title: "Last Tank", value: "\(String(format: "%.0f", result.lastTankLitres)) L", icon: "drop.halffull", color: .orange)
            }

            if result.concentrationFactor != 1.0 {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Concentration Factor")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(String(format: "%.2f", result.concentrationFactor))×")
                            .font(.headline)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Text(result.concentrationFactor > 1.0 ? "Concentrate" : "Dilute")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.15))
                        .clipShape(.rect(cornerRadius: 6))
                        .foregroundStyle(.orange)
                }
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 10))
            }

            ForEach(result.chemicalResults) { chemResult in
                CalcChemicalResultRow(result: chemResult)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
    }
}

private struct CalcStatTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 10))
    }
}

private struct CalcChemicalResultRow: View {
    let result: ChemicalCalculationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "flask.fill")
                    .foregroundStyle(VineyardTheme.leafGreen)
                Text(result.chemicalName).font(.headline)
                Spacer()
                Text("\(result.unit.fromBase(result.totalAmountRequired), specifier: "%.1f") \(result.unit.rawValue)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VineyardTheme.olive)
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Per full tank").font(.caption).foregroundStyle(.secondary)
                    Text("\(result.unit.fromBase(result.amountPerFullTank), specifier: "%.1f") \(result.unit.rawValue)")
                        .font(.subheadline.weight(.medium))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last tank").font(.caption).foregroundStyle(.secondary)
                    Text("\(result.unit.fromBase(result.amountInLastTank), specifier: "%.1f") \(result.unit.rawValue)")
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                Text("\(String(format: "%.0f", result.unit.fromBase(result.selectedRate))) \(result.unit.rawValue)/\(result.basis == .perHectare ? "ha" : "100L")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 10))
    }
}

// MARK: - Costings Card

private struct CostingsCard: View {
    let summary: SprayCostingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.title3)
                    .foregroundStyle(VineyardTheme.vineRed)
                Text("Costings").font(.title2.bold())
            }

            ForEach(summary.chemicalCosts) { cost in
                HStack {
                    Image(systemName: "flask.fill")
                        .foregroundStyle(VineyardTheme.leafGreen)
                        .font(.subheadline)
                    Text(cost.chemicalName).font(.subheadline.weight(.semibold))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("$\(String(format: "%.2f", cost.totalCost))")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(VineyardTheme.vineRed)
                        Text("$\(String(format: "%.2f", cost.costPerHectare))/ha")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 8))
            }

            if let fuel = summary.fuelCost {
                HStack {
                    Image(systemName: "fuelpump.fill")
                        .foregroundStyle(.orange)
                    Text("Fuel — \(fuel.tractorName)").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("$\(String(format: "%.2f", fuel.totalFuelCost))")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.orange)
                }
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 8))
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Grand Total").font(.subheadline).foregroundStyle(.secondary)
                    Text("$\(String(format: "%.2f", summary.grandTotal))")
                        .font(.title.bold())
                        .foregroundStyle(VineyardTheme.vineRed)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Per Hectare").font(.subheadline).foregroundStyle(.secondary)
                    Text("$\(String(format: "%.2f", summary.grandTotalPerHectare))/ha")
                        .font(.title3.bold())
                        .foregroundStyle(VineyardTheme.earthBrown)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 14))
    }
}
