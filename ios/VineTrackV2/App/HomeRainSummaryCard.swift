import SwiftUI

/// Compact, read-only rain summary shown at the top of the Home → Today
/// section. Displays today's rain (midnight → now) and a simple summary of
/// meaningful forecast rain in the next 7 days.
///
/// Operationally important for spraying / irrigation / seeding decisions but
/// intentionally does NOT feed into vineyard health or alert severity.
struct HomeRainSummaryCard: View {
    @Environment(MigratedDataStore.self) private var store

    @State private var todayMm: Double?
    @State private var forecastDays: [ForecastDay] = []
    @State private var hasLoadedForecast: Bool = false
    @State private var isLoading: Bool = false

    private var latitude: Double? {
        store.settings.vineyardLatitude ?? store.paddockCentroidLatitude
    }

    private var longitude: Double? {
        store.settings.vineyardLongitude ?? store.paddockCentroidLongitude
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: "cloud.rain.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(todayLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(forecastLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.18), lineWidth: 1)
        )
        .padding(.horizontal)
        .task(id: store.selectedVineyardId) { await load() }
    }

    // MARK: - Display

    private var todayLine: String {
        guard let mm = todayMm else { return "Rain data unavailable" }
        if mm <= 0 {
            return "Today's rain: 0 mm"
        }
        return String(format: "Today's rain: %.1f mm", mm)
    }

    private var forecastLine: String {
        guard hasLoadedForecast else { return "Loading 7-day rain forecast…" }
        return Self.summarize(days: forecastDays)
    }

    // MARK: - Load

    private func load() async {
        guard let vid = store.selectedVineyardId else {
            todayMm = nil
            forecastDays = []
            hasLoadedForecast = false
            return
        }
        isLoading = true
        defer { isLoading = false }

        // Today's rain — prefer the cached current-weather snapshot
        // (matches the Davis / Wunderground number the rest of the app uses).
        var todayResolved: Double?
        if let snap = try? await WeatherCurrentService().fetchCachedCurrent(vineyardId: vid),
           let r = snap.rainTodayMm {
            todayResolved = r
        }
        // Fallback: persisted daily rainfall row for today.
        if todayResolved == nil {
            let cal = Calendar.current
            let start = cal.startOfDay(for: Date())
            if let rows = try? await PersistedRainfallService.fetchDailyRainfall(
                vineyardId: vid, from: start, to: start
            ), let r = rows.first?.rainfallMm {
                todayResolved = r
            }
        }
        todayMm = todayResolved

        // 7-day forecast rain (Open-Meteo).
        if let lat = latitude, let lon = longitude {
            let svc = IrrigationForecastService()
            await svc.fetchForecast(latitude: lat, longitude: lon, days: 7)
            forecastDays = svc.forecast?.days ?? []
            hasLoadedForecast = true
        } else {
            forecastDays = []
            hasLoadedForecast = true
        }
    }

    // MARK: - Forecast summary

    /// Build a short, scannable summary of meaningful rain in the next 7 days.
    /// Ignores tiny amounts (<1 mm) unless nothing else is forecast.
    static func summarize(days: [ForecastDay]) -> String {
        guard !days.isEmpty else { return "Rain forecast unavailable" }
        let threshold = 1.0
        let meaningful = days.filter { $0.forecastRainMm >= threshold }
        guard !meaningful.isEmpty else {
            return "No significant rain in next 7 days"
        }
        // Pick the first meaningful event (most operationally relevant).
        // If a much larger event is later in the window, mention it too.
        let first = meaningful.first!
        let largest = meaningful.max(by: { $0.forecastRainMm < $1.forecastRainMm }) ?? first
        if largest.date != first.date, largest.forecastRainMm >= first.forecastRainMm + 2 {
            return String(
                format: "Rain: %.1f mm %@ · %.1f mm %@",
                first.forecastRainMm, relativeDay(first.date),
                largest.forecastRainMm, relativeDay(largest.date)
            )
        }
        return String(
            format: "Rain forecast: %.1f mm %@",
            first.forecastRainMm, relativeDay(first.date)
        )
    }

    private static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "today" }
        if cal.isDateInTomorrow(date) { return "tomorrow" }
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }
}
