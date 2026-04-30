import SwiftUI

struct AddEditMaintenanceLogView: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(NewBackendAuthService.self) private var auth
    @Environment(\.accessControl) private var accessControl
    @Environment(\.dismiss) private var dismiss

    let existingLog: MaintenanceLog?

    @State private var itemName: String = ""
    @State private var showCustomItem: Bool = false
    @State private var customItemName: String = ""
    @State private var hours: String = ""
    @State private var workCompleted: String = ""
    @State private var partsUsed: String = ""
    @State private var partsCost: String = ""
    @State private var labourCost: String = ""
    @State private var date: Date = Date()
    @State private var invoicePhotoData: Data?
    @State private var photoChanged: Bool = false
    @State private var showCamera: Bool = false
    @State private var showPhotoSource: Bool = false
    @State private var showDeleteAlert: Bool = false

    private var isEditing: Bool { existingLog != nil }
    private var canViewFinancials: Bool { accessControl?.canViewFinancials ?? false }
    private var canDelete: Bool { accessControl?.canDelete ?? false }

    init(existingLog: MaintenanceLog? = nil) {
        self.existingLog = existingLog
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item / Machine") {
                    Menu {
                        if !store.tractors.isEmpty {
                            Section("Tractors") {
                                ForEach(store.tractors) { tractor in
                                    Button(tractor.displayName) {
                                        itemName = tractor.displayName
                                        showCustomItem = false
                                    }
                                }
                            }
                        }
                        if !store.sprayEquipment.isEmpty {
                            Section("Equipment") {
                                ForEach(store.sprayEquipment) { eq in
                                    Button(eq.name) {
                                        itemName = eq.name
                                        showCustomItem = false
                                    }
                                }
                            }
                        }
                        Divider()
                        Button {
                            showCustomItem = true
                            itemName = customItemName
                        } label: {
                            Label("Custom…", systemImage: "pencil")
                        }
                    } label: {
                        HStack {
                            Text(itemName.isEmpty ? "Select item" : itemName)
                                .foregroundStyle(itemName.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if showCustomItem {
                        TextField("e.g. Water Pump", text: $customItemName)
                            .onChange(of: customItemName) { _, newValue in
                                itemName = newValue
                            }
                    }
                }

                Section("Service Details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    HStack {
                        Text("Hours")
                        Spacer()
                        TextField("0", text: $hours)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }

                Section("Work Completed") {
                    TextField("Describe work completed...", text: $workCompleted, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Parts Used") {
                    TextField("List parts used...", text: $partsUsed, axis: .vertical)
                        .lineLimit(2...5)
                }

                if canViewFinancials {
                    Section("Costs") {
                        HStack {
                            Text("Parts Cost")
                            Spacer()
                            Text(currencySymbol)
                                .foregroundStyle(.secondary)
                            TextField("0.00", text: $partsCost)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        HStack {
                            Text("Labour Cost")
                            Spacer()
                            Text(currencySymbol)
                                .foregroundStyle(.secondary)
                            TextField("0.00", text: $labourCost)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        HStack {
                            Text("Total")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(computedTotal, format: .currency(code: currencyCode))
                                .fontWeight(.semibold)
                                .foregroundStyle(VineyardTheme.earthBrown)
                        }
                    }
                }

                Section("Invoice Photo") {
                    if let photoData = invoicePhotoData, let uiImage = UIImage(data: photoData) {
                        VStack(spacing: 12) {
                            Color(.secondarySystemBackground)
                                .frame(height: 200)
                                .overlay {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .allowsHitTesting(false)
                                }
                                .clipShape(.rect(cornerRadius: 12))

                            HStack {
                                Button {
                                    showPhotoSource = true
                                } label: {
                                    Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.subheadline)
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    withAnimation {
                                        invoicePhotoData = nil
                                        photoChanged = true
                                    }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                        .font(.subheadline)
                                }
                            }
                        }
                    } else {
                        Button {
                            showPhotoSource = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(VineyardTheme.earthBrown.gradient, in: .rect(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Add Invoice Photo")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("Take a photo or choose from library")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if isEditing && canDelete {
                    Section {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Delete Record", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Record" : "New Maintenance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveLog() }
                        .fontWeight(.semibold)
                        .disabled(itemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Add Photo", isPresented: $showPhotoSource) {
                Button("Take Photo") {
                    showCamera = true
                }
                Button("Choose from Library") {
                    showCamera = true
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraImagePicker { data in
                    if let data {
                        invoicePhotoData = data
                        photoChanged = true
                    }
                }
                .ignoresSafeArea()
            }
            .alert("Delete Record", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let log = existingLog {
                        store.deleteMaintenanceLog(log.id)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this maintenance record?")
            }
            .onAppear {
                if let log = existingLog {
                    itemName = log.itemName
                    let matchesTractor = store.tractors.contains { $0.displayName == log.itemName }
                    let matchesEquipment = store.sprayEquipment.contains { $0.name == log.itemName }
                    if !matchesTractor && !matchesEquipment && !log.itemName.isEmpty {
                        showCustomItem = true
                        customItemName = log.itemName
                    }
                    hours = log.hours > 0 ? String(format: "%.1f", log.hours) : ""
                    workCompleted = log.workCompleted
                    partsUsed = log.partsUsed
                    partsCost = log.partsCost > 0 ? String(format: "%.2f", log.partsCost) : ""
                    labourCost = log.labourCost > 0 ? String(format: "%.2f", log.labourCost) : ""
                    date = log.date
                    invoicePhotoData = log.invoicePhotoData
                }
            }
        }
    }

    private var computedTotal: Double {
        (Double(partsCost) ?? 0) + (Double(labourCost) ?? 0)
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var currencySymbol: String {
        Locale.current.currencySymbol ?? "$"
    }

    private func saveLog() {
        let trimmedName = itemName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        var log = existingLog ?? MaintenanceLog()
        log.itemName = trimmedName
        log.hours = Double(hours) ?? 0
        log.workCompleted = workCompleted.trimmingCharacters(in: .whitespacesAndNewlines)
        log.partsUsed = partsUsed.trimmingCharacters(in: .whitespacesAndNewlines)
        log.partsCost = Double(partsCost) ?? 0
        log.labourCost = Double(labourCost) ?? 0
        log.date = date
        log.invoicePhotoData = invoicePhotoData
        // If the photo changed (added, replaced, or removed), clear the synced
        // path so MaintenanceLogSyncService re-uploads or drops it on next sync.
        if photoChanged {
            log.photoPath = nil
        }
        let userName = auth.userName ?? ""
        log.createdBy = userName.isEmpty ? nil : userName

        if isEditing {
            store.updateMaintenanceLog(log)
        } else {
            store.addMaintenanceLog(log)
        }
        dismiss()
    }
}
