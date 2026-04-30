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

    func fetchForecast(latitude: Double, longitude: Double) async {
        isLoading = true
        errorMessage = nil
        forecast = nil

        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&daily=et0_fao_evapotranspiration,precipitation_sum&forecast_days=5&timezone=auto"

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

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current

            var days: [ForecastDay] = []
            let count = min(times.count, min(etoValues.count, rainValues.count))
            for i in 0..<count {
                guard let date = formatter.date(from: times[i]) else { continue }
                let eto = Self.parseDouble(etoValues[i]) ?? 0
                let rain = Self.parseDouble(rainValues[i]) ?? 0
                days.append(ForecastDay(date: date, forecastEToMm: eto, forecastRainMm: rain))
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
