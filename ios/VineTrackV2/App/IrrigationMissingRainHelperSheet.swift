import SwiftUI

/// Guided helper that fills missing rainfall days surfaced by the
/// Irrigation Advisor. Runs Davis → Weather Underground → Open-Meteo
/// in priority order using the existing proxies. Owner/Manager only.
struct IrrigationMissingRainHelperSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BackendAccessControl.self) private var accessControl

    let vineyardId: UUID?
    /// The selected actual-rain window in the Irrigation Advisor (1, 2,
    /// 7, 14). Used to inform the user which range was requested.
    let rainfallWindowDays: Int
    /// Called after the helper finishes (success or partial). The
    /// Irrigation Advisor uses this to reload persisted rainfall and
    /// recalculate the recommendation.
    let onCompleted: () -> Void

    @State private var davisConfigured: Bool = false
    @State private var wuConfigured: Bool = false
    @State private var didLoad: Bool = false
    @State private var isLoadingConfig: Bool = false

    @State private var isRunning: Bool = false
    @State private var hasRun: Bool = false

    @State private var davisStatus: StepStatus = .pending
    @State private var davisDetail: String?
    @State private var davisRowsUpserted: Int = 0

    @State private var wuStatus: StepStatus = .pending
    @State private var wuDetail: String?
    @State private var wuRowsUpserted: Int = 0

    @State private var openMeteoStatus: StepStatus = .pending
    @State private var openMeteoDetail: String?
    @State private var openMeteoRowsUpserted: Int = 0

    @State private var finalMessage: String?

    private let integrationRepository: any VineyardWeatherIntegrationRepositoryProtocol
        = SupabaseVineyardWeatherIntegrationRepository()

    private var canEdit: Bool { accessControl.canChangeSettings }

    /// Davis/WU proxies clamp to a 1..60 range. We use the larger of the
    /// selected window or 14 days so a "24h" window still triggers a
    /// useful station backfill.
    private var davisDays: Int { max(rainfallWindowDays, 14) }
    private var wuDays: Int { max(rainfallWindowDays, 14) }
    /// Open-Meteo runs as the broad fallback. 365 days matches the
    /// Settings → Weather Data button so behaviour stays consistent.
    private var openMeteoDays: Int { 365 }

    enum StepStatus: Equatable {
        case pending
        case skipped(String)
        case running
        case success
        case failed
    }

    var body: some View {
        NavigationStack {
            Form {
                introSection
                if !canEdit {
                    readOnlyNoticeSection
                } else {
                    sourcePrioritySection
                    rangeSection
                    stepsSection
                    actionSection
                    if let finalMessage {
                        Section {
                            Text(finalMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Fill missing rainfall data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(hasRun ? "Done" : "Cancel") {
                        if hasRun { onCompleted() }
                        dismiss()
                    }
                    .disabled(isRunning)
                }
            }
            .task {
                if !didLoad { await loadConfiguration() }
            }
        }
    }

    // MARK: - Sections

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "cloud.rain.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                    Text("Fill missing rainfall data")
                        .font(.subheadline.weight(.semibold))
                }
                Text("VineTrack will try to fill missing rainfall days using your configured sources. Better sources are never overwritten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    private var readOnlyNoticeSection: some View {
        Section {
            Label("Ask an Owner or Manager to fill missing rainfall data.", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var sourcePrioritySection: some View {
        Section("Source priority") {
            VStack(alignment: .leading, spacing: 6) {
                priorityRow(index: 1, name: "Manual entries", note: "Always wins. Never overwritten.")
                priorityRow(index: 2, name: "Davis WeatherLink", note: davisConfigured ? "Configured." : "Not configured — will be skipped.")
                priorityRow(index: 3, name: "Weather Underground", note: wuConfigured ? "Configured." : "Not configured — will be skipped.")
                priorityRow(index: 4, name: "Open-Meteo (fallback)", note: "Fills remaining gaps only.")
            }
            .padding(.vertical, 2)
        }
    }

    private func priorityRow(index: Int, name: String, note: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index).")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.caption.weight(.semibold))
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var rangeSection: some View {
        Section {
            LabeledContent("Selected window") {
                Text(windowLabel(rainfallWindowDays))
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Davis / WU range") {
                Text("\(davisDays) days")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Open-Meteo range") {
                Text("\(openMeteoDays) days")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Date ranges")
        } footer: {
            Text("Stations need at least 14 days of history to be useful, so the Davis and Weather Underground steps use 14 days even when a shorter Irrigation Advisor window is selected. Open-Meteo fills the past year of gaps.")
        }
    }

    private var stepsSection: some View {
        Section("Steps") {
            stepRow(
                icon: "antenna.radiowaves.left.and.right",
                title: "Davis WeatherLink",
                status: davisStatus,
                detail: davisDetail
            )
            stepRow(
                icon: "cloud.sun.fill",
                title: "Weather Underground",
                status: wuStatus,
                detail: wuDetail
            )
            stepRow(
                icon: "tray.full.fill",
                title: "Open-Meteo (fallback)",
                status: openMeteoStatus,
                detail: openMeteoDetail
            )
        }
    }

    private func stepRow(icon: String, title: String, status: StepStatus, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                statusBadge(status)
            }
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusBadge(_ status: StepStatus) -> some View {
        switch status {
        case .pending:
            Text("Pending")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        case .skipped:
            Text("Skipped")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        case .running:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Running…")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.tint)
        case .success:
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(VineyardTheme.leafGreen)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                Task { await runAll() }
            } label: {
                HStack {
                    if isRunning {
                        ProgressView()
                        Text("Filling missing data…")
                    } else {
                        Image(systemName: "drop.fill")
                        Text(hasRun ? "Run again" : "Fill missing data now")
                    }
                    Spacer()
                }
                .font(.subheadline.weight(.semibold))
            }
            .disabled(isRunning || isLoadingConfig || vineyardId == nil)
            .buttonStyle(.borderedProminent)
        } footer: {
            Text("Runs Davis, then Weather Underground, then Open-Meteo. Each source only writes its own rows and never overwrites a higher-priority source.")
        }
    }

    // MARK: - Helpers

    private func windowLabel(_ days: Int) -> String {
        switch days {
        case 1: return "24h"
        case 2: return "48h"
        default: return "\(days) days"
        }
    }

    // MARK: - Configuration loading

    private func loadConfiguration() async {
        guard let vid = vineyardId else { return }
        isLoadingConfig = true
        defer { isLoadingConfig = false }
        await VineyardWeatherIntegrationCache.shared.ensureLoaded(for: vid)
        let cfg = WeatherProviderStore.shared.config(for: vid)
        let hasShared = cfg.davisIsVineyardShared && cfg.davisVineyardHasServerCredentials
        let hasStation = (cfg.davisStationId?.isEmpty == false)
        davisConfigured = hasShared && hasStation
        do {
            let integ = try await integrationRepository.fetch(
                vineyardId: vid, provider: "wunderground"
            )
            wuConfigured = !((integ?.stationId ?? "").isEmpty)
        } catch {
            wuConfigured = false
        }
        didLoad = true
    }

    // MARK: - Run

    private func runAll() async {
        guard canEdit, let vid = vineyardId, !isRunning else { return }
        isRunning = true
        finalMessage = nil
        davisStatus = .pending
        wuStatus = .pending
        openMeteoStatus = .pending
        davisDetail = nil
        wuDetail = nil
        openMeteoDetail = nil
        davisRowsUpserted = 0
        wuRowsUpserted = 0
        openMeteoRowsUpserted = 0

        var anyRowsWritten = false

        // Davis
        if davisConfigured {
            await runDavis(vineyardId: vid)
            if davisRowsUpserted > 0 { anyRowsWritten = true }
        } else {
            davisStatus = .skipped("Not configured")
            davisDetail = "Davis WeatherLink isn't configured for this vineyard."
        }

        // Weather Underground
        if wuConfigured {
            await runWunderground(vineyardId: vid)
            if wuRowsUpserted > 0 { anyRowsWritten = true }
        } else {
            wuStatus = .skipped("Not configured")
            wuDetail = "No Weather Underground station saved for this vineyard."
        }

        // Open-Meteo (always attempted as fallback)
        await runOpenMeteo(vineyardId: vid)
        if openMeteoRowsUpserted > 0 { anyRowsWritten = true }

        finalMessage = anyRowsWritten
            ? "Rainfall data refreshed. Recalculating irrigation advice…"
            : "No new rainfall rows were written. Try again later or check Settings → Weather Data & Forecasting."

        if anyRowsWritten {
            NotificationCenter.default.post(
                name: .rainfallCalendarShouldReload, object: nil
            )
        }

        hasRun = true
        isRunning = false
        // Notify the Advisor so it can reload its persisted rainfall and
        // refresh the recommendation card immediately, even before the
        // user dismisses the sheet.
        onCompleted()
    }

    private func runDavis(vineyardId vid: UUID) async {
        davisStatus = .running
        davisDetail = nil
        let cfg = WeatherProviderStore.shared.config(for: vid)
        guard let sid = cfg.davisStationId, !sid.isEmpty else {
            davisStatus = .skipped("No station")
            davisDetail = "No Davis station ID is selected."
            return
        }
        do {
            let r = try await VineyardDavisProxyService.backfillRainfall(
                vineyardId: vid, stationId: sid, days: davisDays
            )
            davisRowsUpserted = r.rowsUpserted
            davisStatus = r.success && r.errorsCount == 0 ? .success : .failed
            davisDetail = "Days requested: \(r.daysRequested) · Processed: \(r.daysProcessed) · Rows upserted: \(r.rowsUpserted) · Errors: \(r.errorsCount)"
        } catch let error as VineyardDavisProxyError {
            davisStatus = .failed
            davisDetail = error.errorDescription ?? "Davis backfill failed."
        } catch {
            davisStatus = .failed
            davisDetail = "Davis backfill failed — \(error.localizedDescription)"
        }
    }

    private func runWunderground(vineyardId vid: UUID) async {
        wuStatus = .running
        wuDetail = nil
        do {
            let r = try await VineyardWundergroundProxyService.backfillRainfall(
                vineyardId: vid, stationId: nil, days: wuDays
            )
            wuRowsUpserted = r.rowsUpserted
            wuStatus = r.success && r.errorsCount == 0 ? .success : .failed
            var parts: [String] = []
            parts.append("Days requested: \(r.daysRequested) · Processed: \(r.daysProcessed) · Rows upserted: \(r.rowsUpserted) · Errors: \(r.errorsCount)")
            if let name = r.stationName, !name.isEmpty {
                parts.append("Station: \(name)")
            } else if let sid = r.stationId, !sid.isEmpty {
                parts.append("Station: \(sid)")
            }
            wuDetail = parts.joined(separator: " · ")
        } catch let error as VineyardWundergroundProxyError {
            wuStatus = .failed
            wuDetail = error.errorDescription ?? "Weather Underground backfill failed."
        } catch {
            wuStatus = .failed
            wuDetail = "Weather Underground backfill failed — \(error.localizedDescription)"
        }
    }

    private func runOpenMeteo(vineyardId vid: UUID) async {
        openMeteoStatus = .running
        openMeteoDetail = nil
        do {
            let r = try await VineyardOpenMeteoProxyService.backfillRainfallGaps(
                vineyardId: vid, days: openMeteoDays, timezone: TimeZone.current.identifier
            )
            openMeteoRowsUpserted = r.rowsUpserted
            openMeteoStatus = r.success && r.errorsCount == 0 ? .success : .failed
            openMeteoDetail = "Rows upserted: \(r.rowsUpserted) · Skipped (better source): \(r.daysSkippedBetterSource) · Skipped (no data): \(r.daysSkippedNoData) · Errors: \(r.errorsCount)"
        } catch let error as VineyardOpenMeteoProxyError {
            openMeteoStatus = .failed
            openMeteoDetail = error.errorDescription ?? "Open-Meteo gap fill failed."
        } catch {
            openMeteoStatus = .failed
            openMeteoDetail = "Open-Meteo gap fill failed — \(error.localizedDescription)"
        }
    }
}
