import SwiftUI

struct SprayPresetsView: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(\.accessControl) private var accessControl
    @State private var showAddChemical: Bool = false
    @State private var showAddPreset: Bool = false
    @State private var editingChemical: SavedChemical?
    @State private var editingPreset: SavedSprayPreset?

    private var canManageSetup: Bool { accessControl?.canManageSetup ?? false }

    var body: some View {
        List {
            chemicalsSection
            tankPresetsSection
        }
        .navigationTitle("Spray Presets")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddChemical) {
            EditSavedChemicalSheet(chemical: nil)
        }
        .sheet(item: $editingChemical) { chem in
            EditSavedChemicalSheet(chemical: chem)
        }
        .sheet(isPresented: $showAddPreset) {
            EditSavedSprayPresetSheet(preset: nil)
        }
        .sheet(item: $editingPreset) { preset in
            EditSavedSprayPresetSheet(preset: preset)
        }
    }

    private var chemicalsSection: some View {
        Section {
            ForEach(store.savedChemicals) { chemical in
                Group {
                    if canManageSetup {
                        Button {
                            editingChemical = chemical
                        } label: { chemicalRowContent(chemical) }
                    } else {
                        chemicalRowContent(chemical)
                    }
                }
                .swipeActions(edge: .trailing) {
                    if canManageSetup {
                        Button(role: .destructive) {
                            store.deleteSavedChemical(chemical)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            if canManageSetup {
                Button {
                    showAddChemical = true
                } label: {
                    Label("Add Chemical", systemImage: "plus.circle")
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "flask.fill")
                    .foregroundStyle(VineyardTheme.olive)
                    .font(.caption)
                Text("Chemicals")
            }
        } footer: {
            if canManageSetup {
                Text("Saved chemicals are shared with all users of this vineyard.")
            } else {
                Text("Setup data is managed by vineyard owners and managers.")
            }
        }
    }

    @ViewBuilder
    private func chemicalRowContent(_ chemical: SavedChemical) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(chemical.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                if !chemical.activeIngredient.isEmpty {
                    Text(chemical.activeIngredient)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("\(String(format: "%.2f", chemical.ratePerHa)) \(chemical.unit.rawValue)/Ha")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if canManageSetup {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var tankPresetsSection: some View {
        Section {
            ForEach(store.savedSprayPresets) { preset in
                Group {
                    if canManageSetup {
                        Button {
                            editingPreset = preset
                        } label: { presetRowContent(preset) }
                    } else {
                        presetRowContent(preset)
                    }
                }
                .swipeActions(edge: .trailing) {
                    if canManageSetup {
                        Button(role: .destructive) {
                            store.deleteSavedSprayPreset(preset)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            if canManageSetup {
                Button {
                    showAddPreset = true
                } label: {
                    Label("Add Tank Preset", systemImage: "plus.circle")
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .foregroundStyle(VineyardTheme.olive)
                    .font(.caption)
                Text("Tank Presets")
            }
        } footer: {
            Text("Tank presets save Water Volume, Spray Rate, and Concentration Factor.")
        }
    }

    @ViewBuilder
    private func presetRowContent(_ preset: SavedSprayPreset) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(Int(preset.waterVolume))L • \(Int(preset.sprayRatePerHa))L/Ha • CF \(String(format: "%.1f", preset.concentrationFactor))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if canManageSetup {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Edit Saved Chemical Sheet

private enum ChemicalFormType: String, CaseIterable, Identifiable {
    case liquid = "Liquid"
    case solid = "Solid"
    var id: String { rawValue }

    var units: [ChemicalUnit] {
        switch self {
        case .liquid: return [.litres, .millilitres]
        case .solid: return [.kilograms, .grams]
        }
    }

    static func from(unit: ChemicalUnit) -> ChemicalFormType {
        switch unit {
        case .litres, .millilitres: return .liquid
        case .kilograms, .grams: return .solid
        }
    }
}

struct EditSavedChemicalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MigratedDataStore.self) private var store
    @Environment(\.accessControl) private var accessControl

    /// Purchase cost data (container size, dollar cost) is owner/manager only.
    /// Supervisors/operators can still see other chemical details but the
    /// purchase/cost section is hidden so they never see pricing.
    private var canViewFinancials: Bool { accessControl?.canViewFinancials ?? false }

    let chemical: SavedChemical?

    @State private var name: String = ""
    @State private var formType: ChemicalFormType = .liquid
    @State private var unit: ChemicalUnit = .litres
    @State private var chemicalGroup: String = ""
    @State private var use: String = ""
    @State private var manufacturer: String = ""
    @State private var notes: String = ""
    @State private var problem: String = ""
    @State private var ratePerHaText: String = ""
    @State private var ratePer100LText: String = ""
    @State private var activeIngredient: String = ""
    @State private var modeOfAction: String = ""
    @State private var labelURL: String = ""
    @State private var trackPurchase: Bool = false
    @State private var containerSizeText: String = ""
    @State private var containerUnit: ChemicalUnit = .litres
    @State private var costText: String = ""
    @State private var showAILookup: Bool = false
    @State private var aiLoading: Bool = false
    @State private var aiError: String?

    private let existingPerHaRateId: UUID?
    private let existingPer100LRateId: UUID?

    init(chemical: SavedChemical?) {
        self.chemical = chemical
        if let c = chemical {
            _name = State(initialValue: c.name)
            _unit = State(initialValue: c.unit)
            _formType = State(initialValue: ChemicalFormType.from(unit: c.unit))
            _chemicalGroup = State(initialValue: c.chemicalGroup)
            _use = State(initialValue: c.use)
            _manufacturer = State(initialValue: c.manufacturer)
            _notes = State(initialValue: c.notes)
            _problem = State(initialValue: c.problem)
            _activeIngredient = State(initialValue: c.activeIngredient)
            _modeOfAction = State(initialValue: c.modeOfAction)
            _labelURL = State(initialValue: c.labelURL)

            let perHa = c.rates.first(where: { $0.basis == .perHectare })
            let per100L = c.rates.first(where: { $0.basis == .per100Litres })
            self.existingPerHaRateId = perHa?.id
            self.existingPer100LRateId = per100L?.id

            if let perHa {
                _ratePerHaText = State(initialValue: Self.formatRate(c.unit.fromBase(perHa.value)))
            } else if c.ratePerHa > 0 {
                _ratePerHaText = State(initialValue: Self.formatRate(c.ratePerHa))
            }
            if let per100L {
                _ratePer100LText = State(initialValue: Self.formatRate(c.unit.fromBase(per100L.value)))
            }

            if let p = c.purchase {
                _trackPurchase = State(initialValue: true)
                _containerSizeText = State(initialValue: Self.formatRate(p.containerSizeML))
                _containerUnit = State(initialValue: p.containerUnit)
                _costText = State(initialValue: p.costDollars > 0 ? Self.formatRate(p.costDollars) : "")
            } else {
                _containerUnit = State(initialValue: c.unit)
            }
        } else {
            self.existingPerHaRateId = nil
            self.existingPer100LRateId = nil
        }
    }

    private static func formatRate(_ value: Double) -> String {
        if value == 0 { return "" }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if store.settings.aiSuggestionsEnabled {
                    aiSection
                }
                productSection
                detailsSection
                ratesSection
                if canViewFinancials {
                    purchaseSection
                }
                sharingSection
                notesSection
            }
            .navigationTitle(chemical == nil ? "New Chemical" : "Edit Chemical")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAILookup) {
                ChemicalAILookupSheet(initialQuery: name) { result in
                    Task { await applyAIResult(result) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onChange(of: formType) { _, newValue in
                if !newValue.units.contains(unit) {
                    unit = newValue.units.first ?? .litres
                }
                if !newValue.units.contains(containerUnit) {
                    containerUnit = newValue.units.first ?? .litres
                }
            }
        }
    }

    private var aiSection: some View {
        Section {
            Button {
                showAILookup = true
            } label: {
                Label(aiLoading ? "Looking up..." : "Search with AI", systemImage: "sparkles")
            }
            .disabled(aiLoading)
            if let aiError {
                Text(aiError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } footer: {
            Text("AI suggestions must be checked against the current product label, permit, SDS, and local regulations before use.")
        }
    }

    private var productSection: some View {
        Section("Product") {
            TextField("Chemical Name", text: $name)
            Picker("Form", selection: $formType) {
                ForEach(ChemicalFormType.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            Picker("Unit", selection: $unit) {
                ForEach(formType.units, id: \.self) { u in
                    Text(u.rawValue).tag(u)
                }
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Active Ingredient", text: $activeIngredient)
            TextField("Chemical Group", text: $chemicalGroup)
            TextField("Use / Problem", text: $use)
            TextField("Target Problem (e.g. Powdery Mildew)", text: $problem)
            TextField("Manufacturer", text: $manufacturer)
            TextField("Mode of Action (MOA)", text: $modeOfAction)
            TextField("Label URL", text: $labelURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private var ratesSection: some View {
        Section {
            HStack {
                Text("Per Ha")
                Spacer()
                TextField("0", text: $ratePerHaText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                Text("\(unit.rawValue)/ha")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Per 100L Water")
                Spacer()
                TextField("0", text: $ratePer100LText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                Text("\(unit.rawValue)/100L")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Rates")
        } footer: {
            Text("Enter either or both. The Spray Calculator lets the operator pick which basis to use per job.")
        }
    }

    private var purchaseSection: some View {
        Section {
            Toggle("Track Purchase Info", isOn: $trackPurchase.animation())
            if trackPurchase {
                HStack {
                    Text("Container Size")
                    Spacer()
                    TextField("0", text: $containerSizeText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Picker("Unit", selection: $containerUnit) {
                        ForEach(formType.units, id: \.self) { u in
                            Text(u.rawValue).tag(u)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                HStack {
                    Text("Cost")
                    Spacer()
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $costText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                }
            }
        } header: {
            Text("Purchase Tracking")
        } footer: {
            Text("Used to calculate chemical cost in spray reports. AI does not fill in pricing — enter it from your invoice.")
        }
    }

    private var sharingSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(.secondary)
                Text("Saved chemicals are shared with all users of this vineyard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $notes)
                .frame(minHeight: 60)
        }
    }

    @MainActor
    private func applyAIResult(_ result: ChemicalSearchResult) async {
        aiError = nil
        aiLoading = true
        defer { aiLoading = false }
        if name.isEmpty { name = result.name }
        if activeIngredient.isEmpty { activeIngredient = result.activeIngredient }
        if manufacturer.isEmpty { manufacturer = result.brand }
        if chemicalGroup.isEmpty { chemicalGroup = result.chemicalGroup }
        if modeOfAction.isEmpty { modeOfAction = result.modeOfAction }
        if use.isEmpty { use = result.primaryUse }
        if problem.isEmpty { problem = result.primaryUse }

        let country = ChemicalInfoService.resolveCountry(vineyardCountry: store.selectedVineyard?.country)
        do {
            let info = try await ChemicalInfoService().lookupChemicalInfo(productName: result.name, country: country)
            if activeIngredient.isEmpty { activeIngredient = info.activeIngredient }
            if manufacturer.isEmpty { manufacturer = info.brand }
            if chemicalGroup.isEmpty { chemicalGroup = info.chemicalGroup }
            if labelURL.isEmpty { labelURL = LabelURLValidator.sanitize(info.labelURL) }
            if let moa = info.modeOfAction, modeOfAction.isEmpty { modeOfAction = moa }
            if use.isEmpty { use = info.primaryUse }
            unit = info.defaultUnit
            formType = ChemicalFormType.from(unit: info.defaultUnit)
            if !formType.units.contains(containerUnit) {
                containerUnit = info.defaultUnit
            }
            if let rates = info.ratesPerHectare, let first = rates.first, ratePerHaText.isEmpty {
                ratePerHaText = Self.formatRate(first.value)
            }
            if let rates = info.ratesPer100L, let first = rates.first, ratePer100LText.isEmpty {
                ratePer100LText = Self.formatRate(first.value)
            }
        } catch {
            aiError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func save() {
        let perHaDisplay = Double(ratePerHaText) ?? 0
        let per100LDisplay = Double(ratePer100LText) ?? 0

        var rates: [ChemicalRate] = []
        if perHaDisplay > 0 {
            rates.append(ChemicalRate(
                id: existingPerHaRateId ?? UUID(),
                label: "Per Ha",
                value: unit.toBase(perHaDisplay),
                basis: .perHectare
            ))
        }
        if per100LDisplay > 0 {
            rates.append(ChemicalRate(
                id: existingPer100LRateId ?? UUID(),
                label: "Per 100L",
                value: unit.toBase(per100LDisplay),
                basis: .per100Litres
            ))
        }

        // Preserve existing purchase data when the editor cannot see/edit
        // financials so that owners/managers don't lose cost values when a
        // supervisor/operator edits the same chemical for other details.
        var purchase: ChemicalPurchase? = canViewFinancials ? nil : chemical?.purchase
        if canViewFinancials, trackPurchase {
            let containerSize = Double(containerSizeText) ?? 0
            let cost = Double(costText) ?? 0
            if containerSize > 0 || cost > 0 {
                purchase = ChemicalPurchase(
                    brand: manufacturer,
                    activeIngredient: activeIngredient,
                    chemicalGroup: chemicalGroup,
                    labelURL: labelURL,
                    costDollars: cost,
                    containerSizeML: containerSize,
                    containerUnit: containerUnit
                )
            }
        }

        if var existing = chemical {
            existing.name = name
            existing.unit = unit
            existing.chemicalGroup = chemicalGroup
            existing.use = use
            existing.manufacturer = manufacturer
            existing.notes = notes
            existing.problem = problem
            existing.ratePerHa = perHaDisplay
            existing.activeIngredient = activeIngredient
            existing.modeOfAction = modeOfAction
            existing.labelURL = labelURL
            existing.rates = rates
            existing.purchase = purchase
            store.updateSavedChemical(existing)
        } else {
            let new = SavedChemical(
                name: name,
                ratePerHa: perHaDisplay,
                unit: unit,
                chemicalGroup: chemicalGroup,
                use: use,
                manufacturer: manufacturer,
                notes: notes,
                problem: problem,
                activeIngredient: activeIngredient,
                rates: rates,
                purchase: purchase,
                labelURL: labelURL,
                modeOfAction: modeOfAction
            )
            store.addSavedChemical(new)
        }
    }
}

// MARK: - Chemical AI Lookup Sheet

struct ChemicalAILookupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MigratedDataStore.self) private var store

    let initialQuery: String
    let onSelect: (ChemicalSearchResult) -> Void

    @State private var query: String = ""
    @State private var results: [ChemicalSearchResult] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    init(initialQuery: String, onSelect: @escaping (ChemicalSearchResult) -> Void) {
        self.initialQuery = initialQuery
        self.onSelect = onSelect
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Product or active ingredient", text: $query)
                            .textInputAutocapitalization(.words)
                            .onSubmit { Task { await search() } }
                        Button {
                            Task { await search() }
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .disabled(isLoading || query.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } footer: {
                    Text("AI suggestions must be checked against the current label, permit, SDS, and local regulations before use.")
                }

                if isLoading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Searching...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { item in
                            Button {
                                onSelect(item)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if !item.activeIngredient.isEmpty {
                                        Text(item.activeIngredient)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    HStack(spacing: 6) {
                                        if !item.brand.isEmpty {
                                            Text(item.brand).font(.caption2).foregroundStyle(.tertiary)
                                        }
                                        if !item.chemicalGroup.isEmpty {
                                            Text("• \(item.chemicalGroup)").font(.caption2).foregroundStyle(.tertiary)
                                        }
                                        if !item.modeOfAction.isEmpty {
                                            Text("• MOA \(item.modeOfAction)").font(.caption2).foregroundStyle(.tertiary)
                                        }
                                    }
                                    if !item.primaryUse.isEmpty {
                                        Text(item.primaryUse)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if !initialQuery.trimmingCharacters(in: .whitespaces).isEmpty && results.isEmpty {
                    await search()
                }
            }
        }
    }

    @MainActor
    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        let country = ChemicalInfoService.resolveCountry(vineyardCountry: store.selectedVineyard?.country)
        do {
            results = try await ChemicalInfoService().searchChemicals(query: trimmed, country: country)
            if results.isEmpty {
                errorMessage = "No products found."
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            results = []
        }
    }
}

// MARK: - Edit Saved Spray Preset Sheet

struct EditSavedSprayPresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MigratedDataStore.self) private var store

    let preset: SavedSprayPreset?

    @State private var name: String = ""
    @State private var waterVolumeText: String = ""
    @State private var sprayRateText: String = ""
    @State private var concentrationText: String = "1.0"

    init(preset: SavedSprayPreset?) {
        self.preset = preset
        if let p = preset {
            _name = State(initialValue: p.name)
            _waterVolumeText = State(initialValue: String(format: "%.0f", p.waterVolume))
            _sprayRateText = State(initialValue: String(format: "%.0f", p.sprayRatePerHa))
            _concentrationText = State(initialValue: String(format: "%.1f", p.concentrationFactor))
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Preset Name", text: $name)
                }
                Section("Volumes") {
                    HStack {
                        Text("Water Volume")
                        Spacer()
                        TextField("0", text: $waterVolumeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("L")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Spray Rate")
                        Spacer()
                        TextField("0", text: $sprayRateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("L/Ha")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Concentration Factor")
                        Spacer()
                        TextField("1.0", text: $concentrationText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
            }
            .navigationTitle(preset == nil ? "New Preset" : "Edit Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        let water = Double(waterVolumeText) ?? 0
        let rate = Double(sprayRateText) ?? 0
        let cf = Double(concentrationText) ?? 1.0
        if var existing = preset {
            existing.name = name
            existing.waterVolume = water
            existing.sprayRatePerHa = rate
            existing.concentrationFactor = cf
            store.updateSavedSprayPreset(existing)
        } else {
            let new = SavedSprayPreset(
                name: name,
                waterVolume: water,
                sprayRatePerHa: rate,
                concentrationFactor: cf
            )
            store.addSavedSprayPreset(new)
        }
    }
}
