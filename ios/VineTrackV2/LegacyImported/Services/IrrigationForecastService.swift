import Foundation

nonisolated struct IrrigationForecast: Sendable, Hashable {
    let days: [ForecastDay]
    let source: String
}

@Observable
class IrrigationForecastService {
    var isLoading: Bool = false
    var errorMessage: String?
    var forecast: IrrigationForecast?

    func fetchForecast(latitude: Double, longitude: Double, days: Int = 5) async {
        isLoading = true
        errorMessage = nil
        forecast = nil

        let clampedDays = max(1, min(days, 16))
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&daily=et0_fao_evapotranspiration,precipitation_sum,windspeed_10m_max,temperature_2m_max,temperature_2m_min&forecast_days=\(clampedDays)&timezone=auto&windspeed_unit=kmh"

        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid forecast URL."
            isLoading = false
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                errorMessage = "Failed to fetch forecast (HTTP \(code))."
                isLoading = false
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let daily = json["daily"] as? [String: Any],
                  let times = daily["time"] as? [String],
                  let etoValues = daily["et0_fao_evapotranspiration"] as? [Any],
                  let rainValues = daily["precipitation_sum"] as? [Any] else {
                errorMessage = "Forecast response could not be parsed."
                isLoading = false
                return
            }
            let windValues = daily["windspeed_10m_max"] as? [Any] ?? []
            let tMaxValues = daily["temperature_2m_max"] as? [Any] ?? []
            let tMinValues = daily["temperature_2m_min"] as? [Any] ?? []

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current

            var days: [ForecastDay] = []
            let count = min(times.count, min(etoValues.count, rainValues.count))
            for i in 0..<count {
                guard let date = formatter.date(from: times[i]) else { continue }
                let eto = Self.parseDouble(etoValues[i]) ?? 0
                let rain = Self.parseDouble(rainValues[i]) ?? 0
                let wind = i < windValues.count ? Self.parseDouble(windValues[i]) : nil
                let tMax = i < tMaxValues.count ? Self.parseDouble(tMaxValues[i]) : nil
                let tMin = i < tMinValues.count ? Self.parseDouble(tMinValues[i]) : nil
                days.append(ForecastDay(
                    date: date,
                    forecastEToMm: eto,
                    forecastRainMm: rain,
                    forecastWindKmhMax: wind,
                    forecastTempMaxC: tMax,
                    forecastTempMinC: tMin
                ))
            }

            forecast = IrrigationForecast(days: days, source: "Open-Meteo")
        } catch {
            errorMessage = "Could not load forecast: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private static func parseDouble(_ value: Any) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
