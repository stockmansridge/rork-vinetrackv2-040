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
                statRow("Duration", value: formatDuration(trip.activeDuration), icon: "clock")
                statRow("Distance", value: formatDistance(trip.totalDistance), icon: "point.topleft.down.to.point.bottomright.curvepath")
                if !trip.paddockName.isEmpty {
                    statRow("Paddock", value: trip.paddockName, icon: "leaf")
                }
                if !trip.personName.isEmpty {
                    statRow("Operator", value: trip.personName, icon: "person")
                }
                if !trip.rowSequence.isEmpty {
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
                        let coords = trip.pathPoints.map { $0.coordinate }
                        if coords.count > 1 {
                            MapPolyline(coordinates: coords)
                                .stroke(VineyardTheme.leafGreen, lineWidth: 4)
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
