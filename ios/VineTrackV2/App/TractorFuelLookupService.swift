import Foundation

nonisolated struct FuelLookupResult: Sendable {
    let fuelUsageLPerHour: Double
    let confidence: String?
    let notes: String?
}

nonisolated struct TractorFuelLookupService: Sendable {

    func lookupFuelUsage(brand: String, model: String, year: Int? = nil) async throws -> FuelLookupResult {
        guard AppConfig.isSupabaseConfigured else { throw ChemicalLookupError.notConfigured }
        let base = AppConfig.supabaseURL.absoluteString
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/functions/v1/tractor-fuel-lookup") else {
            throw ChemicalLookupError.network("Invalid edge function URL")
        }
        let anonKey = AppConfig.supabaseAnonKey
        guard !anonKey.isEmpty else { throw ChemicalLookupError.notConfigured }

        var payload: [String: Any] = [
            "brand": brand,
            "model": model,
        ]
        if let year { payload["year"] = year }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ChemicalLookupError.network("No HTTP response")
        }
        if !(200..<300).contains(http.statusCode) {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = obj["error"] as? String {
                if msg.contains("OPENAI_API_KEY") {
                    throw ChemicalLookupError.missingProviderKey
                }
                throw ChemicalLookupError.network(msg)
            }
            throw ChemicalLookupError.network("HTTP \(http.statusCode)")
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = (obj["fuelUsageLPerHour"] as? Double)
                ?? (obj["fuelUsageLPerHour"] as? NSNumber)?.doubleValue,
              value > 0 else {
            throw ChemicalLookupError.parseFailed
        }
        return FuelLookupResult(
            fuelUsageLPerHour: value,
            confidence: obj["confidence"] as? String,
            notes: obj["notes"] as? String
        )
    }
}
