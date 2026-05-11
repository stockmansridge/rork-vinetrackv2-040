import SwiftUI

struct EquipmentManagementView: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(\.accessControl) private var accessControl
    @State private var showAddSheet: Bool = false
    @State private var editingEquipment: SprayEquipmentItem?
    @State private var showAddTractorSheet: Bool = false
    @State private var editingTractor: Tractor?
    @State private var showAddFuelSheet: Bool = false
    @State private var editingFuelPurchase: FuelPurchase?

    private var canManageSetup: Bool { accessControl?.canManageSetup ?? false }

    private var otherItemsCount: Int {
        guard let vid = store.selectedVineyardId else { return 0 }
        return store.equipmentItems.filter { $0.vineyardId == vid }.count
    }

    private var otherItemsSubtitle: String {
        let count = otherItemsCount
        if count == 0 { return "Add quad bikes, utes, pumps, generators…" }
        return "\(count) item\(count == 1 ? "" : "s")"
    }

    var body: some View {
        List {
            Section {
                ForEach(store.sprayEquipment) { item in
                    Group {
                        if canManageSetup {
                            Button { editingEquipment = item } label: { EquipmentRow(equipment: item) }
                        } else {
                            EquipmentRow(equipment: item)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if canManageSetup {
                            Button(role: .destructive) {
                                store.deleteSprayEquipment(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Label("Spray Rigs & Tanks", systemImage: "wrench.and.screwdriver")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                    Spacer()
                    if canManageSetup {
                        Button {
                            showAddSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.body)
                        }
                    }
                }
            } footer: {
                if !canManageSetup {
                    Text("Setup data is managed by vineyard owners and managers.")
                }
            }

            Section {
                NavigationLink {
                    OtherEquipmentManagementView()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Manage Other Items")
                                .font(.body.weight(.medium))
                            Text(otherItemsSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            } header: {
                HStack {
                    Label("Other", systemImage: "shippingbox.fill")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                    Spacer()
                }
            } footer: {
                Text("Quad bikes, utes, trailers, pumps, generators, slashers, mulchers, irrigation pumps, workshop tools, and other vineyard assets you maintain.")
            }

            Section {
                ForEach(store.tractors) { tractor in
                    Group {
                        if canManageSetup {
                            Button { editingTractor = tractor } label: { TractorRow(tractor: tractor) }
                        } else {
                            TractorRow(tractor: tractor)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if canManageSetup {
                            Button(role: .destructive) {
                                store.deleteTractor(tractor)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Label("Tractors", systemImage: "truck.pickup.side.fill")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                    Spacer()
                    if canManageSetup {
                        Button {
                            showAddTractorSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.body)
                        }
                    }
                }
            } footer: {
                if canManageSetup {
                    Text("Fuel usage (L/hr) can typically be found in your tractor's user manual under engine specifications.")
                }
            }

            Section {
                ForEach(store.fuelPurchases.sorted(by: { $0.date > $1.date })) { purchase in
                    Group {
                        if canManageSetup {
                            Button { editingFuelPurchase = purchase } label: { FuelPurchaseRow(purchase: purchase) }
                        } else {
                            FuelPurchaseRow(purchase: purchase)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if canManageSetup {
                            Button(role: .destructive) {
                                store.deleteFuelPurchase(purchase)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                if !store.fuelPurchases.isEmpty {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Season Average")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if accessControl?.canViewFinancials ?? false {
                                Text("$\(String(format: "%.2f", store.seasonFuelCostPerLitre))/L")
                                    .font(.headline.bold())
                                    .foregroundStyle(VineyardTheme.olive)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Total Purchased")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            let totalVol = store.fuelPurchases.reduce(0) { $0 + $1.volumeLitres }
                            Text("\(String(format: "%.0f", totalVol)) L")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Label("Fuel Purchases", systemImage: "fuelpump.circle.fill")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                    Spacer()
                    if canManageSetup {
                        Button {
                            showAddFuelSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.body)
                        }
                    }
                }
            } footer: {
                if canManageSetup {
                    Text("Record fuel purchases to calculate an average cost per litre for the season.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Equipment")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if store.sprayEquipment.isEmpty && store.tractors.isEmpty && store.fuelPurchases.isEmpty {
                ContentUnavailableView {
                    Label("No Equipment", systemImage: "wrench.and.screwdriver")
                } description: {
                    Text("Add your spray rigs, tanks, and tractors")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            EquipmentFormSheet(equipment: nil)
        }
        .sheet(item: $editingEquipment) { item in
            EquipmentFormSheet(equipment: item)
        }
        .sheet(isPresented: $showAddTractorSheet) {
            TractorFormSheet(tractor: nil)
        }
        .sheet(item: $editingTractor) { item in
            TractorFormSheet(tractor: item)
        }
        .sheet(isPresented: $showAddFuelSheet) {
            FuelPurchaseFormSheet(purchase: nil)
        }
        .sheet(item: $editingFuelPurchase) { item in
            FuelPurchaseFormSheet(purchase: item)
        }
    }
}

struct EquipmentRow: View {
    let equipment: SprayEquipmentItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(equipment.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Label("\(String(format: "%.0f", equipment.tankCapacityLitres)) L tank", systemImage: "drop.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct TractorRow: View {
    let tractor: Tractor

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(tractor.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Label("\(String(format: "%.1f", tractor.fuelUsageLPerHour)) L/hr fuel usage", systemImage: "fuelpump.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct FuelPurchaseRow: View {
    let purchase: FuelPurchase
    @Environment(\.accessControl) private var accessControl

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if accessControl?.canViewFinancials ?? false {
                    Text("\(String(format: "%.0f", purchase.volumeLitres)) L — $\(String(format: "%.2f", purchase.totalCost))")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                } else {
                    Text("\(String(format: "%.0f", purchase.volumeLitres)) L")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                }
                HStack(spacing: 8) {
                    Label(purchase.date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if accessControl?.canViewFinancials ?? false {
                        Text("$\(String(format: "%.2f", purchase.costPerLitre))/L")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(VineyardTheme.olive)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct EquipmentFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MigratedDataStore.self) private var store

    let equipment: SprayEquipmentItem?

    @State private var name: String = ""
    @State private var tankCapacity: String = ""

    init(equipment: SprayEquipmentItem?) {
        self.equipment = equipment
        if let e = equipment {
            _name = State(initialValue: e.name)
            _tankCapacity = State(initialValue: String(format: "%.0f", e.tankCapacityLitres))
        }
    }

    private var isValid: Bool {
        !name.isEmpty && (Double(tankCapacity) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Equipment Name", text: $name)
                } header: {
                    Text("Equipment Name")
                } footer: {
                    Text("A descriptive name for this spray rig or tank.")
                }

                Section {
                    TextField("e.g. 400", text: $tankCapacity)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Tank Capacity (litres)")
                }
            }
            .navigationTitle(equipment == nil ? "New Equipment" : "Edit Equipment")
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
        let capacity = Double(tankCapacity) ?? 0
        if var existing = equipment {
            existing.name = name
            existing.tankCapacityLitres = capacity
            store.updateSprayEquipment(existing)
        } else {
            store.addSprayEquipment(SprayEquipmentItem(name: name, tankCapacityLitres: capacity))
        }
    }
}

struct TractorFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MigratedDataStore.self) private var store
    @Environment(TractorSyncService.self) private var tractorSync

    let tractor: Tractor?

    @Environment(MigratedDataStore.self) private var storeForAI
    @State private var brand: String = ""
    @State private var model: String = ""
    @State private var modelYearText: String = ""
    @State private var fuelUsage: String = ""
    @State private var fuelLookupLoading: Bool = false
    @State private var fuelLookupError: String?
    @State private var fuelLookupNotes: String?
    @State private var fuelLookupConfidence: String?

    init(tractor: Tractor?) {
        self.tractor = tractor
        if let t = tractor {
            _brand = State(initialValue: t.brand)
            _model = State(initialValue: t.model)
            _modelYearText = State(initialValue: t.modelYear.map { String($0) } ?? "")
            _fuelUsage = State(initialValue: String(format: "%.1f", t.fuelUsageLPerHour))
        }
    }

    private var parsedYear: Int? {
        let trimmed = modelYearText.trimmingCharacters(in: .whitespaces)
        guard let y = Int(trimmed), y >= 1900, y <= 2100 else { return nil }
        return y
    }

    private var isValid: Bool {
        !brand.isEmpty && !model.isEmpty && (Double(fuelUsage) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. John Deere", text: $brand)
                    TextField("e.g. 5075E", text: $model)
                    TextField("e.g. 2018", text: $modelYearText)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Tractor")
                }

                Section {
                    TextField("e.g. 8.5", text: $fuelUsage)
                        .keyboardType(.decimalPad)
                    if storeForAI.settings.aiSuggestionsEnabled {
                        Button {
                            Task { await estimateFuel() }
                        } label: {
                            HStack {
                                if fuelLookupLoading {
                                    ProgressView()
                                    Text("Estimating…")
                                } else {
                                    Label("Estimate Fuel Use", systemImage: "sparkles")
                                }
                            }
                        }
                        .disabled(fuelLookupLoading || brand.trimmingCharacters(in: .whitespaces).isEmpty || model.trimmingCharacters(in: .whitespaces).isEmpty)
                        if let fuelLookupError {
                            Text(fuelLookupError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if let confidence = fuelLookupConfidence, !confidence.isEmpty {
                            Text("Confidence: \(confidence.capitalized)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let notes = fuelLookupNotes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Fuel Usage (L/hr)")
                } footer: {
                    Text("Fuel consumption rate in litres per hour under working load. AI estimates are approximate — actual fuel use varies by load, terrain, implement, speed, and conditions.")
                }
            }
            .navigationTitle(tractor == nil ? "New Tractor" : "Edit Tractor")
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

    @MainActor
    private func estimateFuel() async {
        fuelLookupError = nil
        fuelLookupNotes = nil
        fuelLookupConfidence = nil
        fuelLookupLoading = true
        defer { fuelLookupLoading = false }
        do {
            let result = try await TractorFuelLookupService().lookupFuelUsage(
                brand: brand.trimmingCharacters(in: .whitespaces),
                model: model.trimmingCharacters(in: .whitespaces),
                year: parsedYear
            )
            fuelUsage = String(format: "%.1f", result.fuelUsageLPerHour)
            fuelLookupConfidence = result.confidence
            fuelLookupNotes = result.notes
        } catch {
            fuelLookupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func save() {
        let usage = Double(fuelUsage) ?? 0
        let displayName = "\(brand) \(model)".trimmingCharacters(in: .whitespaces)
        if var existing = tractor {
            existing.brand = brand
            existing.model = model
            existing.modelYear = parsedYear
            existing.name = displayName
            existing.fuelUsageLPerHour = usage
            store.updateTractor(existing)
        } else {
            store.addTractor(Tractor(name: displayName, brand: brand, model: model, modelYear: parsedYear, fuelUsageLPerHour: usage))
        }
        // Push immediately so other devices see the change without waiting for
        // a scene-phase active event or vineyard switch.
        Task { await tractorSync.syncForSelectedVineyard() }
    }
}

struct FuelPurchaseFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MigratedDataStore.self) private var store

    let purchase: FuelPurchase?

    @State private var volumeText: String = ""
    @State private var costText: String = ""
    @State private var date: Date = Date()

    init(purchase: FuelPurchase?) {
        self.purchase = purchase
        if let p = purchase {
            _volumeText = State(initialValue: String(format: "%.0f", p.volumeLitres))
            _costText = State(initialValue: String(format: "%.2f", p.totalCost))
            _date = State(initialValue: p.date)
        }
    }

    private var isValid: Bool {
        (Double(volumeText) ?? 0) > 0 && (Double(costText) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Volume (Litres)") {
                    TextField("e.g. 500", text: $volumeText)
                        .keyboardType(.decimalPad)
                }

                Section("Total Cost ($)") {
                    TextField("e.g. 950.00", text: $costText)
                        .keyboardType(.decimalPad)
                }

                Section {
                    DatePicker("Purchase Date", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle(purchase == nil ? "New Fuel Purchase" : "Edit Fuel Purchase")
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
        let vol = Double(volumeText) ?? 0
        let cost = Double(costText) ?? 0
        if var existing = purchase {
            existing.volumeLitres = vol
            existing.totalCost = cost
            existing.date = date
            store.updateFuelPurchase(existing)
        } else {
            store.addFuelPurchase(FuelPurchase(volumeLitres: vol, totalCost: cost, date: date))
        }
    }
}
