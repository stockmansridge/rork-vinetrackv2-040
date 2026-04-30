import UIKit
import PDFKit
import MapKit
import CoreLocation

struct TripPDFService {
    static func generatePDF(trip: Trip, vineyardName: String, paddockName: String, pinCount: Int, mapSnapshot: UIImage?, logoData: Data? = nil, fuelCost: Double = 0, chemicalCosts: [(String, Double)] = [], operatorCost: Double = 0, operatorCategoryName: String? = nil, includeCostings: Bool = true, timeZone: TimeZone = .current) -> Data {
        let pageWidth: CGFloat = 595.0
        let pageHeight: CGFloat = 842.0
        let margin: CGFloat = 40.0
        let contentWidth = pageWidth - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin

            let headerFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
            let bodyFont = UIFont.systemFont(ofSize: 11, weight: .regular)
            let bodyBoldFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
            let captionFont = UIFont.systemFont(ofSize: 9, weight: .regular)
            let accentColor = VineyardTheme.uiOlive

            func checkPageBreak(needed: CGFloat) {
                if y + needed > pageHeight - margin {
                    context.beginPage()
                    y = margin
                }
            }

            func drawText(_ text: String, font: UIFont, color: UIColor = .black, x: CGFloat = margin, maxWidth: CGFloat? = nil) {
                let w = maxWidth ?? contentWidth
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let size = (text as NSString).boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
                checkPageBreak(needed: size.height + 4)
                (text as NSString).draw(in: CGRect(x: x, y: y, width: w, height: size.height), withAttributes: attrs)
                y += size.height + 4
            }

            func drawRow(label: String, value: String, indent: CGFloat = 0) {
                let labelWidth: CGFloat = 180
                let rowHeight: CGFloat = 18
                checkPageBreak(needed: rowHeight)
                let labelAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: UIColor.darkGray]
                let valueAttrs: [NSAttributedString.Key: Any] = [.font: bodyBoldFont, .foregroundColor: UIColor.black]
                (label as NSString).draw(in: CGRect(x: margin + indent, y: y, width: labelWidth, height: rowHeight), withAttributes: labelAttrs)
                (value as NSString).draw(in: CGRect(x: margin + indent + labelWidth, y: y, width: contentWidth - labelWidth - indent, height: rowHeight), withAttributes: valueAttrs)
                y += rowHeight
            }

            func drawSectionHeader(_ text: String) {
                y += 12
                checkPageBreak(needed: 28)
                let rect = CGRect(x: margin, y: y, width: contentWidth, height: 24)
                UIColor(white: 0.95, alpha: 1.0).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: 4).fill()
                let attrs: [NSAttributedString.Key: Any] = [.font: headerFont, .foregroundColor: accentColor]
                (text as NSString).draw(in: CGRect(x: margin + 8, y: y + 4, width: contentWidth - 16, height: 20), withAttributes: attrs)
                y += 30
            }

            PDFHeaderHelper.drawHeader(
                vineyardName: vineyardName,
                logoData: logoData,
                title: "Trip Report",
                accentColor: accentColor,
                margin: margin,
                contentWidth: contentWidth,
                y: &y
            )

            let dateStr = trip.startTime.formattedTZ(date: .abbreviated, time: .shortened, in: timeZone)
            drawText(dateStr, font: captionFont, color: .darkGray)
            y += 4

            drawSectionHeader("Trip Details")
            if !paddockName.isEmpty {
                drawRow(label: "Block", value: paddockName)
            } else if !trip.paddockName.isEmpty {
                drawRow(label: "Block", value: trip.paddockName)
            }
            if !vineyardName.isEmpty {
                drawRow(label: "Vineyard", value: vineyardName)
            }
            if !trip.personName.isEmpty {
                drawRow(label: "Logged By", value: trip.personName)
            }
            drawRow(label: "Date", value: trip.startTime.formattedTZ(date: .abbreviated, time: .shortened, in: timeZone))
            if let endTime = trip.endTime {
                drawRow(label: "End Time", value: endTime.formattedTZ(date: .omitted, time: .shortened, in: timeZone))
            }
            drawRow(label: "Duration", value: formatDuration(trip))
            drawRow(label: "Distance", value: formatDistance(trip.totalDistance))
            drawRow(label: "Average Speed", value: formatAverageSpeed(trip))
            drawRow(label: "Pattern", value: trip.trackingPattern.title)
            drawRow(label: "Pins Logged", value: "\(pinCount)")

            if !trip.rowSequence.isEmpty {
                drawSectionHeader("Row Summary")
                let completed = trip.rowSequence.filter { trip.completedPaths.contains($0) }.count
                let skipped = trip.rowSequence.filter { trip.skippedPaths.contains($0) }.count
                let pending = trip.rowSequence.count - completed - skipped
                drawRow(label: "Total Paths", value: "\(trip.rowSequence.count)")
                drawRow(label: "Completed", value: "\(completed)")
                drawRow(label: "Skipped", value: "\(skipped)")
                if pending > 0 {
                    drawRow(label: "Pending", value: "\(pending)")
                }
            }

            if !trip.tankSessions.isEmpty {
                drawSectionHeader("Tank Sessions")
                for session in trip.tankSessions {
                    let status = session.endTime != nil ? "Complete" : "Active"
                    drawRow(label: "Tank \(session.tankNumber)", value: status)
                    if !session.rowRange.isEmpty {
                        drawRow(label: "  Rows", value: session.rowRange, indent: 12)
                    }
                    if let end = session.endTime {
                        let dur = end.timeIntervalSince(session.startTime)
                        drawRow(label: "  Duration", value: formatDurationSeconds(dur), indent: 12)
                    }
                    if let fillDur = session.fillDuration {
                        drawRow(label: "  Fill Duration", value: formatDurationSeconds(fillDur), indent: 12)
                    }
                    y += 4
                }
            }

            let hasChemCosts = !chemicalCosts.isEmpty
            let hasCosts = hasChemCosts || fuelCost > 0 || operatorCost > 0
            if hasCosts && includeCostings {
                drawSectionHeader("Costs")
                let totalChemCost = chemicalCosts.reduce(0.0) { $0 + $1.1 }
                for (name, cost) in chemicalCosts {
                    drawRow(label: name, value: String(format: "$%.2f", cost))
                }
                if hasChemCosts {
                    y += 4
                    drawRow(label: "Chemical Subtotal", value: String(format: "$%.2f", totalChemCost))
                }
                if fuelCost > 0 {
                    drawRow(label: "Fuel Cost", value: String(format: "$%.2f", fuelCost))
                }
                if operatorCost > 0 {
                    drawRow(label: operatorCategoryName ?? "Operator", value: String(format: "$%.2f", operatorCost))
                }
                y += 4
                let grandTotal = totalChemCost + fuelCost + operatorCost
                drawRow(label: "Total Cost", value: String(format: "$%.2f", grandTotal))
            }

            if let snapshot = mapSnapshot {
                drawSectionHeader("Route Map")

                let maxMapHeight: CGFloat = 320
                let aspectRatio = snapshot.size.height / snapshot.size.width
                let mapHeight = min(contentWidth * aspectRatio, maxMapHeight)

                checkPageBreak(needed: mapHeight + 16)

                let mapRect = CGRect(x: margin, y: y, width: contentWidth, height: mapHeight)
                let clipPath = UIBezierPath(roundedRect: mapRect, cornerRadius: 8)
                context.cgContext.saveGState()
                clipPath.addClip()
                snapshot.draw(in: mapRect)
                context.cgContext.restoreGState()

                UIColor(white: 0.82, alpha: 1.0).setStroke()
                let borderPath = UIBezierPath(roundedRect: mapRect, cornerRadius: 8)
                borderPath.lineWidth = 1
                borderPath.stroke()

                y += mapHeight + 12
            }

            y += 16
            checkPageBreak(needed: 30)
            let footerDate = Date().formattedTZ(date: .abbreviated, time: .shortened, in: timeZone)
            let tzAbbrev = timeZone.abbreviation() ?? timeZone.identifier
            drawText("Generated \(footerDate) (\(tzAbbrev)) • VineTrackV2", font: captionFont, color: .gray)
        }

        return data
    }

    static func captureMapSnapshot(trip: Trip) async -> UIImage? {
        let coords = trip.pathPoints.map { $0.coordinate }
        guard coords.count >= 2 else {
            return nil
        }

        var minLat = coords.map(\.latitude).min() ?? 0
        var maxLat = coords.map(\.latitude).max() ?? 0
        var minLon = coords.map(\.longitude).min() ?? 0
        var maxLon = coords.map(\.longitude).max() ?? 0

        let latPadding = (maxLat - minLat) * 0.15
        let lonPadding = (maxLon - minLon) * 0.15
        minLat -= latPadding
        maxLat += latPadding
        minLon -= lonPadding
        maxLon += lonPadding

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(maxLat - minLat, 0.001),
            longitudeDelta: max(maxLon - minLon, 0.001)
        )

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.size = CGSize(width: 1030, height: 700)
        options.mapType = .hybrid

        let snapshotter = MKMapSnapshotter(options: options)

        do {
            let snapshot = try await snapshotter.start()

            let image = snapshot.image
            UIGraphicsBeginImageContextWithOptions(image.size, true, image.scale)
            image.draw(at: .zero)

            if let ctx = UIGraphicsGetCurrentContext() {
                ctx.setLineWidth(4.0)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)

                for i in 0..<(coords.count - 1) {
                    let p1 = snapshot.point(for: coords[i])
                    let p2 = snapshot.point(for: coords[i + 1])

                    let progress = Double(i) / Double(max(coords.count - 1, 1))
                    let r = CGFloat(1.0 - progress)
                    let g = CGFloat(progress)
                    ctx.setStrokeColor(UIColor(red: r, green: g, blue: 0, alpha: 1.0).cgColor)

                    ctx.move(to: p1)
                    ctx.addLine(to: p2)
                    ctx.strokePath()
                }

                if let firstCoord = coords.first, let lastCoord = coords.last {
                    let startPoint = snapshot.point(for: firstCoord)
                    let endPoint = snapshot.point(for: lastCoord)

                    ctx.setFillColor(UIColor.systemGreen.cgColor)
                    ctx.fillEllipse(in: CGRect(x: startPoint.x - 8, y: startPoint.y - 8, width: 16, height: 16))
                    ctx.setFillColor(UIColor.white.cgColor)
                    ctx.fillEllipse(in: CGRect(x: startPoint.x - 4, y: startPoint.y - 4, width: 8, height: 8))

                    ctx.setFillColor(UIColor.systemRed.cgColor)
                    ctx.fillEllipse(in: CGRect(x: endPoint.x - 8, y: endPoint.y - 8, width: 16, height: 16))
                    ctx.setFillColor(UIColor.white.cgColor)
                    ctx.fillEllipse(in: CGRect(x: endPoint.x - 4, y: endPoint.y - 4, width: 8, height: 8))
                }
            }

            let finalImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return finalImage
        } catch {
            return nil
        }
    }

    static func savePDFToTemp(data: Data, fileName: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let sanitized = fileName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = tempDir.appendingPathComponent("\(sanitized).pdf")
        try? data.write(to: url)
        return url
    }

    private static func formatDuration(_ trip: Trip) -> String {
        formatDurationSeconds(trip.activeDuration)
    }

    private static func formatDurationSeconds(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let hrs = mins / 60
        if hrs > 0 {
            return "\(hrs)h \(mins % 60)m"
        }
        return "\(mins)m"
    }

    private static func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        }
        return String(format: "%.2f km", meters / 1000)
    }

    private static func formatAverageSpeed(_ trip: Trip) -> String {
        let durationSeconds = trip.activeDuration
        guard durationSeconds > 0 && trip.totalDistance > 0 else { return "—" }
        let speedMps = trip.totalDistance / durationSeconds
        let speedKmh = speedMps * 3.6
        return String(format: "%.1f km/h", speedKmh)
    }
}
