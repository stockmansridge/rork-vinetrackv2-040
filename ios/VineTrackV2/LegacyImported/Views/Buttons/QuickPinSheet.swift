import SwiftUI
import CoreLocation

struct QuickPinSheet: View {
    @Environment(MigratedDataStore.self) private var store
    @Environment(NewBackendAuthService.self) private var auth
    @Environment(LocationService.self) private var locationService
    @Environment(BackendAccessControl.self) private var accessControl
    @Environment(\.dismiss) private var dismiss

    @State private var mode: PinMode = .repairs
    @State private var selectedButtonId: UUID?
    @State private var selectedPaddockId: UUID?
    @State private var rowText: String = ""
    @State private var side: PinSide = .right
    @State private var notes: String = ""
    @State private var showGrowthPicker: Bool = false
    @State private var pendingGrowthButton: ButtonConfig?
    @State private var errorMessage: String?

    private var canCreate: Bool { accessControl.canCreateOperationalRecords }

    private var activeButtons: [ButtonConfig] {
        let all = mode == .repairs ? store.repairButtons : store.growthButtons
        // Show only one button per row (first 4 by index)
        return all.sorted { $0.index < $1.index }.prefix(4).map { $0 }
    }

    private var selectedButton: ButtonConfig? {
        guard let id = selectedButtonId else { return nil }
        return activeButtons.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !canCreate {
                    Section {
                        Label("You do not have permission to create pins.", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Mode") {
                    Picker("Mode", selection: $mode) {
                        ForEach(PinMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _, _ in
                        selectedButtonId = nil
                    }
                }

                Section("Button") {
                    if activeButtons.isEmpty {
                        Text("No buttons configured for this mode.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeButtons) { button in
                            Button {
                                selectedButtonId = button.id
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color.fromString(button.color).gradient)
                                        .frame(width: 24, height: 24)
                                    Text(button.name)
                                        .foregroundStyle(.primary)
                                    if button.isGrowthStageButton {
                                        GrapeLeafIcon(size: 12, color: .green)
                                    }
                                    Spacer()
                                    if selectedButtonId == button.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(VineyardTheme.leafGreen)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Location") {
                    Picker("Paddock", selection: $selectedPaddockId) {
                        Text("None").tag(UUID?.none)
                        ForEach(store.paddocks) { paddock in
                            Text(paddock.name).tag(UUID?.some(paddock.id))
                        }
                    }
                    HStack {
                        Text("Row")
                        Spacer()
                        TextField("Optional", text: $rowText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    Picker("Side", selection: $side) {
                        Text("Left").tag(PinSide.left)
                        Text("Right").tag(PinSide.right)
                    }
                    .pickerStyle(.segmented)

                    if let coord = locationService.location?.coordinate {
                        LabeledContent("Coordinates", value: String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                            .font(.caption)
                    } else {
                        Label("Waiting for GPS…", systemImage: "location.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Quick Pin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Drop") { handleDrop() }
                        .disabled(!canDrop)
                }
            }
            .sheet(isPresented: $showGrowthPicker) {
                GrowthStagePickerSheet { stage in
                    handleGrowthStageSelected(stage)
                }
            }
        }
    }

    private var canDrop: Bool {
        canCreate && selectedButton != nil && locationService.location != nil
    }

    private func handleDrop() {
        guard canCreate else { return }
        guard let button = selectedButton else { return }
        guard let location = locationService.location else {
            errorMessage = "Waiting for GPS location."
            return
        }

        if mode == .growth && button.isGrowthStageButton {
            pendingGrowthButton = button
            showGrowthPicker = true
            return
        }

        createPin(button: button, location: location)
    }

    private func handleGrowthStageSelected(_ stage: GrowthStage) {
        guard let location = locationService.location else { return }
        let rowNumber = Int(rowText.trimmingCharacters(in: .whitespacesAndNewlines))
        store.createGrowthStagePin(
            stageCode: stage.code,
            stageDescription: stage.description,
            coordinate: location.coordinate,
            heading: locationService.heading?.trueHeading ?? 0,
            side: side,
            paddockId: selectedPaddockId,
            rowNumber: rowNumber,
            createdBy: auth.userName,
            notes: notes.isEmpty ? nil : notes
        )
        dismiss()
    }

    private func createPin(button: ButtonConfig, location: CLLocation) {
        let rowNumber = Int(rowText.trimmingCharacters(in: .whitespacesAndNewlines))
        store.createPinFromButton(
            button: button,
            coordinate: location.coordinate,
            heading: locationService.heading?.trueHeading ?? 0,
            side: side,
            paddockId: selectedPaddockId,
            rowNumber: rowNumber,
            createdBy: auth.userName,
            notes: notes.isEmpty ? nil : notes
        )
        dismiss()
    }
}
