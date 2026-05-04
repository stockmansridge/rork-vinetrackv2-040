import SwiftUI

/// Compact calendar/table view of daily rainfall (mm) for a year.
struct RainfallCalendarView: View {
    @Environment(MigratedDataStore.self) private var store

    @State private var service = RainfallCalendarService()
    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var didInitialLoad = false

    private let dayColumnWidth: CGFloat = 28
    private let monthColumnWidth: CGFloat = 44
    private let cellHeight: CGFloat = 18

    private var latitude: Double? {
        store.settings.vineyardLatitude ?? store.paddockCentroidLatitude
    }
    private var longitude: Double? {
        store.settings.vineyardLongitude ?? store.paddockCentroidLongitude
    }

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                yearControls
                sourceCard
                if latitude == nil || longitude == nil {
                    locationMissing
                } else {
                    calendarTable
                    summarySection
                }
                if let err = service.errorMessage {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Text("mm")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Rainfall Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reload() }
                } label: {
                    if service.isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(service.isLoading)
            }
        }
        .refreshable { await reload() }
        .task {
            if !didInitialLoad {
                didInitialLoad = true
                await reload()
            }
        }
        .onChange(of: year) { _, _ in
            Task { await reload() }
        }
    }

    // MARK: - Year controls

    private var yearControls: some View {
        HStack(spacing: 12) {
            Button {
                year -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)

            VStack(spacing: 2) {
                Text(String(year))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("Year")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button {
                if year < currentYear { year += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .disabled(year >= currentYear)
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(service.providerLabel)
                .font(.footnote.weight(.semibold))
            Text(service.fallbackNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let updated = service.lastUpdated {
                Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if service.isLoading {
                Text("Loading rainfall…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
    }

    private var locationMissing: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No vineyard location set", systemImage: "location.slash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Set your vineyard location in Weather Data & Forecasting setup to load rainfall history.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
    }

    // MARK: - Calendar table

    private var calendarTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                    Divider()
                    ForEach(1...31, id: \.self) { day in
                        dayRow(day: day)
                            .background(day.isMultiple(of: 2) ? Color.clear : Color.black.opacity(0.025))
                    }
                }
                .padding(8)
                .background(Color(.systemBackground), in: .rect(cornerRadius: 10))
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: dayColumnWidth, height: cellHeight, alignment: .center)
            ForEach(1...12, id: \.self) { m in
                Text(monthAbbrev(m))
                    .font(.caption2.weight(.semibold))
                    .frame(width: monthColumnWidth, height: cellHeight, alignment: .center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dayRow(day: Int) -> some View {
        HStack(spacing: 0) {
            Text("\(day)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: dayColumnWidth, height: cellHeight, alignment: .center)
            ForEach(1...12, id: \.self) { m in
                cell(month: m, day: day)
                    .frame(width: monthColumnWidth, height: cellHeight)
            }
        }
    }

    @ViewBuilder
    private func cell(month: Int, day: Int) -> some View {
        let info = cellInfo(month: month, day: day)
        ZStack {
            if let mm = info.mm {
                if mm > 0 {
                    Color.blue.opacity(min(0.55, mm / 30.0))
                }
                Text(formatMm(mm))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(mm >= 10 ? Color.primary : Color.primary.opacity(0.85))
            } else {
                Text("----")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func cellInfo(month: Int, day: Int) -> (valid: Bool, mm: Double?) {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        guard let date = cal.date(from: comps) else { return (false, nil) }
        // Check the constructed day actually matches (catches Feb 30 etc.)
        let real = cal.dateComponents([.year, .month, .day], from: date)
        if real.year != year || real.month != month || real.day != day {
            return (false, nil)
        }
        let today = cal.startOfDay(for: Date())
        if date > today { return (true, nil) }
        let key = cal.startOfDay(for: date)
        return (true, service.dailyRainMm[key])
    }

    private func formatMm(_ mm: Double) -> String {
        // Mirrors the reference style: 05.9, 00.0
        let clamped = max(0, min(mm, 99.9))
        return String(format: "%04.1f", clamped)
    }

    private func monthAbbrev(_ month: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        return f.shortMonthSymbols[month - 1]
    }

    // MARK: - Summary

    private var summarySection: some View {
        let months = RainfallCalendarMath.monthSummaries(year: year, daily: service.dailyRainMm)
        let annual = RainfallCalendarMath.annual(year: year, daily: service.dailyRainMm, months: months)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {
                    summaryRow(label: "TOTALS",     months: months) { mmString($0.totalMm) }
                    summaryRow(label: "Rain days",  months: months) { "\($0.rainDays)" }
                    summaryRow(label: "Wettest day", months: months) {
                        guard let d = $0.wettestDay, let mm = $0.wettestDayMm else { return "—" }
                        return "\(d) (\(mmShort(mm)))"
                    }
                    summaryRow(label: "Average",    months: months) { mmString($0.averageMm) }
                }
                .padding(8)
                .background(Color(.systemBackground), in: .rect(cornerRadius: 10))
            }

            annualCard(annual)
        }
    }

    private func summaryRow(label: String,
                            months: [RainfallMonthSummary],
                            value: (RainfallMonthSummary) -> String) -> some View {
        let values: [(month: Int, text: String)] = months.map { ($0.month, value($0)) }
        return HStack(spacing: 0) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: dayColumnWidth + 60, alignment: .leading)
            ForEach(values, id: \.month) { entry in
                Text(entry.text)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .frame(width: monthColumnWidth, alignment: .center)
            }
        }
    }

    private func annualCard(_ annual: RainfallAnnualSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            statRow("Year total to date", value: mmString(annual.totalMm) + " mm")
            statRow("Rain days (year)", value: "\(annual.rainDays)")
            if let m = annual.wettestMonth, let mm = annual.wettestMonthMm {
                statRow("Wettest month", value: "\(monthAbbrev(m)) (\(mmShort(mm)) mm)")
            }
            if let m = annual.driestMonth, let mm = annual.driestMonthMm {
                statRow("Driest month", value: "\(monthAbbrev(m)) (\(mmShort(mm)) mm)")
            }
            if let date = annual.wettestDay, let mm = annual.wettestDayMm {
                statRow("Wettest day", value: "\(formattedDate(date)) (\(mmShort(mm)) mm)")
            }
            statRow("Av. Year total", value: "—")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func mmString(_ mm: Double) -> String {
        String(format: "%.1f", mm)
    }
    private func mmShort(_ mm: Double) -> String {
        String(format: "%.1f", mm)
    }
    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    // MARK: - Reload

    private func reload() async {
        guard let lat = latitude, let lon = longitude else { return }
        await service.load(
            year: year,
            latitude: lat,
            longitude: lon,
            providerLabel: resolvedProviderLabel()
        )
    }

    private func resolvedProviderLabel() -> String {
        guard let vid = store.selectedVineyardId else {
            return "Source: Automatic Forecast / Historical Weather"
        }
        let status = WeatherProviderResolver.resolve(
            for: vid,
            weatherStationId: store.settings.weatherStationId
        )
        switch status.provider {
        case .davis:
            return "Source: Davis WeatherLink"
        case .wunderground:
            return "Source: Weather Underground"
        case .automatic:
            return "Source: Automatic Forecast / Historical Weather"
        }
    }
}
