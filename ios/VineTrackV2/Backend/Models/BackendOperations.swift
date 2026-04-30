import Foundation

// MARK: - Work Tasks

nonisolated struct BackendWorkTask: Codable, Sendable, Identifiable {
    let id: UUID
    let vineyardId: UUID
    let paddockId: UUID?
    let paddockName: String?
    let date: Date?
    let taskType: String?
    let durationHours: Double?
    let resources: [WorkTaskResource]?
    let notes: String?
    let isArchived: Bool?
    let archivedAt: Date?
    let archivedBy: String?
    let isFinalized: Bool?
    let finalizedAt: Date?
    let finalizedBy: String?
    let createdBy: UUID?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?
    let clientUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case paddockId = "paddock_id"
        case paddockName = "paddock_name"
        case date
        case taskType = "task_type"
        case durationHours = "duration_hours"
        case resources
        case notes
        case isArchived = "is_archived"
        case archivedAt = "archived_at"
        case archivedBy = "archived_by"
        case isFinalized = "is_finalized"
        case finalizedAt = "finalized_at"
        case finalizedBy = "finalized_by"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case clientUpdatedAt = "client_updated_at"
    }
}

nonisolated struct BackendWorkTaskUpsert: Encodable, Sendable {
    let id: UUID
    let vineyardId: UUID
    let paddockId: UUID?
    let paddockName: String
    let date: Date
    let taskType: String
    let durationHours: Double
    let resources: [WorkTaskResource]
    let notes: String
    let isArchived: Bool
    let archivedAt: Date?
    let archivedBy: String?
    let isFinalized: Bool
    let finalizedAt: Date?
    let finalizedBy: String?
    let createdBy: UUID?
    let clientUpdatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case paddockId = "paddock_id"
        case paddockName = "paddock_name"
        case date
        case taskType = "task_type"
        case durationHours = "duration_hours"
        case resources
        case notes
        case isArchived = "is_archived"
        case archivedAt = "archived_at"
        case archivedBy = "archived_by"
        case isFinalized = "is_finalized"
        case finalizedAt = "finalized_at"
        case finalizedBy = "finalized_by"
        case createdBy = "created_by"
        case clientUpdatedAt = "client_updated_at"
    }
}

extension BackendWorkTask {
    static func upsert(from t: WorkTask, createdBy: UUID?, clientUpdatedAt: Date) -> BackendWorkTaskUpsert {
        BackendWorkTaskUpsert(
            id: t.id,
            vineyardId: t.vineyardId,
            paddockId: t.paddockId,
            paddockName: t.paddockName,
            date: t.date,
            taskType: t.taskType,
            durationHours: t.durationHours,
            resources: t.resources,
            notes: t.notes,
            isArchived: t.isArchived,
            archivedAt: t.archivedAt,
            archivedBy: t.archivedBy,
            isFinalized: t.isFinalized,
            finalizedAt: t.finalizedAt,
            finalizedBy: t.finalizedBy,
            createdBy: createdBy,
            clientUpdatedAt: clientUpdatedAt
        )
    }

    func toWorkTask() -> WorkTask {
        WorkTask(
            id: id,
            vineyardId: vineyardId,
            date: date ?? Date(),
            taskType: taskType ?? "",
            paddockId: paddockId,
            paddockName: paddockName ?? "",
            durationHours: durationHours ?? 0,
            resources: resources ?? [],
            notes: notes ?? "",
            createdBy: createdBy?.uuidString,
            isArchived: isArchived ?? false,
            archivedAt: archivedAt,
            archivedBy: archivedBy,
            isFinalized: isFinalized ?? false,
            finalizedAt: finalizedAt,
            finalizedBy: finalizedBy
        )
    }
}

// MARK: - Maintenance Logs

nonisolated struct BackendMaintenanceLog: Codable, Sendable, Identifiable {
    let id: UUID
    let vineyardId: UUID
    let itemName: String?
    let hours: Double?
    let workCompleted: String?
    let partsUsed: String?
    let partsCost: Double?
    let labourCost: Double?
    let date: Date?
    let photoPath: String?
    let isArchived: Bool?
    let archivedAt: Date?
    let archivedBy: String?
    let isFinalized: Bool?
    let finalizedAt: Date?
    let finalizedBy: String?
    let createdBy: UUID?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?
    let clientUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case itemName = "item_name"
        case hours
        case workCompleted = "work_completed"
        case partsUsed = "parts_used"
        case partsCost = "parts_cost"
        case labourCost = "labour_cost"
        case date
        case photoPath = "photo_path"
        case isArchived = "is_archived"
        case archivedAt = "archived_at"
        case archivedBy = "archived_by"
        case isFinalized = "is_finalized"
        case finalizedAt = "finalized_at"
        case finalizedBy = "finalized_by"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case clientUpdatedAt = "client_updated_at"
    }
}

nonisolated struct BackendMaintenanceLogUpsert: Encodable, Sendable {
    let id: UUID
    let vineyardId: UUID
    let itemName: String
    let hours: Double
    let workCompleted: String
    let partsUsed: String
    let partsCost: Double
    let labourCost: Double
    let date: Date
    let photoPath: String?
    let isArchived: Bool
    let archivedAt: Date?
    let archivedBy: String?
    let isFinalized: Bool
    let finalizedAt: Date?
    let finalizedBy: String?
    let createdBy: UUID?
    let clientUpdatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case itemName = "item_name"
        case hours
        case workCompleted = "work_completed"
        case partsUsed = "parts_used"
        case partsCost = "parts_cost"
        case labourCost = "labour_cost"
        case date
        case photoPath = "photo_path"
        case isArchived = "is_archived"
        case archivedAt = "archived_at"
        case archivedBy = "archived_by"
        case isFinalized = "is_finalized"
        case finalizedAt = "finalized_at"
        case finalizedBy = "finalized_by"
        case createdBy = "created_by"
        case clientUpdatedAt = "client_updated_at"
    }
}

extension BackendMaintenanceLog {
    static func upsert(from m: MaintenanceLog, createdBy: UUID?, clientUpdatedAt: Date) -> BackendMaintenanceLogUpsert {
        BackendMaintenanceLogUpsert(
            id: m.id,
            vineyardId: m.vineyardId,
            itemName: m.itemName,
            hours: m.hours,
            workCompleted: m.workCompleted,
            partsUsed: m.partsUsed,
            partsCost: m.partsCost,
            labourCost: m.labourCost,
            date: m.date,
            photoPath: m.photoPath,
            isArchived: m.isArchived,
            archivedAt: m.archivedAt,
            archivedBy: m.archivedBy,
            isFinalized: m.isFinalized,
            finalizedAt: m.finalizedAt,
            finalizedBy: m.finalizedBy,
            createdBy: createdBy,
            clientUpdatedAt: clientUpdatedAt
        )
    }

    func toMaintenanceLog(preservingPhoto: Data? = nil) -> MaintenanceLog {
        MaintenanceLog(
            id: id,
            vineyardId: vineyardId,
            itemName: itemName ?? "",
            hours: hours ?? 0,
            workCompleted: workCompleted ?? "",
            partsUsed: partsUsed ?? "",
            partsCost: partsCost ?? 0,
            labourCost: labourCost ?? 0,
            date: date ?? Date(),
            invoicePhotoData: preservingPhoto,
            photoPath: photoPath,
            createdBy: createdBy?.uuidString,
            isArchived: isArchived ?? false,
            archivedAt: archivedAt,
            archivedBy: archivedBy,
            isFinalized: isFinalized ?? false,
            finalizedAt: finalizedAt,
            finalizedBy: finalizedBy
        )
    }
}

// MARK: - Yield Estimation Sessions

nonisolated struct BackendYieldEstimationSession: Codable, Sendable, Identifiable {
    let id: UUID
    let vineyardId: UUID
    let payload: YieldEstimationSession?
    let isCompleted: Bool?
    let completedAt: Date?
    let sessionCreatedAt: Date?
    let createdBy: UUID?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?
    let clientUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case payload
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
        case sessionCreatedAt = "session_created_at"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case clientUpdatedAt = "client_updated_at"
    }
}

nonisolated struct BackendYieldEstimationSessionUpsert: Encodable, Sendable {
    let id: UUID
    let vineyardId: UUID
    let payload: YieldEstimationSession
    let isCompleted: Bool
    let completedAt: Date?
    let sessionCreatedAt: Date
    let createdBy: UUID?
    let clientUpdatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case payload
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
        case sessionCreatedAt = "session_created_at"
        case createdBy = "created_by"
        case clientUpdatedAt = "client_updated_at"
    }
}

extension BackendYieldEstimationSession {
    static func upsert(from s: YieldEstimationSession, createdBy: UUID?, clientUpdatedAt: Date) -> BackendYieldEstimationSessionUpsert {
        BackendYieldEstimationSessionUpsert(
            id: s.id,
            vineyardId: s.vineyardId,
            payload: s,
            isCompleted: s.isCompleted,
            completedAt: s.completedAt,
            sessionCreatedAt: s.createdAt,
            createdBy: createdBy,
            clientUpdatedAt: clientUpdatedAt
        )
    }

    func toYieldEstimationSession() -> YieldEstimationSession? {
        payload
    }
}

// MARK: - Damage Records

nonisolated struct BackendDamageRecord: Codable, Sendable, Identifiable {
    let id: UUID
    let vineyardId: UUID
    let paddockId: UUID
    let date: Date?
    let damageType: String?
    let damagePercent: Double?
    let polygonPoints: [CoordinatePoint]?
    let notes: String?
    let createdBy: UUID?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?
    let clientUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case paddockId = "paddock_id"
        case date
        case damageType = "damage_type"
        case damagePercent = "damage_percent"
        case polygonPoints = "polygon_points"
        case notes
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case clientUpdatedAt = "client_updated_at"
    }
}

nonisolated struct BackendDamageRecordUpsert: Encodable, Sendable {
    let id: UUID
    let vineyardId: UUID
    let paddockId: UUID
    let date: Date
    let damageType: String
    let damagePercent: Double
    let polygonPoints: [CoordinatePoint]
    let notes: String
    let createdBy: UUID?
    let clientUpdatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case paddockId = "paddock_id"
        case date
        case damageType = "damage_type"
        case damagePercent = "damage_percent"
        case polygonPoints = "polygon_points"
        case notes
        case createdBy = "created_by"
        case clientUpdatedAt = "client_updated_at"
    }
}

extension BackendDamageRecord {
    static func upsert(from d: DamageRecord, createdBy: UUID?, clientUpdatedAt: Date) -> BackendDamageRecordUpsert {
        BackendDamageRecordUpsert(
            id: d.id,
            vineyardId: d.vineyardId,
            paddockId: d.paddockId,
            date: d.date,
            damageType: d.damageType.rawValue,
            damagePercent: d.damagePercent,
            polygonPoints: d.polygonPoints,
            notes: d.notes,
            createdBy: createdBy,
            clientUpdatedAt: clientUpdatedAt
        )
    }

    func toDamageRecord() -> DamageRecord {
        DamageRecord(
            id: id,
            vineyardId: vineyardId,
            paddockId: paddockId,
            polygonPoints: polygonPoints ?? [],
            date: date ?? Date(),
            damageType: damageType.flatMap { DamageType(rawValue: $0) } ?? .frost,
            damagePercent: damagePercent ?? 0,
            notes: notes ?? ""
        )
    }
}

// MARK: - Historical Yield Records

nonisolated struct BackendHistoricalYieldRecord: Codable, Sendable, Identifiable {
    let id: UUID
    let vineyardId: UUID
    let season: String?
    let year: Int?
    let archivedAt: Date?
    let totalYieldTonnes: Double?
    let totalAreaHectares: Double?
    let notes: String?
    let blockResults: [HistoricalBlockResult]?
    let createdBy: UUID?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?
    let clientUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case season
        case year
        case archivedAt = "archived_at"
        case totalYieldTonnes = "total_yield_tonnes"
        case totalAreaHectares = "total_area_hectares"
        case notes
        case blockResults = "block_results"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case clientUpdatedAt = "client_updated_at"
    }
}

nonisolated struct BackendHistoricalYieldRecordUpsert: Encodable, Sendable {
    let id: UUID
    let vineyardId: UUID
    let season: String
    let year: Int
    let archivedAt: Date
    let totalYieldTonnes: Double
    let totalAreaHectares: Double
    let notes: String
    let blockResults: [HistoricalBlockResult]
    let createdBy: UUID?
    let clientUpdatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case season
        case year
        case archivedAt = "archived_at"
        case totalYieldTonnes = "total_yield_tonnes"
        case totalAreaHectares = "total_area_hectares"
        case notes
        case blockResults = "block_results"
        case createdBy = "created_by"
        case clientUpdatedAt = "client_updated_at"
    }
}

extension BackendHistoricalYieldRecord {
    static func upsert(from h: HistoricalYieldRecord, createdBy: UUID?, clientUpdatedAt: Date) -> BackendHistoricalYieldRecordUpsert {
        BackendHistoricalYieldRecordUpsert(
            id: h.id,
            vineyardId: h.vineyardId,
            season: h.season,
            year: h.year,
            archivedAt: h.archivedAt,
            totalYieldTonnes: h.totalYieldTonnes,
            totalAreaHectares: h.totalAreaHectares,
            notes: h.notes,
            blockResults: h.blockResults,
            createdBy: createdBy,
            clientUpdatedAt: clientUpdatedAt
        )
    }

    func toHistoricalYieldRecord() -> HistoricalYieldRecord {
        HistoricalYieldRecord(
            id: id,
            vineyardId: vineyardId,
            season: season ?? "",
            year: year ?? 0,
            archivedAt: archivedAt ?? Date(),
            blockResults: blockResults ?? [],
            totalYieldTonnes: totalYieldTonnes ?? 0,
            totalAreaHectares: totalAreaHectares ?? 0,
            notes: notes ?? ""
        )
    }
}
