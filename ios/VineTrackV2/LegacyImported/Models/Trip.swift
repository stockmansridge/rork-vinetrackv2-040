import Foundation
import CoreLocation

nonisolated struct TankSession: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var tankNumber: Int
    var startTime: Date
    var endTime: Date?
    var pathsCovered: [Double]
    var startRow: Double?
    var endRow: Double?
    var fillStartTime: Date?
    var fillEndTime: Date?

    var fillDuration: TimeInterval? {
        guard let start = fillStartTime, let end = fillEndTime else { return nil }
        return end.timeIntervalSince(start)
    }

    init(
        id: UUID = UUID(),
        tankNumber: Int = 1,
        startTime: Date = Date(),
        endTime: Date? = nil,
        pathsCovered: [Double] = [],
        startRow: Double? = nil,
        endRow: Double? = nil,
        fillStartTime: Date? = nil,
        fillEndTime: Date? = nil
    ) {
        self.id = id
        self.tankNumber = tankNumber
        self.startTime = startTime
        self.endTime = endTime
        self.pathsCovered = pathsCovered
        self.startRow = startRow
        self.endRow = endRow
        self.fillStartTime = fillStartTime
        self.fillEndTime = fillEndTime
    }

    var rowRange: String {
        guard let start = startRow, let end = endRow else { return "" }
        if start == end { return "Row \(formatRow(start))" }
        return "Rows \(formatRow(min(start, end)))–\(formatRow(max(start, end)))"
    }

    private func formatRow(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}

nonisolated struct Trip: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var vineyardId: UUID
    let paddockId: UUID?
    let paddockName: String
    var paddockIds: [UUID]
    let startTime: Date
    var endTime: Date?
    var currentRowNumber: Double
    var nextRowNumber: Double
    var pathPoints: [CoordinatePoint]
    var isActive: Bool
    var trackingPattern: TrackingPattern
    var rowSequence: [Double]
    var sequenceIndex: Int
    var personName: String
    var totalDistance: Double
    var pinIds: [UUID]
    var completedPaths: [Double]
    var skippedPaths: [Double]
    var currentPathDistance: Double
    var tankSessions: [TankSession]
    var activeTankNumber: Int?
    var totalTanks: Int
    var pauseTimestamps: [Date]
    var resumeTimestamps: [Date]
    var isPaused: Bool
    var isFillingTank: Bool
    var fillingTankNumber: Int?

    var activeDuration: TimeInterval {
        let end = endTime ?? Date()
        var total: TimeInterval = 0
        var lastStart = startTime
        for i in 0..<pauseTimestamps.count {
            total += pauseTimestamps[i].timeIntervalSince(lastStart)
            if i < resumeTimestamps.count {
                lastStart = resumeTimestamps[i]
            } else {
                return total
            }
        }
        total += end.timeIntervalSince(lastStart)
        return total
    }

    init(
        id: UUID = UUID(),
        vineyardId: UUID = UUID(),
        paddockId: UUID? = nil,
        paddockName: String = "",
        paddockIds: [UUID] = [],
        startTime: Date = Date(),
        endTime: Date? = nil,
        currentRowNumber: Double = 0.5,
        nextRowNumber: Double = 1.5,
        pathPoints: [CoordinatePoint] = [],
        isActive: Bool = true,
        trackingPattern: TrackingPattern = .sequential,
        rowSequence: [Double] = [],
        sequenceIndex: Int = 0,
        personName: String = "",
        totalDistance: Double = 0,
        pinIds: [UUID] = [],
        completedPaths: [Double] = [],
        skippedPaths: [Double] = [],
        currentPathDistance: Double = 0,
        tankSessions: [TankSession] = [],
        activeTankNumber: Int? = nil,
        totalTanks: Int = 0,
        pauseTimestamps: [Date] = [],
        resumeTimestamps: [Date] = [],
        isPaused: Bool = false,
        isFillingTank: Bool = false,
        fillingTankNumber: Int? = nil
    ) {
        self.id = id
        self.vineyardId = vineyardId
        self.paddockId = paddockId
        self.paddockName = paddockName
        self.paddockIds = paddockIds
        self.startTime = startTime
        self.endTime = endTime
        self.currentRowNumber = currentRowNumber
        self.nextRowNumber = nextRowNumber
        self.pathPoints = pathPoints
        self.isActive = isActive
        self.trackingPattern = trackingPattern
        self.rowSequence = rowSequence
        self.sequenceIndex = sequenceIndex
        self.personName = personName
        self.totalDistance = totalDistance
        self.pinIds = pinIds
        self.completedPaths = completedPaths
        self.skippedPaths = skippedPaths
        self.currentPathDistance = currentPathDistance
        self.tankSessions = tankSessions
        self.activeTankNumber = activeTankNumber
        self.totalTanks = totalTanks
        self.pauseTimestamps = pauseTimestamps
        self.resumeTimestamps = resumeTimestamps
        self.isPaused = isPaused
        self.isFillingTank = isFillingTank
        self.fillingTankNumber = fillingTankNumber
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case id, vineyardId, paddockId, paddockName, paddockIds, startTime, endTime
        case currentRowNumber, nextRowNumber, pathPoints, isActive
        case trackingPattern, rowSequence, sequenceIndex
        case personName, totalDistance, pinIds
        case completedPaths, skippedPaths, currentPathDistance
        case tankSessions, activeTankNumber, totalTanks
        case pauseTimestamps, resumeTimestamps, isPaused
        case isFillingTank, fillingTankNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        vineyardId = try container.decode(UUID.self, forKey: .vineyardId)
        paddockId = try container.decodeIfPresent(UUID.self, forKey: .paddockId)
        paddockName = try container.decode(String.self, forKey: .paddockName)
        paddockIds = try container.decodeIfPresent([UUID].self, forKey: .paddockIds) ?? (paddockId.map { [$0] } ?? [])
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        pathPoints = try container.decode([CoordinatePoint].self, forKey: .pathPoints)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        trackingPattern = try container.decodeIfPresent(TrackingPattern.self, forKey: .trackingPattern) ?? .sequential
        sequenceIndex = try container.decodeIfPresent(Int.self, forKey: .sequenceIndex) ?? 0
        personName = try container.decodeIfPresent(String.self, forKey: .personName) ?? ""
        totalDistance = try container.decodeIfPresent(Double.self, forKey: .totalDistance) ?? 0
        pinIds = try container.decodeIfPresent([UUID].self, forKey: .pinIds) ?? []
        completedPaths = try container.decodeIfPresent([Double].self, forKey: .completedPaths) ?? []
        skippedPaths = try container.decodeIfPresent([Double].self, forKey: .skippedPaths) ?? []
        currentPathDistance = try container.decodeIfPresent(Double.self, forKey: .currentPathDistance) ?? 0
        tankSessions = try container.decodeIfPresent([TankSession].self, forKey: .tankSessions) ?? []
        activeTankNumber = try container.decodeIfPresent(Int.self, forKey: .activeTankNumber)
        totalTanks = try container.decodeIfPresent(Int.self, forKey: .totalTanks) ?? 0
        pauseTimestamps = try container.decodeIfPresent([Date].self, forKey: .pauseTimestamps) ?? []
        resumeTimestamps = try container.decodeIfPresent([Date].self, forKey: .resumeTimestamps) ?? []
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        isFillingTank = try container.decodeIfPresent(Bool.self, forKey: .isFillingTank) ?? false
        fillingTankNumber = try container.decodeIfPresent(Int.self, forKey: .fillingTankNumber)

        if let doubleRow = try? container.decode(Double.self, forKey: .currentRowNumber) {
            currentRowNumber = doubleRow
        } else if let intRow = try? container.decode(Int.self, forKey: .currentRowNumber) {
            currentRowNumber = Double(intRow)
        } else {
            currentRowNumber = 0.5
        }

        if let doubleRow = try? container.decode(Double.self, forKey: .nextRowNumber) {
            nextRowNumber = doubleRow
        } else if let intRow = try? container.decode(Int.self, forKey: .nextRowNumber) {
            nextRowNumber = Double(intRow)
        } else {
            nextRowNumber = 1.5
        }

        if let doubleSeq = try? container.decode([Double].self, forKey: .rowSequence) {
            rowSequence = doubleSeq
        } else if let intSeq = try? container.decode([Int].self, forKey: .rowSequence) {
            rowSequence = intSeq.map { Double($0) }
        } else {
            rowSequence = []
        }
    }
}
