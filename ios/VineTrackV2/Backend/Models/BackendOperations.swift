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
    // Portal extension (sql/048) — additive optional columns.
    let rowNumber: Int?
    let side: String?
    let severity: String?
    let status: String?
    let dateObserved: Date?
    let operatorName: String?
    let latitude: Double?
    let longitude: Double?
    let pinId: UUID?
    let tripId: UUID?
    let photoUrls: [String]?
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
        case rowNumber = "row_number"
        case side
        case severity
        case status
        case dateObserved = "date_observed"
        case operatorName = "operator_name"
        case latitude
        case longitude
        case pinId = "pin_id"
        case tripId = "trip_id"
        case photoUrls = "photo_urls"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case clientUpdatedAt = "client_updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.vineyardId = try c.decode(UUID.self, forKey: .vineyardId)
        self.paddockId = try c.decode(UUID.self, forKey: .paddockId)
        self.date = Self.flexibleDate(c, .date)
        self.damageType = try c.decodeIfPresent(String.self, forKey: .damageType)
        self.damagePercent = try c.decodeIfPresent(Double.self, forKey: .damagePercent)
        self.polygonPoints = (try? c.decodeIfPresent([CoordinatePoint].self, forKey: .polygonPoints)) ?? nil
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.rowNumber = try c.decodeIfPresent(Int.self, forKey: .rowNumber)
        self.side = try c.decodeIfPresent(String.self, forKey: .side)
        self.severity = try c.decodeIfPresent(String.self, forKey: .severity)
        self.status = try c.decodeIfPresent(String.self, forKey: .status)
        self.dateObserved = Self.flexibleDate(c, .dateObserved)
        self.operatorName = try c.decodeIfPresent(String.self, forKey: .operatorName)
        self.latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        self.longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        self.pinId = try c.decodeIfPresent(UUID.self, forKey: .pinId)
        self.tripId = try c.decodeIfPresent(UUID.self, forKey: .tripId)
        self.photoUrls = try c.decodeIfPresent([String].self, forKey: .photoUrls)
        self.createdBy = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
        self.createdAt = Self.flexibleDate(c, .createdAt)
        self.updatedAt = Self.flexibleDate(c, .updatedAt)
        self.deletedAt = Self.flexibleDate(c, .deletedAt)
        self.clientUpdatedAt = Self.flexibleDate(c, .clientUpdatedAt)
    }

    private static func flexibleDate(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Date? {
        if let d = try? c.decodeIfPresent(Date.self, forKey: key) { return d }
        guard let s = try? c.decodeIfPresent(String.self, forKey: key), !s.isEmpty else { return nil }
        return BackendDamageRecordDateParser.parse(s)
    }
}

nonisolated enum BackendDamageRecordDateParser {
    static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    static let dateOnly: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .iso8601); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static let timestampNoTZ: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .iso8601); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f
    }()

    static func parse(_ s: String) -> Date? {
        if let d = isoFractional.date(from: s) { return d }
        if let d = isoBasic.date(from: s) { return d }
        if let d = dateOnly.date(from: s) { return d }
        if let d = timestampNoTZ.date(from: s) { return d }
        return nil
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
    // Portal extension fields — encoded only when non-nil so iOS writes
    // never overwrite portal-set values with NULL.
    let rowNumber: Int?
    let side: String?
    let severity: String?
    let status: String?
    let dateObserved: Date?
    let operatorName: String?
    let latitude: Double?
    let longitude: Double?
    let pinId: UUID?
    let tripId: UUID?
    let photoUrls: [String]?
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
        case rowNumber = "row_number"
        case side
        case severity
        case status
        case dateObserved = "date_observed"
        case operatorName = "operator_name"
        case latitude
        case longitude
        case pinId = "pin_id"
        case tripId = "trip_id"
        case photoUrls = "photo_urls"
        case createdBy = "created_by"
        case clientUpdatedAt = "client_updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(vineyardId, forKey: .vineyardId)
        try c.encode(paddockId, forKey: .paddockId)
        try c.encode(date, forKey: .date)
        try c.encode(damageType, forKey: .damageType)
        try c.encode(damagePercent, forKey: .damagePercent)
        try c.encode(polygonPoints, forKey: .polygonPoints)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(rowNumber, forKey: .rowNumber)
        try c.encodeIfPresent(side, forKey: .side)
        try c.encodeIfPresent(severity, forKey: .severity)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(dateObserved, forKey: .dateObserved)
        try c.encodeIfPresent(operatorName, forKey: .operatorName)
        try c.encodeIfPresent(latitude, forKey: .latitude)
        try c.encodeIfPresent(longitude, forKey: .longitude)
        try c.encodeIfPresent(pinId, forKey: .pinId)
        try c.encodeIfPresent(tripId, forKey: .tripId)
        try c.encodeIfPresent(photoUrls, forKey: .photoUrls)
        try c.encodeIfPresent(createdBy, forKey: .createdBy)
        try c.encode(clientUpdatedAt, forKey: .clientUpdatedAt)
    }
}

extension BackendDamageRecord {
    /// Map portal/iOS damage_type strings (any case, including new portal-only
    /// labels) to the closest local DamageType so a row never fails to render.
    static func normalizeDamageType(_ raw: String?) -> DamageType {
        guard let raw, !raw.isEmpty else { return .other }
        if let exact = DamageType(rawValue: raw) { return exact }
        let key = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch key {
        case "frost": return .frost
        case "hail": return .hail
        case "wind": return .wind
        case "heat", "sunburn", "heat / sunburn", "heat/sunburn": return .heat
        case "disease": return .disease
        case "pest", "animal / bird damage", "animal/bird damage", "animal damage", "bird damage": return .pest
        default: return .other
        }
    }

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
            rowNumber: d.rowNumber,
            side: d.side,
            severity: d.severity,
            status: d.status,
            dateObserved: d.dateObserved,
            operatorName: d.operatorName,
            latitude: d.latitude,
            longitude: d.longitude,
            pinId: d.pinId,
            tripId: d.tripId,
            photoUrls: d.photoUrls,
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
            date: date ?? dateObserved ?? Date(),
            damageType: BackendDamageRecord.normalizeDamageType(damageType),
            damagePercent: damagePercent ?? 0,
            notes: notes ?? "",
            rowNumber: rowNumber,
            side: side,
            severity: severity,
            status: status,
            dateObserved: dateObserved,
            operatorName: operatorName,
            latitude: latitude,
            longitude: longitude,
            pinId: pinId,
            tripId: tripId,
            photoUrls: photoUrls
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
