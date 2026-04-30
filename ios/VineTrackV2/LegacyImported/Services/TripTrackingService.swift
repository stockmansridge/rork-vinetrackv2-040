import Foundation
import CoreLocation

/// Backend-neutral live trip tracking service. Keeps the active trip in
/// MigratedDataStore.trips (where isActive == true) and appends GPS points to
/// it as the device location updates. Uses when-in-use location only.
@Observable
@MainActor
final class TripTrackingService {

    // MARK: - Published state

    var isTracking: Bool = false
    var isPaused: Bool = false
    var currentDistance: Double = 0
    var elapsedTime: TimeInterval = 0
    var currentSpeed: Double?
    var errorMessage: String?

    // Row guidance / coverage (live)
    var currentPaddockId: UUID?
    var currentPaddockName: String?
    var currentRowNumber: Double?
    var currentRowDistance: Double?
    var rowsCoveredCount: Int = 0
    var rowGuidanceAvailable: Bool = false

    // MARK: - Dependencies

    private weak var store: MigratedDataStore?
    private weak var locationService: LocationService?

    private var trackingTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?
    private var lastObservedLocation: CLLocation?

    // MARK: - Configuration

    func configure(store: MigratedDataStore, locationService: LocationService) {
        self.store = store
        self.locationService = locationService
        resumeIfNeeded()
    }

    // MARK: - Active trip helpers

    var activeTrip: Trip? {
        store?.trips.first { $0.isActive }
    }

    // MARK: - Start

    func startTrip(
        type: TripType,
        paddockId: UUID?,
        paddockName: String,
        trackingPattern: TrackingPattern = .sequential,
        personName: String = ""
    ) {
        guard let store else { return }
        guard store.selectedVineyardId != nil else {
            errorMessage = "No vineyard selected."
            return
        }
        if activeTrip != nil {
            errorMessage = "A trip is already in progress."
            return
        }

        let trip = Trip(
            paddockId: paddockId,
            paddockName: paddockName,
            paddockIds: paddockId.map { [$0] } ?? [],
            startTime: Date(),
            isActive: true,
            trackingPattern: trackingPattern,
            personName: personName
        )
        store.startTrip(trip)
        errorMessage = nil
        beginTracking()
        _ = type
    }

    // MARK: - Pause / Resume

    func pauseTrip() {
        guard var trip = activeTrip, !trip.isPaused else { return }
        trip.isPaused = true
        trip.pauseTimestamps.append(Date())
        store?.updateTrip(trip)
        isPaused = true
        stopTrackingLoops(stopLocation: false)
    }

    func resumeTrip() {
        guard var trip = activeTrip, trip.isPaused else { return }
        trip.isPaused = false
        trip.resumeTimestamps.append(Date())
        store?.updateTrip(trip)
        isPaused = false
        beginTracking()
    }

    // MARK: - End

    func endTrip() {
        guard let trip = activeTrip else { return }
        store?.endTrip(trip.id)
        stopTrackingLoops(stopLocation: true)
        isTracking = false
        isPaused = false
        currentDistance = 0
        elapsedTime = 0
        currentSpeed = nil
        lastObservedLocation = nil
        currentPaddockId = nil
        currentPaddockName = nil
        currentRowNumber = nil
        currentRowDistance = nil
        rowsCoveredCount = 0
        rowGuidanceAvailable = false
    }

    // MARK: - Manual point

    func addCurrentLocationPoint() {
        guard let location = locationService?.location else { return }
        appendPoint(from: location, force: true)
    }

    // MARK: - Quick pin during trip

    @discardableResult
    func dropPinDuringTrip(
        button: ButtonConfig,
        paddockId: UUID? = nil,
        rowNumber: Int? = nil,
        side: PinSide = .right,
        notes: String? = nil
    ) -> VinePin? {
        guard let store, let trip = activeTrip else { return nil }
        guard let location = locationService?.location else {
            errorMessage = "Waiting for GPS location."
            return nil
        }
        guard var pin = store.createPinFromButton(
            button: button,
            coordinate: location.coordinate,
            heading: locationService?.heading?.trueHeading ?? 0,
            side: side,
            paddockId: paddockId ?? trip.paddockId,
            rowNumber: rowNumber,
            notes: notes
        ) else { return nil }

        pin.tripId = trip.id
        store.updatePin(pin)

        var updatedTrip = trip
        if !updatedTrip.pinIds.contains(pin.id) {
            updatedTrip.pinIds.append(pin.id)
            store.updateTrip(updatedTrip)
        }
        return pin
    }

    // MARK: - Tank workflow

    /// Index of the current open tank session (no endTime). nil if none.
    private func openSessionIndex(in trip: Trip) -> Int? {
        trip.tankSessions.lastIndex(where: { $0.endTime == nil })
    }

    /// Index of the most recent session that has an active fill timer
    /// (fillStartTime set, fillEndTime nil).
    private func openFillIndex(in trip: Trip) -> Int? {
        trip.tankSessions.lastIndex(where: { $0.fillStartTime != nil && $0.fillEndTime == nil })
    }

    /// Start spraying a new tank. If a tank session is already open it is
    /// closed first.
    func startTank() {
        guard var trip = activeTrip else { return }
        if let openIdx = openSessionIndex(in: trip) {
            // If there's an open session that hasn't actually been started
            // (fill-only), reuse it. Otherwise close it.
            let existing = trip.tankSessions[openIdx]
            let hasSpray = existing.fillEndTime != nil || existing.fillStartTime == nil ? false : false
            _ = hasSpray
            // Reuse if it was fill-only (fill recorded, never sprayed)
            if existing.fillStartTime != nil {
                trip.tankSessions[openIdx].startTime = Date()
                trip.tankSessions[openIdx].startRow = currentRowNumber ?? trip.currentRowNumber
                trip.activeTankNumber = existing.tankNumber
                trip.isFillingTank = false
                store?.updateTrip(trip)
                return
            }
            // Otherwise close it
            trip.tankSessions[openIdx].endTime = Date()
            trip.tankSessions[openIdx].endRow = currentRowNumber ?? trip.currentRowNumber
        }
        let nextNumber = (trip.tankSessions.map { $0.tankNumber }.max() ?? 0) + 1
        let session = TankSession(
            tankNumber: nextNumber,
            startTime: Date(),
            startRow: currentRowNumber ?? trip.currentRowNumber
        )
        trip.tankSessions.append(session)
        trip.activeTankNumber = nextNumber
        trip.isFillingTank = false
        store?.updateTrip(trip)
    }

    /// End the currently active tank session.
    func endTank() {
        guard var trip = activeTrip else { return }
        guard let idx = openSessionIndex(in: trip) else { return }
        trip.tankSessions[idx].endTime = Date()
        trip.tankSessions[idx].endRow = currentRowNumber ?? trip.currentRowNumber
        trip.activeTankNumber = nil
        store?.updateTrip(trip)
    }

    /// Start the fill timer for the next (or current) tank.
    func startFillTimer() {
        guard var trip = activeTrip else { return }
        if let idx = openSessionIndex(in: trip) {
            // Tank still open — record fill on it (rare but valid)
            trip.tankSessions[idx].fillStartTime = Date()
            trip.tankSessions[idx].fillEndTime = nil
        } else {
            // Create a new session in fill-only mode
            let nextNumber = (trip.tankSessions.map { $0.tankNumber }.max() ?? 0) + 1
            var session = TankSession(
                tankNumber: nextNumber,
                startTime: Date()
            )
            session.fillStartTime = Date()
            trip.tankSessions.append(session)
            trip.fillingTankNumber = nextNumber
        }
        trip.isFillingTank = true
        store?.updateTrip(trip)
    }

    /// Stop the fill timer. Records fillEndTime on the open fill session.
    func stopFillTimer() {
        guard var trip = activeTrip else { return }
        if let idx = openFillIndex(in: trip) {
            trip.tankSessions[idx].fillEndTime = Date()
        }
        trip.isFillingTank = false
        trip.fillingTankNumber = nil
        store?.updateTrip(trip)
    }

    /// Cancel a running fill timer without recording it.
    func resetFillTimer() {
        guard var trip = activeTrip else { return }
        if let idx = openFillIndex(in: trip) {
            // If the session is fill-only with no spray yet, drop it entirely.
            let session = trip.tankSessions[idx]
            if session.startRow == nil && session.endTime == nil {
                trip.tankSessions.remove(at: idx)
            } else {
                trip.tankSessions[idx].fillStartTime = nil
                trip.tankSessions[idx].fillEndTime = nil
            }
        }
        trip.isFillingTank = false
        trip.fillingTankNumber = nil
        store?.updateTrip(trip)
    }

    // MARK: - Resume after launch

    func resumeIfNeeded() {
        guard activeTrip != nil, !isTracking else { return }
        if activeTrip?.isPaused == true {
            isPaused = true
            return
        }
        beginTracking()
    }

    // MARK: - Internals

    private func beginTracking() {
        guard let locationService else { return }
        let status = locationService.authorizationStatus
        if status == .notDetermined {
            locationService.requestPermission()
        } else if status == .denied || status == .restricted {
            errorMessage = "Location permission is required to track trips."
            return
        } else if status == .authorizedWhenInUse {
            // Ask to upgrade to Always so the trip continues when the screen
            // locks or the user switches apps. Safe to call repeatedly — iOS
            // only shows the prompt once per app install.
            locationService.requestAlwaysPermission()
        }

        locationService.startUpdating()
        locationService.startBackgroundUpdating()
        isTracking = true
        isPaused = false
        lastObservedLocation = locationService.location
        if let trip = activeTrip {
            currentDistance = trip.totalDistance
            elapsedTime = trip.activeDuration
        }

        trackingTask?.cancel()
        let interval = max(0.5, store?.settings.rowTrackingInterval ?? 1.0)
        trackingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self else { return }
                if Task.isCancelled { return }
                await MainActor.run {
                    self.sampleAndAppendPoint()
                }
            }
        }

        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if Task.isCancelled { return }
                await MainActor.run {
                    if let trip = self.activeTrip {
                        self.elapsedTime = trip.activeDuration
                    }
                }
            }
        }
    }

    private func stopTrackingLoops(stopLocation: Bool) {
        trackingTask?.cancel()
        trackingTask = nil
        tickerTask?.cancel()
        tickerTask = nil
        // Always stop background updates when the tracking loop pauses or
        // ends — we only want background location during an active trip.
        locationService?.stopBackgroundUpdating()
        if stopLocation {
            locationService?.stopUpdating()
        }
        isTracking = false
    }

    private func sampleAndAppendPoint() {
        guard let location = locationService?.location else { return }
        appendPoint(from: location, force: false)
    }

    private func appendPoint(from location: CLLocation, force: Bool) {
        guard let store, var trip = activeTrip, !trip.isPaused else { return }

        let newPoint = CoordinatePoint(coordinate: location.coordinate)
        if let last = trip.pathPoints.last {
            let lastLocation = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let segment = location.distance(from: lastLocation)
            if !force && segment < 1.0 { return }
            trip.totalDistance += segment
            trip.pathPoints.append(newPoint)
        } else {
            trip.pathPoints.append(newPoint)
        }

        let rowTrackingEnabled = store.settings.rowTrackingEnabled
        if rowTrackingEnabled {
            updateRowGuidance(for: location.coordinate, trip: &trip, store: store)
        } else {
            currentRowNumber = nil
            currentRowDistance = nil
            rowGuidanceAvailable = false
            rowsCoveredCount = trip.completedPaths.count
        }

        store.updateTrip(trip)
        currentDistance = trip.totalDistance
        currentSpeed = location.speed >= 0 ? location.speed : nil
        lastObservedLocation = location
    }

    // MARK: - Row guidance / coverage

    private func updateRowGuidance(
        for coordinate: CLLocationCoordinate2D,
        trip: inout Trip,
        store: MigratedDataStore
    ) {
        let candidates: [Paddock]
        if let pinned = trip.paddockId,
           let paddock = store.paddocks.first(where: { $0.id == pinned }) {
            candidates = [paddock]
        } else {
            candidates = store.paddocks
        }

        guard let paddock = RowGuidance.paddock(for: coordinate, in: candidates) else {
            currentPaddockId = trip.paddockId
            currentPaddockName = trip.paddockName.isEmpty ? nil : trip.paddockName
            currentRowNumber = nil
            currentRowDistance = nil
            rowGuidanceAvailable = false
            rowsCoveredCount = trip.completedPaths.count
            return
        }

        currentPaddockId = paddock.id
        currentPaddockName = paddock.name
        if !trip.paddockIds.contains(paddock.id) {
            trip.paddockIds.append(paddock.id)
        }

        guard let match = RowGuidance.nearestRow(for: coordinate, in: paddock) else {
            currentRowNumber = nil
            currentRowDistance = nil
            rowGuidanceAvailable = false
            rowsCoveredCount = trip.completedPaths.count
            return
        }

        rowGuidanceAvailable = true
        currentRowNumber = match.rowNumber
        currentRowDistance = match.distance
        trip.currentRowNumber = match.rowNumber

        let threshold = max(0.5, paddock.rowWidth / 2.0)
        if match.distance <= threshold, !trip.completedPaths.contains(match.rowNumber) {
            trip.completedPaths.append(match.rowNumber)
        }
        rowsCoveredCount = trip.completedPaths.count
    }
}
