import SwiftUI
import MapKit
import CoreLocation

/// Restored original-style active trip screen. Backend-neutral: uses
/// `MigratedDataStore` and `TripTrackingService` only.
struct ActiveTripView: View {
    let trip: Trip

    @Environment(MigratedDataStore.self) private var store
    @Environment(TripTrackingService.self) private var tracking
    @Environment(LocationService.self) private var locationService
    @Environment(BackendAccessControl.self) private var accessControl

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var isFollowingUser: Bool = true
    @State private var showRowIndicator: Bool = true
    @State private var showEndConfirmation: Bool = false
    @State private var showSummary: Bool = false
    @State private var showRepairs: Bool = false
    @State private var showGrowth: Bool = false
    @State private var elapsedTimer: TimeInterval = 0
    @State private var ticker: Timer?
    @State private var fillElapsed: TimeInterval = 0
    @State private var showEndTankConfirmation: Bool = false

    private var sprayRecord: SprayRecord? {
        store.sprayRecords.first { $0.tripId == trip.id }
    }

    private var currentPaddock: Paddock? {
        if let id = trip.paddockId,
           let paddock = store.paddocks.first(where: { $0.id == id }) {
            return paddock
        }
        for id in trip.paddockIds {
            if let paddock = store.paddocks.first(where: { $0.id == id }) {
                return paddock
            }
        }
        if let liveId = tracking.currentPaddockId {
            return store.paddocks.first(where: { $0.id == liveId })
        }
        return nil
    }

    private var paddocksOnMap: [Paddock] {
        var ids = Set<UUID>()
        if let id = trip.paddockId { ids.insert(id) }
        ids.formUnion(trip.paddockIds)
        if let liveId = tracking.currentPaddockId { ids.insert(liveId) }
        return store.paddocks.filter { ids.contains($0.id) }
    }

    private var displayPath: Double? {
        if let row = tracking.currentRowNumber { return row }
        if !trip.rowSequence.isEmpty { return trip.currentRowNumber }
        return nil
    }

    private var nextPath: Double? {
        guard !trip.rowSequence.isEmpty else { return nil }
        let next = trip.sequenceIndex + 1
        if next < trip.rowSequence.count {
            return trip.rowSequence[next]
        }
        return nil
    }

    private var leftRowNumber: Int {
        let path = displayPath ?? trip.currentRowNumber
        return Int(ceil(path))
    }

    private var rightRowNumber: Int {
        let path = displayPath ?? trip.currentRowNumber
        return Int(floor(path))
    }

    private var currentSpeedKmh: Double {
        guard let speed = locationService.location?.speed, speed > 0 else { return 0 }
        return speed * 3.6
    }

    var body: some View {
        VStack(spacing: 0) {
            tripInfoBar

            ZStack(alignment: .topTrailing) {
                mapView

                VStack(spacing: 8) {
                    Button {
                        withAnimation(.snappy) {
                            isFollowingUser = true
                            position = .userLocation(fallback: .automatic)
                        }
                    } label: {
                        Image(systemName: isFollowingUser ? "location.fill" : "location")
                            .font(.title3)
                            .foregroundStyle(isFollowingUser ? Color.accentColor : .primary)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: .circle)
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.snappy) {
                            showRowIndicator.toggle()
                        }
                    } label: {
                        Image(systemName: showRowIndicator ? "arrow.left.and.right.circle.fill" : "arrow.left.and.right.circle")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: .circle)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)

                if showRowIndicator, tracking.rowGuidanceAvailable, store.settings.rowTrackingEnabled {
                    rowIndicatorOverlay
                }
            }

            if store.settings.rowTrackingEnabled {
                currentRowBanner
            } else {
                rowTrackingDisabledBanner
            }

            if let record = sprayRecord {
                sprayBanner(record: record)
                tankControls(record: record)
            }

            tripControls
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(currentPaddock?.name ?? (trip.paddockName.isEmpty ? "Active Trip" : trip.paddockName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f km/h", currentSpeedKmh))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: currentSpeedKmh)
                }
            }
        }
        .sheet(isPresented: $showSummary) {
            TripSummarySheet(trip: trip)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showRepairs) {
            NavigationStack { RepairsGrowthView(initial: .repairs) }
        }
        .sheet(isPresented: $showGrowth) {
            NavigationStack { RepairsGrowthView(initial: .growth) }
        }
        .onAppear {
            elapsedTimer = trip.activeDuration
            startTicker()
        }
        .onDisappear {
            ticker?.invalidate()
            ticker = nil
        }
        .onMapCameraChange { _ in
            isFollowingUser = false
        }
    }

    // MARK: - Top info bar

    private var tripInfoBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    showRepairs = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin").font(.caption)
                        Text("Repairs").font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.15), in: .rect(cornerRadius: 8))
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .disabled(!accessControl.canCreateOperationalRecords)

                Button {
                    showGrowth = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin").font(.caption)
                        Text("Growth").font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(VineyardTheme.leafGreen.opacity(0.15), in: .rect(cornerRadius: 8))
                    .foregroundStyle(VineyardTheme.leafGreen)
                }
                .buttonStyle(.plain)
                .disabled(!accessControl.canCreateOperationalRecords)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemGroupedBackground))

            HStack(spacing: 0) {
                statColumn(label: "CURRENT PATH",
                           value: formatPath(displayPath),
                           tint: Color.accentColor,
                           liveIndicator: tracking.rowGuidanceAvailable && tracking.currentRowNumber != nil)

                Divider().frame(height: 40)

                statColumn(label: "NEXT PATH",
                           value: formatPath(nextPath),
                           tint: .primary,
                           liveIndicator: false)

                Divider().frame(height: 40)

                VStack(spacing: 4) {
                    Text("DISTANCE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(formatDistance(tracking.currentDistance))
                        .font(.system(.headline, design: .monospaced))
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 40)

                VStack(spacing: 4) {
                    HStack(spacing: 3) {
                        Text("DURATION")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        if trip.isPaused {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(formatDuration(elapsedTimer))
                        .font(.system(.headline, design: .monospaced))
                        .foregroundStyle(trip.isPaused ? .orange : .primary)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)

            if !trip.rowSequence.isEmpty {
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: trip.trackingPattern.icon).font(.caption2)
                        Text(trip.trackingPattern.title).font(.caption2.weight(.medium))
                        Spacer()
                        Text("\(trip.sequenceIndex + 1) of \(trip.rowSequence.count)")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                    ProgressView(
                        value: Double(min(trip.sequenceIndex + 1, trip.rowSequence.count)),
                        total: Double(max(trip.rowSequence.count, 1))
                    )
                    .tint(Color.accentColor)
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func statColumn(label: String, value: String, tint: Color, liveIndicator: Bool) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                if liveIndicator {
                    Image(systemName: "location.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(VineyardTheme.leafGreen)
                }
            }
            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Map

    private var mapView: some View {
        Map(position: $position) {
            ForEach(paddocksOnMap) { paddock in
                if paddock.polygonPoints.count >= 3 {
                    MapPolygon(coordinates: paddock.polygonPoints.map { $0.coordinate })
                        .foregroundStyle(VineyardTheme.leafGreen.opacity(0.15))
                        .stroke(VineyardTheme.leafGreen.opacity(0.7), lineWidth: 1.5)
                }
                ForEach(paddock.rows, id: \.id) { row in
                    MapPolyline(coordinates: [row.startPoint.coordinate, row.endPoint.coordinate])
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                }
            }

            if trip.pathPoints.count > 1 {
                MapPolyline(coordinates: trip.pathPoints.map { $0.coordinate })
                    .stroke(Color.yellow, lineWidth: 4)
            }

            ForEach(store.pins.filter { $0.tripId == trip.id }) { pin in
                Annotation(pin.buttonName, coordinate: pin.coordinate) {
                    Circle()
                        .fill(Color.fromString(pin.buttonColor))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(radius: 1)
                }
            }

            UserAnnotation()
        }
        .mapStyle(.hybrid)
    }

    private var rowIndicatorOverlay: some View {
        HStack {
            VStack(spacing: 4) {
                Image(systemName: "arrow.left").font(.caption2.weight(.bold))
                Text("Row \(leftRowNumber)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
            }
            .frame(width: 70, height: 60)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
            .padding(.leading, 12)

            Spacer()

            VStack(spacing: 4) {
                Image(systemName: "arrow.right").font(.caption2.weight(.bold))
                Text("Row \(rightRowNumber)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
            }
            .frame(width: 70, height: 60)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: - Banners

    private var rowTrackingDisabledBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.slash.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("ROW TRACKING DISABLED")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("GPS path is still recording. Enable row tracking in Preferences for live row guidance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                showSummary = true
            } label: {
                Image(systemName: "list.bullet.clipboard")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var currentRowBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.fill")
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("CURRENT PATH")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text("Path \(formatPath(displayPath))")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .contentTransition(.numericText())
                    if let blockName = currentPaddock?.name {
                        Text("• \(blockName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Button {
                showSummary = true
            } label: {
                Image(systemName: "list.bullet.clipboard")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func sprayBanner(record: SprayRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sprinkler.and.droplets.fill")
                .font(.title3)
                .foregroundStyle(VineyardTheme.leafGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.sprayReference.isEmpty ? "Spray Record" : record.sprayReference)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(record.tanks.count) tank\(record.tanks.count == 1 ? "" : "s") • \(record.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            NavigationLink {
                SprayRecordDetailView(record: record)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(VineyardTheme.leafGreen.opacity(0.08))
    }

    // MARK: - Trip controls

    private var tripControls: some View {
        HStack(spacing: 12) {
            if !trip.rowSequence.isEmpty && !trip.isPaused {
                Button {
                    advanceRow(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 50, height: 50)
                }
                .buttonStyle(.bordered)
                .disabled(trip.sequenceIndex <= 0)

                Button {
                    advanceRow(by: 1)
                } label: {
                    Label("Next Path", systemImage: "chevron.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(trip.sequenceIndex >= trip.rowSequence.count - 1)
            } else if trip.isPaused {
                HStack(spacing: 8) {
                    Image(systemName: "pause.fill").foregroundStyle(.orange)
                    Text("Trip Paused")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(VineyardTheme.leafGreen)
                    Text(tracking.rowGuidanceAvailable ? "GPS Tracking Active" : "Waiting for GPS")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            Button {
                withAnimation(.snappy) {
                    if trip.isPaused {
                        tracking.resumeTrip()
                    } else {
                        tracking.pauseTrip()
                    }
                }
            } label: {
                Image(systemName: trip.isPaused ? "play.fill" : "pause.fill")
                    .font(.headline)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.bordered)
            .tint(trip.isPaused ? .green : .orange)
            .sensoryFeedback(.impact, trigger: trip.isPaused)

            Button {
                showEndConfirmation = true
            } label: {
                Image(systemName: "stop.fill")
                    .font(.headline)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .confirmationDialog("End Trip?", isPresented: $showEndConfirmation) {
                Button("End Trip", role: .destructive) {
                    ticker?.invalidate()
                    ticker = nil
                    tracking.endTrip()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will stop tracking and finalise the trip.")
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Helpers

    private func advanceRow(by delta: Int) {
        guard !trip.rowSequence.isEmpty else { return }
        let newIndex = trip.sequenceIndex + delta
        guard newIndex >= 0 && newIndex < trip.rowSequence.count else { return }
        var updated = trip
        let oldPath = updated.currentRowNumber
        if delta > 0,
           !updated.completedPaths.contains(oldPath),
           !updated.skippedPaths.contains(oldPath) {
            updated.completedPaths.append(oldPath)
        }
        updated.sequenceIndex = newIndex
        updated.currentRowNumber = updated.rowSequence[newIndex]
        if newIndex + 1 < updated.rowSequence.count {
            updated.nextRowNumber = updated.rowSequence[newIndex + 1]
        } else {
            updated.nextRowNumber = updated.currentRowNumber
        }
        store.updateTrip(updated)
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                if let active = tracking.activeTrip {
                    elapsedTimer = active.activeDuration
                    if let session = active.tankSessions.last(where: { $0.fillStartTime != nil && $0.fillEndTime == nil }),
                       let start = session.fillStartTime {
                        fillElapsed = Date().timeIntervalSince(start)
                    } else {
                        fillElapsed = 0
                    }
                }
            }
        }
    }

    // MARK: - Tank controls

    private var liveTrip: Trip {
        tracking.activeTrip ?? trip
    }

    private var openTankSession: TankSession? {
        liveTrip.tankSessions.last(where: { $0.endTime == nil && $0.startRow != nil })
    }

    private var hasActiveTank: Bool {
        liveTrip.activeTankNumber != nil
    }

    private var isFilling: Bool {
        liveTrip.isFillingTank
    }

    private var completedTankCount: Int {
        liveTrip.tankSessions.filter { $0.endTime != nil }.count
    }

    @ViewBuilder
    private func tankControls(record: SprayRecord) -> some View {
        let totalTanks = max(record.tanks.count, liveTrip.totalTanks)
        let active = liveTrip.activeTankNumber
        let fillEnabled = store.settings.fillTimerEnabled

        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "drop.fill")
                    .font(.title3)
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("TANK")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        if let n = active {
                            Text("\(n)\(totalTanks > 0 ? " of \(totalTanks)" : "")")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(.cyan)
                        } else {
                            Text(totalTanks > 0 ? "\(completedTankCount) of \(totalTanks) done" : "Not started")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let session = openTankSession {
                        if let idx = record.tanks.firstIndex(where: { $0.tankNumber == session.tankNumber }) {
                            let tank = record.tanks[idx]
                            Text("\(Int(tank.waterVolume)) L water • \(Int(tank.areaPerTank * 100) / 100) ha")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if !hasActiveTank, completedTankCount < record.tanks.count {
                        let next = record.tanks[completedTankCount]
                        Text("Next: Tank \(next.tankNumber) • \(Int(next.waterVolume)) L")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isFilling {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("FILLING")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.cyan)
                        Text(formatFillElapsed(fillElapsed))
                            .font(.system(.title3, design: .monospaced, weight: .bold))
                            .foregroundStyle(.cyan)
                            .contentTransition(.numericText())
                    }
                }
            }

            HStack(spacing: 8) {
                if hasActiveTank {
                    Button {
                        showEndTankConfirmation = true
                    } label: {
                        Label("End Tank", systemImage: "stop.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!accessControl.canCreateOperationalRecords)
                } else {
                    Button {
                        tracking.startTank()
                    } label: {
                        Label("Start Tank", systemImage: "play.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(!accessControl.canCreateOperationalRecords)
                }

                if fillEnabled {
                    if isFilling {
                        Button {
                            tracking.stopFillTimer()
                        } label: {
                            Label("Stop Fill", systemImage: "stop.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(.cyan)
                    } else {
                        Button {
                            tracking.startFillTimer()
                        } label: {
                            Label("Start Fill", systemImage: "timer")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(.cyan)
                        .disabled(hasActiveTank || !accessControl.canCreateOperationalRecords)
                    }
                }
            }

            if !liveTrip.tankSessions.isEmpty {
                tankProgressDots(total: totalTanks)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .confirmationDialog("End this tank?", isPresented: $showEndTankConfirmation) {
            Button("End Tank", role: .destructive) {
                tracking.endTank()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func tankProgressDots(total: Int) -> some View {
        let count = max(total, liveTrip.tankSessions.count)
        return HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                let number = i + 1
                let session = liveTrip.tankSessions.first(where: { $0.tankNumber == number })
                let isComplete = session?.endTime != nil
                let isActive = session?.endTime == nil && session?.startRow != nil
                Circle()
                    .fill(isComplete ? Color.cyan : (isActive ? Color.cyan.opacity(0.5) : Color.secondary.opacity(0.2)))
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func formatFillElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatPath(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters))m" }
        return String(format: "%.1fkm", meters / 1000)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
