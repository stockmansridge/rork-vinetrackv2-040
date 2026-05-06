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

    /// Smoothed ground speed in m/s, derived from CLLocation.speed when valid
    /// and otherwise from the recent point window. Use this instead of
    /// `locationService.location?.speed` to avoid the half-speed dropout that
    /// CoreLocation's automotive smoothing applied at slow tractor speeds.
    var smoothedSpeed: Double = 0
    private var recentSpeedSamples: [(date: Date, location: CLLocation)] = []

    // MARK: - Dependencies

    private weak var store: MigratedDataStore?
    private weak var locationService: LocationService?

    private var trackingTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?
    private var lastObservedLocation: CLLocation?

    // Path-distance tracking for auto path completion (global path → metres).
    private var pathDistanceMap: [Double: Double] = [:]
    private var lastTrackingLocation: CLLocation?

    // Cached GlobalRowIndex per selected paddock-id set. Built once per
    // selection change instead of every GPS tick.
    private var cachedRowIndex: GlobalRowIndex?
    private var cachedRowIndexKey: [UUID] = []

    // Hard cap on retained recent-speed samples in addition to the time window.
    private let maxRecentSpeedSamples: Int = 30

    // Cooldown to prevent the same path completing twice in quick succession.
    private var lastAutoCompletePath: Double?
    private var lastAutoCompleteAt: Date?
    private let autoCompleteCooldown: TimeInterval = 2.5

    // MARK: - Diagnostics (DEBUG only)
    #if DEBUG
    private(set) var diagLocationUpdateCount: Int = 0
    private(set) var diagAutoCompleteFiredCount: Int = 0
    private(set) var diagSequenceIndexChanges: Int = 0
    private(set) var diagRowIndexBuildCount: Int = 0
    private var lastDiagLogAt: Date = .distantPast
    private func breadcrumb(_ message: @autoclosure () -> String) {
        print("[ActiveTrip] \(message())")
    }
    #else
    @inline(__always) private func breadcrumb(_ message: @autoclosure () -> String) {}
    #endif

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
        personName: String = "",
        tripFunction: String? = nil,
        tripTitle: String? = nil
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
            personName: personName,
            tripFunction: tripFunction,
            tripTitle: tripTitle
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
        smoothedSpeed = 0
        recentSpeedSamples.removeAll()
        pathDistanceMap.removeAll()
        lastTrackingLocation = nil
        cachedRowIndex = nil
        cachedRowIndexKey = []
        lastAutoCompletePath = nil
        lastAutoCompleteAt = nil
        breadcrumb("endTrip")
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
        breadcrumb("beginTracking")
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
        #if DEBUG
        diagLocationUpdateCount += 1
        #endif

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
        updateSmoothedSpeed(from: location)
        currentSpeed = smoothedSpeed > 0 ? smoothedSpeed : nil
        lastObservedLocation = location
    }

    private func updateSmoothedSpeed(from location: CLLocation) {
        let now = Date()
        recentSpeedSamples.append((now, location))
        // Keep ~5s of recent samples, with a hard cap as a safety net.
        recentSpeedSamples.removeAll { now.timeIntervalSince($0.date) > 5 }
        if recentSpeedSamples.count > maxRecentSpeedSamples {
            recentSpeedSamples.removeFirst(recentSpeedSamples.count - maxRecentSpeedSamples)
        }

        // Prefer a fresh, valid CLLocation.speed (m/s) when available.
        if location.speed >= 0, location.timestamp.timeIntervalSinceNow > -2 {
            // Light blend with previous reading to avoid jitter without
            // averaging over the full trip.
            if smoothedSpeed > 0 {
                smoothedSpeed = smoothedSpeed * 0.4 + location.speed * 0.6
            } else {
                smoothedSpeed = location.speed
            }
            return
        }

        // Fallback: derive from the recent sample window.
        if let first = recentSpeedSamples.first {
            let dt = now.timeIntervalSince(first.date)
            let dist = location.distance(from: first.location)
            if dt > 0.5, dist > 0 {
                smoothedSpeed = dist / dt
                return
            }
        }
        smoothedSpeed = 0
    }

    // MARK: - Row guidance / coverage

    private func updateRowGuidance(
        for coordinate: CLLocationCoordinate2D,
        trip: inout Trip,
        store: MigratedDataStore
    ) {
        // Resolve all selected paddocks for this trip (multi-block aware).
        var selectedIds: [UUID] = trip.paddockIds
        if selectedIds.isEmpty, let id = trip.paddockId { selectedIds = [id] }
        let selected = selectedIds.compactMap { id in
            store.paddocks.first(where: { $0.id == id })
        }
        let candidates: [Paddock] = selected.isEmpty ? store.paddocks : selected

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

        // Convert local row hit → global path number that lines up with
        // trip.rowSequence (which uses combined multi-block paths from
        // StartTripSheet). The index is cached per selection so we don't
        // rebuild it on every GPS tick.
        let index = rowIndex(for: candidates)
        let localRow = Int(match.rowNumber)
        let globalRow = index.globalRow(paddockId: paddock.id, localRow: localRow)
            ?? localRow

        // Detected live path snapped to the X.5 grid that's closest to the
        // current sequence path. May or may not equal the current sequence
        // path — that's exactly what we use to gate auto-completion.
        let livePath = livePathForSequence(
            globalRow: globalRow,
            sequence: trip.rowSequence,
            currentPath: trip.currentRowNumber
        ) ?? (Double(globalRow) - 0.5)

        rowGuidanceAvailable = true
        currentRowDistance = match.distance

        // The current intended path is what the operator is meant to be
        // driving — it is NOT changed just because the GPS happens to be
        // near a different row. This is critical for maintenance trips
        // where the operator may pass through off-cycle paths without
        // intending to complete them.
        let currentSequencePath: Double? = trip.rowSequence.indices.contains(trip.sequenceIndex)
            ? trip.rowSequence[trip.sequenceIndex]
            : nil

        // Path-match tolerance: livePath is snapped to the .5 grid, so an
        // exact equality is the right physical comparison. We still compare
        // with a small epsilon for FP safety.
        let pathMatch: Bool = {
            guard let target = currentSequencePath else { return false }
            return abs(livePath - target) < 0.01
        }()

        // Show the live GPS path on the row indicator regardless of match,
        // but keep `trip.currentRowNumber` pinned to the planned path so
        // the trip header / summary stays on the intended row.
        currentRowNumber = livePath
        if let target = currentSequencePath {
            trip.currentRowNumber = target
        } else {
            trip.currentRowNumber = livePath
        }

        // Only accumulate distance along the *current planned* path, and
        // only when the live GPS is actually on that path. Driving an
        // off-cycle path contributes zero progress to the planned path.
        if pathMatch, let target = currentSequencePath {
            accumulateDistanceAlong(path: target, location: locationService?.location)

            // Auto-complete only when we are physically near the planned
            // row centreline and have covered enough of its length.
            let proximity = max(0.5, paddock.rowWidth / 2.0)
            if match.distance <= proximity {
                let didComplete = finalizeIfThresholdMet(
                    path: target,
                    trip: &trip,
                    paddock: paddock,
                    rowWidth: paddock.rowWidth,
                    location: locationService?.location
                )
                if didComplete {
                    advanceSequenceAfterCompletion(trip: &trip)
                }
            }
        } else {
            // Off-cycle: reset last tracking location so the next valid
            // on-path tick doesn't accumulate the off-path distance.
            lastTrackingLocation = locationService?.location
        }

        #if DEBUG
        let acc = currentSequencePath.map { pathDistanceMap[$0, default: 0] } ?? 0
        let len = currentSequencePath.flatMap { rowLength(forPath: $0, paddock: paddock) } ?? 0
        let pct = len > 0 ? (acc / len * 100) : 0
        breadcrumb(
            "row currentSeq=\(currentSequencePath.map { String($0) } ?? "nil") " +
            "livePath=\(livePath) match=\(pathMatch) " +
            "len=\(String(format: "%.1f", len))m acc=\(String(format: "%.1f", acc))m " +
            "pct=\(String(format: "%.0f", pct))%"
        )
        #endif

        rowsCoveredCount = trip.completedPaths.count
        #if DEBUG
        if Date().timeIntervalSince(lastDiagLogAt) > 10 {
            lastDiagLogAt = Date()
            breadcrumb(
                "diag updates=\(diagLocationUpdateCount) trailPts=\(trip.pathPoints.count) " +
                "autoCompletes=\(diagAutoCompleteFiredCount) seqChanges=\(diagSequenceIndexChanges) " +
                "rowIndexBuilds=\(diagRowIndexBuildCount) selectedPaddocks=\(candidates.count)"
            )
        }
        #endif
    }

    private func rowIndex(for candidates: [Paddock]) -> GlobalRowIndex {
        let key = candidates.map(\.id)
        if let cached = cachedRowIndex, key == cachedRowIndexKey {
            return cached
        }
        let built = GlobalRowIndex(paddocks: candidates)
        cachedRowIndex = built
        cachedRowIndexKey = key
        #if DEBUG
        diagRowIndexBuildCount += 1
        breadcrumb("rowIndex rebuilt entries=\(built.entries.count) totalRows=\(built.totalRows)")
        #endif
        return built
    }

    /// Choose the path (X-0.5 or X+0.5) for a detected global row that lies
    /// inside the active row sequence and is closest to the current path.
    private func livePathForSequence(
        globalRow: Int,
        sequence: [Double],
        currentPath: Double
    ) -> Double? {
        guard !sequence.isEmpty else { return nil }
        let candidates = [Double(globalRow) - 0.5, Double(globalRow) + 0.5]
        let set = Set(sequence)
        let matches = candidates.filter { set.contains($0) }
        if matches.isEmpty { return nil }
        return matches.min(by: { abs($0 - currentPath) < abs($1 - currentPath) })
    }

    private func accumulateDistanceAlong(path: Double, location: CLLocation?) {
        guard let location else { return }
        defer { lastTrackingLocation = location }
        guard let last = lastTrackingLocation else { return }
        let segment = location.distance(from: last)
        // Reject GPS jumps and noise.
        guard segment > 0.5, segment < 50 else { return }
        pathDistanceMap[path, default: 0] += segment
    }

    /// Rows shorter than this are considered "short" and use a more
    /// forgiving auto-completion rule that accounts for GPS drift, turning
    /// radius and slow tractor speed at the row ends.
    private let shortRowThresholdMetres: Double = 25.0

    /// Advance the planned sequence to the next pending path after the
    /// current one auto-completes. Skips any entries that are already
    /// marked completed/skipped so we never get stuck.
    private func advanceSequenceAfterCompletion(trip: inout Trip) {
        guard !trip.rowSequence.isEmpty else { return }
        var next = trip.sequenceIndex + 1
        while next < trip.rowSequence.count {
            let candidate = trip.rowSequence[next]
            if !trip.completedPaths.contains(candidate),
               !trip.skippedPaths.contains(candidate) { break }
            next += 1
        }
        let clamped = min(next, trip.rowSequence.count - 1)
        if clamped != trip.sequenceIndex {
            #if DEBUG
            diagSequenceIndexChanges += 1
            breadcrumb("sequenceIndex \(trip.sequenceIndex) -> \(clamped) (auto-complete advance)")
            #endif
            trip.sequenceIndex = clamped
            trip.currentRowNumber = trip.rowSequence[clamped]
            if clamped + 1 < trip.rowSequence.count {
                trip.nextRowNumber = trip.rowSequence[clamped + 1]
            } else {
                trip.nextRowNumber = trip.rowSequence[clamped]
            }
        }
    }

    @discardableResult
    private func finalizeIfThresholdMet(
        path: Double,
        trip: inout Trip,
        paddock: Paddock,
        rowWidth: Double,
        location: CLLocation?
    ) -> Bool {
        guard !trip.completedPaths.contains(path),
              !trip.skippedPaths.contains(path) else { return false }

        // Cooldown: never auto-complete the same path twice within a few
        // seconds, even if upstream calls us repeatedly.
        if let last = lastAutoCompletePath, last == path,
           let lastAt = lastAutoCompleteAt,
           Date().timeIntervalSince(lastAt) < autoCompleteCooldown {
            return false
        }

        let accumulated = pathDistanceMap[path, default: 0]
        let length = rowLength(forPath: path, paddock: paddock)

        var ruleUsed: String
        var requiredDistance: Double
        var didComplete = false

        if let length, length > 1 {
            if length <= shortRowThresholdMetres {
                // Short-row rule: complete on either
                //  • ~60 % of the row length covered (min 4 m), OR
                //  • operator is within ~3 m of either row end.
                ruleUsed = "shortRow"
                requiredDistance = max(4.0, length * 0.6)
                let nearEnd = isNearPathEnd(path: path, paddock: paddock, location: location, tolerance: 3.0)
                if accumulated >= requiredDistance || nearEnd {
                    trip.completedPaths.append(path)
                    didComplete = true
                }
            } else {
                // Long-row rule: original 80 % progress threshold.
                ruleUsed = "longRow"
                requiredDistance = length * 0.8
                if accumulated >= requiredDistance {
                    trip.completedPaths.append(path)
                    didComplete = true
                }
            }
        } else {
            // Fallback: no usable geometry length — 10 m of accumulation.
            ruleUsed = "fallback"
            requiredDistance = 10.0
            if accumulated >= requiredDistance {
                trip.completedPaths.append(path)
                didComplete = true
            }
        }

        if didComplete {
            lastAutoCompletePath = path
            lastAutoCompleteAt = Date()
            #if DEBUG
            diagAutoCompleteFiredCount += 1
            #endif
        }

        #if DEBUG
        let lengthStr = length.map { String(format: "%.1f", $0) } ?? "nil"
        print(
            "[TripAutoComplete] path=\(path) rowLength=\(lengthStr)m rule=\(ruleUsed) " +
            "required=\(String(format: "%.1f", requiredDistance))m " +
            "accumulated=\(String(format: "%.1f", accumulated))m " +
            "autoComplete=\(didComplete)"
        )
        #endif
        return didComplete
    }

    private func isNearPathEnd(
        path: Double,
        paddock: Paddock,
        location: CLLocation?,
        tolerance: Double
    ) -> Bool {
        guard let location else { return false }
        let neighbours = [Int(floor(path)), Int(ceil(path))]
        for number in neighbours {
            guard let row = paddock.rows.first(where: { $0.number == number }) else { continue }
            let start = CLLocation(latitude: row.startPoint.latitude, longitude: row.startPoint.longitude)
            let end = CLLocation(latitude: row.endPoint.latitude, longitude: row.endPoint.longitude)
            if location.distance(from: start) <= tolerance { return true }
            if location.distance(from: end) <= tolerance { return true }
        }
        return false
    }

    private func rowLength(forPath path: Double, paddock: Paddock) -> Double? {
        // Path X.5 sits between rows X and X+1 — use either neighbour for length.
        let neighbours = [Int(floor(path)), Int(ceil(path))]
        for number in neighbours {
            if let row = paddock.rows.first(where: { $0.number == number }) {
                let a = CLLocation(latitude: row.startPoint.latitude, longitude: row.startPoint.longitude)
                let b = CLLocation(latitude: row.endPoint.latitude, longitude: row.endPoint.longitude)
                let length = a.distance(from: b)
                if length > 1 { return length }
            }
        }
        return nil
    }
}
