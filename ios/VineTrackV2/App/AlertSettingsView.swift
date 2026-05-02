import SwiftUI

struct AlertSettingsView: View {
    @Environment(AlertService.self) private var alertService
    @Environment(MigratedDataStore.self) private var store
    @Environment(BackendAccessControl.self) private var accessControl
    @Environment(\.dismiss) private var dismiss

    @State private var draft: BackendAlertPreferences?
    @State private var isSaving: Bool = false

    private var canEdit: Bool { accessControl.canChangeSettings }

    var body: some View {
        Form {
            if let prefs = draft {
                editor(prefs)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Alerts & Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(!canEdit || draft == nil || isSaving)
            }
        }
        .task {
            if draft == nil {
                if let existing = alertService.preferences {
                    draft = existing
                } else if let vid = store.selectedVineyardId {
                    draft = BackendAlertPreferences.defaults(for: vid)
                }
            }
        }
    }

    @ViewBuilder
    private func editor(_ prefs: BackendAlertPreferences) -> some View {
        let binding = Binding<BackendAlertPreferences>(
            get: { draft ?? prefs },
            set: { draft = $0 }
        )

        Section {
            Toggle("Aged pin alerts", isOn: binding.agedPinAlertsEnabled)
                .disabled(!canEdit)
            Stepper(
                "Age threshold: \(binding.wrappedValue.agedPinDays) days",
                value: binding.agedPinDays,
                in: 1...60
            )
            .disabled(!canEdit || !binding.wrappedValue.agedPinAlertsEnabled)
        } header: {
            Text("Pins")
        } footer: {
            Text("Notify when unresolved pins are older than this threshold.")
        }

        Section {
            Toggle("Irrigation alerts", isOn: binding.irrigationAlertsEnabled)
                .disabled(!canEdit)
            Stepper(
                "Forecast window: \(binding.wrappedValue.irrigationForecastDays) days",
                value: binding.irrigationForecastDays,
                in: 1...14
            )
            .disabled(!canEdit || !binding.wrappedValue.irrigationAlertsEnabled)
            HStack {
                Text("Deficit threshold (mm)")
                Spacer()
                TextField("mm", value: binding.irrigationDeficitThresholdMm, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .disabled(!canEdit || !binding.wrappedValue.irrigationAlertsEnabled)
            }
        } header: {
            Text("Irrigation")
        } footer: {
            Text("Trigger when calculated deficit over the forecast window exceeds this amount.")
        }

        Section {
            Toggle("Weather alerts", isOn: binding.weatherAlertsEnabled)
                .disabled(!canEdit)
            HStack {
                Text("Rain (mm)")
                Spacer()
                TextField("mm", value: binding.rainAlertThresholdMm, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .disabled(!canEdit || !binding.wrappedValue.weatherAlertsEnabled)
            }
            HStack {
                Text("Wind (km/h)")
                Spacer()
                TextField("km/h", value: binding.windAlertThresholdKmh, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .disabled(!canEdit || !binding.wrappedValue.weatherAlertsEnabled)
            }
            HStack {
                Text("Frost below (°C)")
                Spacer()
                TextField("°C", value: binding.frostAlertThresholdC, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .disabled(!canEdit || !binding.wrappedValue.weatherAlertsEnabled)
            }
            HStack {
                Text("Heat above (°C)")
                Spacer()
                TextField("°C", value: binding.heatAlertThresholdC, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .disabled(!canEdit || !binding.wrappedValue.weatherAlertsEnabled)
            }
        } header: {
            Text("Weather")
        }

        Section {
            Toggle("Spray job reminders", isOn: binding.sprayJobRemindersEnabled)
                .disabled(!canEdit)
        } header: {
            Text("Spray")
        } footer: {
            Text("Reminders for scheduled spray records due today or tomorrow.")
        }

        Section {
            Toggle("Push notifications", isOn: binding.pushEnabled)
                .disabled(true)
        } header: {
            Text("Push")
        } footer: {
            Text("Push notifications coming soon. In-app alerts are active.")
        }

        if !canEdit {
            Section {
                Text("Only the vineyard owner or manager can change alert preferences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func save() async {
        guard canEdit, let prefs = draft else { return }
        isSaving = true
        defer { isSaving = false }
        await alertService.savePreferences(prefs)
        dismiss()
    }
}
