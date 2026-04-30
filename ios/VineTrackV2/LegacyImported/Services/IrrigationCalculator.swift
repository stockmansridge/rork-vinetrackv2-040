import Foundation

nonisolated struct ForecastDay: Sendable, Hashable, Identifiable {
    let date: Date
    let forecastEToMm: Double
    let forecastRainMm: Double

    var id: Date { date }
}

nonisolated struct IrrigationSettings: Sendable, Hashable {
    var irrigationApplicationRateMmPerHour: Double
    var cropCoefficientKc: Double
    var irrigationEfficiencyPercent: Double
    var rainfallEffectivenessPercent: Double
    var replacementPercent: Double
    var soilMoistureBufferMm: Double

    static let defaults = IrrigationSettings(
        irrigationApplicationRateMmPerHour: 0,
        cropCoefficientKc: 0.65,
        irrigationEfficiencyPercent: 90,
        rainfallEffectivenessPercent: 80,
        replacementPercent: 100,
        soilMoistureBufferMm: 0
    )
}

nonisolated struct DailyIrrigationBreakdown: Sendable, Hashable, Identifiable {
    let date: Date
    let forecastEToMm: Double
    let forecastRainMm: Double
    let cropUseMm: Double
    let effectiveRainMm: Double
    let dailyDeficitMm: Double

    var id: Date { date }
}

nonisolated struct IrrigationRecommendationResult: Sendable, Hashable {
    let dailyBreakdown: [DailyIrrigationBreakdown]
    let forecastCropUseMm: Double
    let forecastEffectiveRainMm: Double
    let netDeficitMm: Double
    let grossIrrigationMm: Double
    let recommendedIrrigationHours: Double
    let recommendedIrrigationMinutes: Int
}

nonisolated enum IrrigationCalculator {
    static func calculate(
        forecastDays: [ForecastDay],
        settings: IrrigationSettings
    ) -> IrrigationRecommendationResult? {
        guard !forecastDays.isEmpty else { return nil }
        guard settings.irrigationApplicationRateMmPerHour > 0 else { return nil }

        let kc = settings.cropCoefficientKc
        let rainEff = settings.rainfallEffectivenessPercent / 100.0
        let irrEff = max(settings.irrigationEfficiencyPercent / 100.0, 0.0001)
        let replacement = settings.replacementPercent / 100.0

        var breakdown: [DailyIrrigationBreakdown] = []
        var totalCropUse: Double = 0
        var totalEffectiveRain: Double = 0
        var totalDeficit: Double = 0

        for day in forecastDays {
            let cropUseMm = day.forecastEToMm * kc
            let rawEffectiveRain = day.forecastRainMm * rainEff
            let effectiveRainMm = day.forecastRainMm < 2.0 ? 0 : rawEffectiveRain
            let dailyDeficitMm = max(0, cropUseMm - effectiveRainMm)

            breakdown.append(DailyIrrigationBreakdown(
                date: day.date,
                forecastEToMm: day.forecastEToMm,
                forecastRainMm: day.forecastRainMm,
                cropUseMm: cropUseMm,
                effectiveRainMm: effectiveRainMm,
                dailyDeficitMm: dailyDeficitMm
            ))

            totalCropUse += cropUseMm
            totalEffectiveRain += effectiveRainMm
            totalDeficit += dailyDeficitMm
        }

        let adjustedNetDeficitMm = max(0, totalDeficit - settings.soilMoistureBufferMm)
        let targetNetIrrigationMm = adjustedNetDeficitMm * replacement
        let grossIrrigationMm = targetNetIrrigationMm / irrEff
        let hours = grossIrrigationMm / settings.irrigationApplicationRateMmPerHour
        let minutes = Int((hours * 60.0).rounded())

        return IrrigationRecommendationResult(
            dailyBreakdown: breakdown,
            forecastCropUseMm: totalCropUse,
            forecastEffectiveRainMm: totalEffectiveRain,
            netDeficitMm: adjustedNetDeficitMm,
            grossIrrigationMm: grossIrrigationMm,
            recommendedIrrigationHours: hours,
            recommendedIrrigationMinutes: minutes
        )
    }
}
