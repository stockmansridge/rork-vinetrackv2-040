import Foundation

/// Pure calculator that estimates labour, fuel and chemical/input cost for a
/// single trip from existing models. No persistence, no UI \u{2014} the caller is
/// responsible for gating display via `canViewCosting` (owner/manager only).
///
/// Inputs intentionally avoid SwiftUI/Observable types so this can be unit
/// tested and reused from reports/exports without dragging in @MainActor.
nonisolated enum TripCostService {

    // MARK: - Output

    nonisolated enum CostingCompleteness: String, Sendable {
        case complete
        case partial
        case unavailable
    }

    nonisolated struct LabourBreakdown: Sendable {
        let categoryName: String?
        let costPerHour: Double?
        let hours: Double
        let cost: Double
        let warning: String?
    }

    nonisolated struct FuelBreakdown: Sendable {
        let tractorName: String?
        let fuelUsageLPerHour: Double?
        let costPerLitre: Double?
        let litres: Double
        let cost: Double
        let warning: String?
    }

    nonisolated struct ChemicalBreakdown: Sendable {
        let cost: Double
        let warning: String?
    }

    nonisolated struct SeedingBreakdown: Sendable {
        let warning: String
    }

    nonisolated struct Result: Sendable {
        let activeHours: Double
        let labour: LabourBreakdown
        let fuel: FuelBreakdown
        let chemical: ChemicalBreakdown?
        let seeding: SeedingBreakdown?
        let totalCost: Double
        let completeness: CostingCompleteness
        let warnings: [String]
    }

    // MARK: - Entry point

    /// Estimate the cost of `trip` using already-resolved supporting data.
    ///
    /// - Parameters:
    ///   - trip: The trip being costed.
    ///   - operatorCategory: Operator category to use for labour cost.
    ///     Resolved by the caller in priority order:
    ///       1. `trip.operatorCategoryId`
    ///       2. `vineyard_members.operator_category_id` for `trip.operatorUserId`
    ///   - tractor: Tractor referenced by `trip.tractorId`, if known.
    ///   - fuelPurchases: All fuel purchases for the vineyard. Used to derive
    ///     a weighted average cost per litre.
    ///   - sprayRecord: Linked spray record (`spray_records.trip_id == trip.id`)
    ///     when one exists. Drives chemical cost.
    static func estimate(
        trip: Trip,
        operatorCategory: OperatorCategory?,
        tractor: Tractor?,
        fuelPurchases: [FuelPurchase],
        sprayRecord: SprayRecord?
    ) -> Result {
        let hours = max(0, trip.activeDuration / 3600.0)

        // ---- Labour ---------------------------------------------------------
        let labour: LabourBreakdown
        if let cat = operatorCategory, cat.costPerHour > 0, hours > 0 {
            labour = LabourBreakdown(
                categoryName: cat.name,
                costPerHour: cat.costPerHour,
                hours: hours,
                cost: cat.costPerHour * hours,
                warning: nil
            )
        } else if let cat = operatorCategory, cat.costPerHour <= 0 {
            labour = LabourBreakdown(
                categoryName: cat.name,
                costPerHour: 0,
                hours: hours,
                cost: 0,
                warning: "Operator category has no hourly rate."
            )
        } else if trip.operatorUserId == nil && trip.operatorCategoryId == nil {
            labour = LabourBreakdown(
                categoryName: nil,
                costPerHour: nil,
                hours: hours,
                cost: 0,
                warning: "No operator assigned to this trip."
            )
        } else {
            labour = LabourBreakdown(
                categoryName: nil,
                costPerHour: nil,
                hours: hours,
                cost: 0,
                warning: "Operator has no category assigned. Set one in Team & Access."
            )
        }

        // ---- Fuel -----------------------------------------------------------
        let weightedCostPerLitre = weightedFuelCostPerLitre(fuelPurchases)
        let fuel: FuelBreakdown
        if let t = tractor, t.fuelUsageLPerHour > 0, hours > 0, let perL = weightedCostPerLitre {
            let litres = t.fuelUsageLPerHour * hours
            fuel = FuelBreakdown(
                tractorName: t.displayName,
                fuelUsageLPerHour: t.fuelUsageLPerHour,
                costPerLitre: perL,
                litres: litres,
                cost: litres * perL,
                warning: nil
            )
        } else if tractor == nil, trip.tractorId == nil {
            fuel = FuelBreakdown(
                tractorName: nil,
                fuelUsageLPerHour: nil,
                costPerLitre: weightedCostPerLitre,
                litres: 0,
                cost: 0,
                warning: "No tractor linked to this trip."
            )
        } else if let t = tractor, t.fuelUsageLPerHour <= 0 {
            fuel = FuelBreakdown(
                tractorName: t.displayName,
                fuelUsageLPerHour: 0,
                costPerLitre: weightedCostPerLitre,
                litres: 0,
                cost: 0,
                warning: "Tractor has no fuel usage (L/hr) configured."
            )
        } else if weightedCostPerLitre == nil {
            fuel = FuelBreakdown(
                tractorName: tractor?.displayName,
                fuelUsageLPerHour: tractor?.fuelUsageLPerHour,
                costPerLitre: nil,
                litres: (tractor?.fuelUsageLPerHour ?? 0) * hours,
                cost: 0,
                warning: "No fuel purchases recorded \u{2014} add one in Equipment to enable fuel cost."
            )
        } else {
            fuel = FuelBreakdown(
                tractorName: tractor?.displayName,
                fuelUsageLPerHour: tractor?.fuelUsageLPerHour,
                costPerLitre: weightedCostPerLitre,
                litres: 0,
                cost: 0,
                warning: "Fuel cost unavailable."
            )
        }

        // ---- Chemical -------------------------------------------------------
        let chemical: ChemicalBreakdown? = sprayRecord.map { record in
            var total: Double = 0
            var anyMissing = false
            var anyPriced = false
            for tank in record.tanks {
                for chem in tank.chemicals {
                    if chem.costPerUnit > 0 {
                        total += chem.costPerTank
                        anyPriced = true
                    } else if chem.volumePerTank > 0 {
                        anyMissing = true
                    }
                }
            }
            let warning: String?
            if !anyPriced && anyMissing {
                warning = "Chemical cost unavailable \u{2014} costs per unit not set on saved chemicals."
            } else if anyMissing {
                warning = "Some chemicals are missing a cost per unit."
            } else {
                warning = nil
            }
            return ChemicalBreakdown(cost: total, warning: warning)
        }

        // ---- Seeding / input -----------------------------------------------
        let seeding: SeedingBreakdown?
        if trip.tripFunction == TripFunction.seeding.rawValue
            || trip.tripFunction == TripFunction.spreading.rawValue
            || trip.tripFunction == TripFunction.fertilising.rawValue {
            seeding = SeedingBreakdown(
                warning: "Seed/input cost unavailable \u{2014} cost per kg not configured."
            )
        } else {
            seeding = nil
        }

        // ---- Total & completeness ------------------------------------------
        let total = labour.cost + fuel.cost + (chemical?.cost ?? 0)

        var warnings: [String] = []
        if let w = labour.warning { warnings.append(w) }
        if let w = fuel.warning { warnings.append(w) }
        if let w = chemical?.warning { warnings.append(w) }
        if let s = seeding { warnings.append(s.warning) }

        let labourOK = labour.warning == nil
        let fuelOK = fuel.warning == nil
        // Chemical is optional: only counts against completeness if a spray
        // record exists at all.
        let chemicalOK = chemical?.warning == nil
        let completeness: CostingCompleteness
        if labourOK && fuelOK && chemicalOK && seeding == nil {
            completeness = .complete
        } else if total > 0 || labourOK || fuelOK || chemicalOK {
            completeness = .partial
        } else {
            completeness = .unavailable
        }

        return Result(
            activeHours: hours,
            labour: labour,
            fuel: fuel,
            chemical: chemical,
            seeding: seeding,
            totalCost: total,
            completeness: completeness,
            warnings: warnings
        )
    }

    // MARK: - Helpers

    /// Weighted average fuel cost per litre across all fuel purchases for a
    /// vineyard: `sum(total_cost) / sum(volume_litres)`. Returns nil when no
    /// purchases with a positive volume exist.
    static func weightedFuelCostPerLitre(_ purchases: [FuelPurchase]) -> Double? {
        let totalCost = purchases.reduce(0) { $0 + $1.totalCost }
        let totalVolume = purchases.reduce(0) { $0 + $1.volumeLitres }
        guard totalVolume > 0 else { return nil }
        return totalCost / totalVolume
    }
}
