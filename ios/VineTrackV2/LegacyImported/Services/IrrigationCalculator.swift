import Foundation

nonisolated struct ForecastDay: Sendable, Hashable, Identifiable {
    let date: Date
    let forecastEToMm: Double
    let forecastRainMm: Double
    let forecastWindKmhMax: Double?
    let forecastTempMaxC: Double?
    let forecastTempMinC: Double?

    var id: Date { date }

    init(
        date: Date,
        forecastEToMm: Double,
        forecastRainMm: Double,
        forecastWindKmhMax: Double? = nil,
        forecastTempMaxC: Double? = nil,
        forecastTempMinC: Double? = nil
    ) {
        self.date = date
        self.forecastEToMm = forecastEToMm
        self.forecastRainMm = forecastRainMm
        self.forecastWindKmhMax = forecastWindKmhMax
        self.forecastTempMaxC = forecastTempMaxC
        self.forecastTempMinC = forecastTempMinC
    }
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
    /// Recent measured/actual rainfall fed into the calculation as a soil
    /// moisture credit. Zero when no actual-rain offset is applied.
    let recentActualRainMm: Double
    let netDeficitMm: Double
    let grossIrrigationMm: Double
    let recommendedIrrigationHours: Double
    let recommendedIrrigationMinutes: Int
}

nonisolated enum IrrigationCalculator {
    static func calculate(
        forecastDays: [ForecastDay],
        settings: IrrigationSettings,
        recentActualRainMm: Double = 0
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

        // Subtract recent measured rainfall (capped at calc deficit) before
        // soil-buffer offset, so users with Davis stations don't over-irrigate
        // after a recent storm.
        let actualRainOffset = max(0, recentActualRainMm * (settings.rainfallEffectivenessPercent / 100.0))
        let adjustedNetDeficitMm = max(0, totalDeficit - settings.soilMoistureBufferMm - actualRainOffset)
        let targetNetIrrigationMm = adjustedNetDeficitMm * replacement
        let grossIrrigationMm = targetNetIrrigationMm / irrEff
        let hours = grossIrrigationMm / settings.irrigationApplicationRateMmPerHour
        let minutes = Int((hours * 60.0).rounded())

        return IrrigationRecommendationResult(
            dailyBreakdown: breakdown,
            forecastCropUseMm: totalCropUse,
            forecastEffectiveRainMm: totalEffectiveRain,
            recentActualRainMm: actualRainOffset,
            netDeficitMm: adjustedNetDeficitMm,
            grossIrrigationMm: grossIrrigationMm,
            recommendedIrrigationHours: hours,
            recommendedIrrigationMinutes: minutes
        )
    }
}
