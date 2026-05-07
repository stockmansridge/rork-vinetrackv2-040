import Foundation
import CoreLocation

/// Pure helpers for warning when a new pin is being dropped on top of an
/// existing one. Backend-neutral — works with whatever pins are already
/// loaded into `MigratedDataStore.pins`.
nonisolated enum PinDuplicateChecker {

    /// Default fallback radius (metres) when no row-spacing is known.
    /// Sized for typical field GPS error (3-5 m) so two pins placed at the
    /// same vine actually trigger a duplicate warning even when the GPS
    /// fix has drifted between drops.
    static let fallbackRadiusMeters: Double = 3.0

    /// Hard cap on radius. Above this, two pins are clearly different
    /// targets — but this is intentionally generous to account for GPS
    /// noise during active trips at slow speeds.
    static let maxRadiusMeters: Double = 6.0

    /// Minimum radius even when row spacing is known. Prevents very narrow
    /// row paddocks (~1 m spacing) from making duplicates effectively
    /// impossible to detect.
    static let minRadiusMeters: Double = 1.5

    /// Compute the duplicate-warning radius for a pin being dropped at
    /// `coordinate`. Uses half the row spacing of the most relevant paddock
    /// (the one containing the coordinate, falling back to `paddockId`),
    /// or a conservative fallback when geometry isn't available.
    static func duplicateRadius(
        coordinate: CLLocationCoordinate2D,
        paddockId: UUID?,
        paddocks: [Paddock]
    ) -> Double {
        if let containing = RowGuidance.paddock(for: coordinate, in: paddocks),
           containing.rowWidth > 0 {
            return min(maxRadiusMeters, max(minRadiusMeters, containing.rowWidth / 2.0))
        }
        if let id = paddockId,
           let paddock = paddocks.first(where: { $0.id == id }),
           paddock.rowWidth > 0 {
            return min(maxRadiusMeters, max(minRadiusMeters, paddock.rowWidth / 2.0))
        }
        return fallbackRadiusMeters
    }

    /// The closest pin within `radius` of `coordinate`, scoped to the same
    /// vineyard. Active (not-completed) pins are preferred; completed pins
    /// are returned only when no active match exists. Returns `nil` when
    /// no pin is in range.
    static func nearbyPin(
        coordinate: CLLocationCoordinate2D,
        vineyardId: UUID?,
        paddockId: UUID?,
        radius: Double,
        in pins: [VinePin]
    ) -> (pin: VinePin, distance: Double)? {
        var bestActive: (pin: VinePin, distance: Double)?
        var bestDone: (pin: VinePin, distance: Double)?

        for pin in pins {
            if let vid = vineyardId, pin.vineyardId != vid { continue }
            let d = RowGuidance.metresBetween(
                coordinate,
                CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
            )
            guard d <= radius else { continue }

            // Same paddock matches sort first by tightening the radius slightly.
            let scoped: (VinePin, Double) = (pin, d)
            if pin.isCompleted {
                if bestDone == nil || d < bestDone!.distance {
                    bestDone = scoped
                }
            } else {
                if bestActive == nil || d < bestActive!.distance {
                    bestActive = scoped
                }
            }
            _ = paddockId
        }
        return bestActive ?? bestDone
    }
}
