import SwiftUI
import MapKit

struct TripDetailView: View {
    let trip: Trip
    @Environment(MigratedDataStore.self) private var store
    @Environment(BackendAccessControl.self) private var accessControl
    @Environment(\.dismiss) private var dismiss
    @State private var showSummary: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var position: MapCameraPosition = .automatic
    @State private var isExporting: Bool = false
    @State private var displayTrailSegments: [TrailSegment] = []

    private static let maxDisplayTrailPoints: Int = 500
    private static let maxTrailBuckets: Int = 5

    private var sprayRecord: SprayRecord? {
        store.sprayRecords.first { $0.tripId == trip.id }
    }

    private var pinsForTrip: [VinePin] {
        store.pins.filter { $0.tripId == trip.id }
    }

    private var tz: TimeZone { store.settings.resolvedTimeZone }

    private var displayName: String {
        if let record = sprayRecord, !record.sprayReference.isEmpty {
            return record.sprayReference
        }
        let dateStr = trip.startTime.formattedTZ(date: .abbreviated, time: .omitted, in: tz)
        return "Maintenance Trip \(dateStr)"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(VineyardTheme.olive)
                    Label(trip.startTime.formattedTZ(date: .abbreviated, time: .shortened, in: tz), systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let endTime = trip.endTime {
                        Label("Ended \(endTime.formattedTZ(date: .abbreviated, time: .shortened, in: tz))", systemImage: "flag.checkered")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if trip.isActive {
                        Label("Active", systemImage: "circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Stats") {
                if let raw = trip.tripFunction, !raw.isEmpty {
                    if let function = TripFunction(rawValue: raw) {
                        statRow("Function", value: function.displayName, icon: function.icon)
                    } else if raw.hasPrefix("custom:") {
                        let label = trip.tripTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let display = (label?.isEmpty == false) ? label! : String(raw.dropFirst("custom:".count))
                        statRow("Function", value: display, icon: "wrench.and.screwdriver")
                    }
                }
                if let title = trip.tripTitle, !title.isEmpty {
                    statRow("Title", value: title, icon: "text.cursor")
                }
                statRow("Duration", value: formatDuration(trip.activeDuration), icon: "clock")
                statRow("Distance", value: formatDistance(trip.totalDistance), icon: "point.topleft.down.to.point.bottomright.curvepath")
                if !trip.paddockName.isEmpty {
                    statRow("Paddock", value: trip.paddockName, icon: "leaf")
                }
                if !trip.personName.isEmpty {
                    statRow("Operator", value: trip.personName, icon: "person")
                }
                if !trip.rowSequence.isEmpty {
                    statRow("Pattern", value: trip.trackingPattern.title, icon: trip.trackingPattern.icon)
                    if let startDescription = startMidrowDescription {
                        statRow("Started", value: startDescription, icon: "flag")
                    }
                    statRow("Paths planned", value: "\(trip.rowSequence.count)", icon: "list.number")
                    statRow("Completed", value: "\(trip.completedPaths.count)", icon: "checkmark.circle")
                    if !trip.skippedPaths.isEmpty {
                        statRow("Skipped", value: "\(trip.skippedPaths.count)", icon: "xmark.circle")
                    }
                }
                if pinsForTrip.count > 0 {
                    statRow("Pins recorded", value: "\(pinsForTrip.count)", icon: "mappin")
                }
            }

            if let record = sprayRecord {
                Section("Spray Record") {
                    if !record.sprayReference.isEmpty {
                        statRow("Reference", value: record.sprayReference, icon: "drop.fill")
                    }
                    statRow("Date", value: record.date.formattedTZ(date: .abbreviated, time: .omitted, in: tz), icon: "calendar")
                    if record.tanks.count > 0 {
                        statRow("Tanks", value: "\(record.tanks.count)", icon: "cylinder")
                    }
                }
            }

            if !coveredRowSummary.isEmpty {
                Section("Row Coverage") {
                    statRow("Rows covered", value: "\(coveredRowNumbers.count)", icon: "checkmark.circle")
                    if let paddockName = coverageSourcePaddockName {
                        statRow("Paddock", value: paddockName, icon: "leaf")
                    }
                    Text(coveredRowSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if trip.pathPoints.count > 1 {
                Section("Path") {
                    Map(position: $position) {
                        ForEach(displayTrailSegments) { segment in
                            MapPolyline(coordinates: segment.coordinates)
                                .stroke(segment.color, lineWidth: 4)
                        }
                    }
                    .mapStyle(.hybrid)
                    .frame(height: 240)
                    .listRowInsets(EdgeInsets())
                }
            }

            if !trip.rowSequence.isEmpty {
                Section {
                    Button {
                        showSummary = true
                    } label: {
                        Label("View Path Summary", systemImage: "list.bullet.clipboard")
                    }
                }
            }

            if let details = trip.seedingDetails, details.hasAnyValue {
                seedingDetailsSection(details)
            }

            if !pinsForTrip.isEmpty {
                Section("Pins") {
                    ForEach(pinsForTrip) { pin in
                        HStack {
                            Group {
                                if pin.mode == .growth {
                                    GrapeLeafIcon(size: 18, color: VineyardTheme.leafGreen)
                                } else {
                                    Image(systemName: "wrench.fill")
                                        .foregroundStyle(.orange)
                                }
                            }
                            .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pin.buttonName.isEmpty ? "Pin" : pin.buttonName)
                                    .font(.subheadline.weight(.medium))
                                Text(pin.timestamp.formattedTZ(date: .abbreviated, time: .shortened, in: tz))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if pin.isCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if accessControl.canExport {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportTrip()
                    } label: {
                        if isExporting {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(isExporting)
                }
            }
            if accessControl.canDeleteOperationalRecords {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .sheet(isPresented: $showSummary) {
            TripSummarySheet(trip: trip)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Delete Trip", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                store.deleteTrip(trip.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this trip? This action cannot be undone.")
        }
        .onAppear {
            rebuildDisplayTrail()
            if trip.pathPoints.count > 1 {
                let coords = trip.pathPoints.map { $0.coordinate }
                let lats = coords.map { $0.latitude }
                let lons = coords.map { $0.longitude }
                if let minLat = lats.min(), let maxLat = lats.max(),
                   let minLon = lons.min(), let maxLon = lons.max() {
                    let center = CLLocationCoordinate2D(
                        latitude: (minLat + maxLat) / 2,
                        longitude: (minLon + maxLon) / 2
                    )
                    let span = MKCoordinateSpan(
                        latitudeDelta: max(maxLat - minLat, 0.001) * 1.4,
                        longitudeDelta: max(maxLon - minLon, 0.001) * 1.4
                    )
                    position = .region(MKCoordinateRegion(center: center, span: span))
                }
            }
        }
        .onChange(of: trip.pathPoints.count) { _, _ in
            rebuildDisplayTrail()
        }
    }

    /// Build the bucketed display trail once for this historical trip. Mirrors
    /// the live `ActiveTripView` renderer but without the 1s timer — pathPoints
    /// are static here, so we recompute only on appear or if the array changes.
    private func rebuildDisplayTrail() {
        let segments = TrailDisplayProcessor.makeDisplayTrailSegments(
            points: trip.pathPoints,
            maxDisplayPoints: Self.maxDisplayTrailPoints,
            maxColourBuckets: Self.maxTrailBuckets
        )
        displayTrailSegments = segments
        #if DEBUG
        let displayCount = segments.reduce(0) { $0 + $1.coordinates.count }
        print("[Trail/Detail] full=\(trip.pathPoints.count) display=\(displayCount) " +
              "polylines=\(segments.count) mode=bucketed-static")
        #endif
    }

    private var coverageSourcePaddock: Paddock? {
        if let id = trip.paddockId, let p = store.paddocks.first(where: { $0.id == id }) {
            return p
        }
        for id in trip.paddockIds {
            if let p = store.paddocks.first(where: { $0.id == id }) { return p }
        }
        return nil
    }

    private var coverageSourcePaddockName: String? {
        coverageSourcePaddock?.name
    }

    private var coveredRowNumbers: [Double] {
        if !trip.completedPaths.isEmpty {
            return trip.completedPaths.sorted()
        }
        guard let paddock = coverageSourcePaddock, trip.pathPoints.count > 1 else { return [] }
        return RowGuidance.coveredRows(for: trip.pathPoints, in: paddock)
    }

    private var coveredRowSummary: String {
        let rows = coveredRowNumbers
        guard !rows.isEmpty else { return "" }
        let formatted = rows.map { value -> String in
            if value.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f", value)
            }
            return String(format: "%.1f", value)
        }
        return formatted.joined(separator: ", ")
    }

    private var startMidrowDescription: String? {
        guard trip.trackingPattern == .everySecondRow,
              let startMidrow = trip.rowSequence.first else { return nil }
        let lowerRow = Int(floor(startMidrow))
        let upperRow = lowerRow + 1
        let midrowText: String
        if startMidrow.truncatingRemainder(dividingBy: 1) == 0 {
            midrowText = String(format: "%.0f", startMidrow)
        } else {
            midrowText = String(format: "%.1f", startMidrow)
        }
        return "Between rows \(lowerRow)–\(upperRow) — midrow \(midrowText)"
    }

    @ViewBuilder
    private func seedingDetailsSection(_ details: SeedingDetails) -> some View {
        Section("Seeding Details") {
            if let depth = details.sowingDepthCm {
                statRow("Sowing depth", value: "\(formatNumber(depth)) cm", icon: "ruler")
            }
            if let front = details.frontBox, front.hasAnyValue {
                seedingBoxRows(title: "Front Box", box: front)
            }
            if let back = details.backBox, back.hasAnyValue {
                seedingBoxRows(title: "Back Box", box: back)
            }
            if let lines = details.mixLines, !lines.isEmpty {
                ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                    seedingMixLineRow(index: idx, line: line)
                }
            }
        }
    }

    @ViewBuilder
    private func seedingBoxRows(title: String, box: SeedingBox) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let mix = box.mixName, !mix.isEmpty {
                statRow("Mix", value: mix, icon: "text.alignleft")
            }
            if let rate = box.ratePerHa {
                statRow("Rate/ha", value: "\(formatNumber(rate)) kg/ha", icon: "speedometer")
            }
            if let s = box.shutterSlide, !s.isEmpty {
                statRow("Shutter", value: s, icon: "slider.horizontal.3")
            }
            if let f = box.bottomFlap, !f.isEmpty {
                statRow("Bottom flap", value: f, icon: "rectangle.bottomthird.inset.filled")
            }
            if let w = box.meteringWheel, !w.isEmpty {
                statRow("Metering wheel", value: w, icon: "gearshape")
            }
            if let v = box.seedVolumeKg {
                statRow("Seed volume", value: "\(formatNumber(v)) kg", icon: "shippingbox")
            }
            if let g = box.gearboxSetting {
                statRow("Gearbox", value: formatNumber(g), icon: "gearshape.2")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func seedingMixLineRow(index: Int, line: SeedingMixLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mix line \(index + 1)\(line.name.flatMap { $0.isEmpty ? nil : " — \($0)" } ?? "")")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let pct = line.percentOfMix {
                statRow("% of mix", value: "\(formatNumber(pct))%", icon: "percent")
            }
            if let box = line.seedBox, !box.isEmpty {
                statRow("Seed box", value: box, icon: "shippingbox")
            }
            if let kg = line.kgPerHa {
                statRow("Kg/ha", value: "\(formatNumber(kg)) kg/ha", icon: "scalemass")
            }
            if let supplier = line.supplierManufacturer, !supplier.isEmpty {
                statRow("Supplier", value: supplier, icon: "building.2")
            }
        }
        .padding(.vertical, 4)
    }

    private func formatNumber(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%g", value)
    }

    private func statRow(_ label: String, value: String, icon: String) -> some View {
        HStack {
            if icon.hasPrefix("leaf") {
                Label { Text(label) } icon: { GrapeLeafIcon(size: 16) }
            } else {
                Label(label, systemImage: icon)
            }
            Spacer()
            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let hrs = mins / 60
        if hrs > 0 {
            return "\(hrs)h \(mins % 60)m"
        }
        return "\(mins)m"
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        }
        return String(format: "%.1fkm", meters / 1000)
    }

    private func exportTrip() {
        guard !isExporting else { return }
        isExporting = true
        let vineyardName = store.selectedVineyard?.name ?? "Vineyard"
        let logoData = store.selectedVineyard?.logoData
        let paddockName = trip.paddockName
        let pinCount = pinsForTrip.count
        let tripCopy = trip
        let exportTimeZone = tz
        let fileName = "TripReport_\(vineyardName)_\(trip.startTime.formattedTZ(date: .numeric, time: .omitted, in: exportTimeZone))"

        Task {
            let snapshot = await TripPDFService.captureMapSnapshot(trip: tripCopy)
            let pdfData = TripPDFService.generatePDF(
                trip: tripCopy,
                vineyardName: vineyardName,
                paddockName: paddockName,
                pinCount: pinCount,
                mapSnapshot: snapshot,
                logoData: logoData,
                timeZone: exportTimeZone
            )
            let url = TripPDFService.savePDFToTemp(data: pdfData, fileName: fileName)
            isExporting = false

            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                var presenter = rootVC
                while let presented = presenter.presentedViewController {
                    presenter = presented
                }
                presenter.present(activityVC, animated: true)
            }
        }
    }
}
