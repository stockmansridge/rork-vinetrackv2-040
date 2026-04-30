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

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .automotiveNavigation
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
