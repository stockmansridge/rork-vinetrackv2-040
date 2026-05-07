import Foundation
import CoreLocation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var location: CLLocation?
    var heading: CLHeading?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var isUsingMockLocation: Bool = false
    private var mockFallbackTask: Task<Void, Never>?

    private(set) var isBackgroundUpdatingEnabled: Bool = false
    private(set) var isHighAccuracyEnabled: Bool = false

    /// Maximum age (seconds) before a cached GPS fix is considered stale
    /// for pin creation. Anything older than this should trigger a warning
    /// rather than silently saving a bad pin.
    static let staleLocationThreshold: TimeInterval = 5.0

    /// Minimum acceptable horizontal accuracy (metres) for pin creation.
    /// Above this we still allow the drop but show a warning so the
    /// operator can wait for a better fix if they want to.
    static let lowAccuracyThreshold: Double = 15.0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        // .other works better than .automotiveNavigation for slow-moving
        // tractors — the automotive activity type applies aggressive
        // smoothing/filtering at low speeds which halves the reported speed
        // after a short distance.
        manager.activityType = .other
        manager.distanceFilter = kCLDistanceFilterNone
        authorizationStatus = manager.authorizationStatus
        applySimulatorMockLocationIfNeeded()
    }

    private func applySimulatorMockLocationIfNeeded() {
        #if targetEnvironment(simulator)
        let mock = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: -41.2865, longitude: 174.7762),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            timestamp: Date()
        )
        self.location = mock
        self.isUsingMockLocation = true
        #endif
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Request Always permission. iOS will only show the upgrade prompt if
    /// the app already has When-In-Use authorization. Call this when the user
    /// starts a trip so they understand the context.
    func requestAlwaysPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            return
        }
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    /// Enable background location updates. Only valid while an active trip is
    /// running. Requires UIBackgroundModes = location and either When-In-Use
    /// or Always authorization.
    func startBackgroundUpdating() {
        guard !isBackgroundUpdatingEnabled else { return }
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        isBackgroundUpdatingEnabled = true
    }

    /// Disable background location updates. Call as soon as a trip ends or is
    /// cancelled to stop draining battery and respect user privacy.
    func stopBackgroundUpdating() {
        guard isBackgroundUpdatingEnabled else { return }
        manager.allowsBackgroundLocationUpdates = false
        isBackgroundUpdatingEnabled = false
    }

    /// Switch to highest-practical GPS accuracy for active trips. Uses
    /// `kCLLocationAccuracyBestForNavigation` so live row guidance and
    /// pin placement get the freshest, most accurate fix the device can
    /// provide. Restored to `kCLLocationAccuracyBest` once the trip ends
    /// to preserve battery during normal app use.
    func enableHighAccuracyForActiveTrip() {
        guard !isHighAccuracyEnabled else { return }
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        isHighAccuracyEnabled = true
    }

    func disableHighAccuracy() {
        guard isHighAccuracyEnabled else { return }
        manager.desiredAccuracy = kCLLocationAccuracyBest
        isHighAccuracyEnabled = false
    }

    /// Returns true if the latest fix is recent enough and accurate enough
    /// to safely use for pin placement. Use `freshLocation()` instead when
    /// you need the actual coordinate plus the freshness/accuracy verdict.
    func isLocationFreshEnough() -> Bool {
        guard let loc = location else { return false }
        let age = -loc.timestamp.timeIntervalSinceNow
        return age <= Self.staleLocationThreshold && loc.horizontalAccuracy >= 0
    }

    enum LocationQuality {
        case fresh
        case stale
        case lowAccuracy
        case unavailable
    }

    /// Inspect the latest fix and return both the location and a quality
    /// verdict so callers can decide whether to warn before creating a pin.
    func freshLocation() -> (location: CLLocation?, quality: LocationQuality) {
        guard let loc = location else { return (nil, .unavailable) }
        let age = -loc.timestamp.timeIntervalSinceNow
        if age > Self.staleLocationThreshold { return (loc, .stale) }
        if loc.horizontalAccuracy < 0 || loc.horizontalAccuracy > Self.lowAccuracyThreshold {
            return (loc, .lowAccuracy)
        }
        return (loc, .fresh)
    }

    func startUpdating() {
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        scheduleSimulatorMockFallback()
    }

    private func scheduleSimulatorMockFallback() {
        #if targetEnvironment(simulator)
        applySimulatorMockLocationIfNeeded()
        #endif
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        stopBackgroundUpdating()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in
            guard let last else { return }
            self.location = last
            self.isUsingMockLocation = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            self.heading = newHeading
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.startUpdatingLocation()
                manager.startUpdatingHeading()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
