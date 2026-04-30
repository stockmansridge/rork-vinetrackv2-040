import Foundation
import CoreLocation

nonisolated struct VinePin: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var vineyardId: UUID
    let latitude: Double
    let longitude: Double
    let heading: Double
    let buttonName: String
    let buttonColor: String
    let side: PinSide
    let mode: PinMode
    let paddockId: UUID?
    let rowNumber: Int?
    let timestamp: Date
    var createdBy: String?
    var isCompleted: Bool
    var completedBy: String?
    var completedAt: Date?
    var photoData: Data?
    var photoPath: String?
    var tripId: UUID?
    var growthStageCode: String?
    var notes: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(
        id: UUID = UUID(),
        vineyardId: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        heading: Double,
        buttonName: String,
        buttonColor: String,
        side: PinSide,
        mode: PinMode,
        paddockId: UUID? = nil,
        rowNumber: Int? = nil,
        timestamp: Date = Date(),
        createdBy: String? = nil,
        isCompleted: Bool = false,
        completedBy: String? = nil,
        completedAt: Date? = nil,
        photoData: Data? = nil,
        photoPath: String? = nil,
        tripId: UUID? = nil,
        growthStageCode: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.vineyardId = vineyardId
        self.latitude = latitude
        self.longitude = longitude
        self.heading = heading
        self.buttonName = buttonName
        self.buttonColor = buttonColor
        self.side = side
        self.mode = mode
        self.paddockId = paddockId
        self.rowNumber = rowNumber
        self.timestamp = timestamp
        self.createdBy = createdBy
        self.isCompleted = isCompleted
        self.completedBy = completedBy
        self.completedAt = completedAt
        self.photoData = photoData
        self.photoPath = photoPath
        self.tripId = tripId
        self.growthStageCode = growthStageCode
        self.notes = notes
    }
}

nonisolated enum PinSide: String, Codable, Sendable, Hashable {
    case left = "Left"
    case right = "Right"
}

nonisolated enum PinMode: String, Codable, Sendable, Hashable, CaseIterable {
    case repairs = "Repairs"
    case growth = "Growth"
}
