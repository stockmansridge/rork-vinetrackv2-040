import Foundation

// MARK: - Saved Chemicals

nonisolated struct BackendSavedChemical: Codable, Sendable, Identifiable {
    let id: UUID
    let vineyardId: UUID
    let name: String?
    let ratePerHa: Double?
    let unit: String?
    let chemicalGroup: String?
    let use: String?
    let manufacturer: String?
    let restrictions: String?
    let notes: String?
    let crop: String?
    let problem: String?
    let activeIngredient: String?
    let rates: [ChemicalRate]?
    let purchase: ChemicalPurchase?
    let labelUrl: String?
    let modeOfAction: String?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?
    let clientUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case name
        case ratePerHa = "rate_per_ha"
        case unit
        case chemicalGroup = "chemical_group"
        case use
        case manufacturer
        case restrictions
        case notes
        case crop
        case problem
        case activeIngredient = "active_ingredient"
        case rates
        case purchase
        case labelUrl = "label_url"
        case modeOfAction = "mode_of_action"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case clientUpdatedAt = "client_updated_at"
    }
}

nonisolated struct BackendSavedChemicalUpsert: Encodable, Sendable {
    let id: UUID
    let vineyardId: UUID
    let name: String
    let ratePerHa: Double
    let unit: String
    let chemicalGroup: String
    let use: String
    let manufacturer: String
    let restrictions: String
    let notes: String
    let crop: String
    let problem: String
    let activeIngredient: String
    let rates: [ChemicalRate]
    let purchase: ChemicalPurchase?
    let labelUrl: String
    let modeOfAction: String
    let createdBy: UUID?
    let clientUpdatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case name
        case ratePerHa = "rate_per_ha"
        case unit
        case chemicalGroup = "chemical_group"
        case use
        case manufacturer
        case restrictions
        case notes
        case crop
        case problem
        case activeIngredient = "active_ingredient"
        case rates
        case purchase
        case labelUrl = "label_url"
        case modeOfAction = "mode_of_action"
        case createdBy = "created_by"
        case clientUpdatedAt = "client_updated_at"
    }
}

extension BackendSavedChemical {
    static func upsert(from c: SavedChemical, createdBy: UUID?, clientUpdatedAt: Date) -> BackendSavedChemicalUpsert {
        BackendSavedChemicalUpsert(
            id: c.id,
            vineyardId: c.vineyardId,
            name: c.name,
            ratePerHa: c.ratePerHa,
            unit: c.unit.rawValue,
            chemicalGroup: c.chemicalGroup,
            use: c.use,
            manufacturer: c.manufacturer,
            restrictions: c.restrictions,
            notes: c.notes,
            crop: c.crop,
            problem: c.problem,
            activeIngredient: c.activeIngredient,
            rates: c.rates,
            purchase: c.purchase,
            labelUrl: c.labelURL,
            modeOfAction: c.modeOfAction,
            createdBy: createdBy,
            clientUpdatedAt: clientUpdatedAt
        )
    }

    func toSavedChemical() -> SavedChemical {
        SavedChemical(
            id: id,
            vineyardId: vineyardId,
            name: name ?? "",
            ratePerHa: ratePerHa ?? 0,
            unit: ChemicalUnit(rawValue: unit ?? "") ?? .litres,
            chemicalGroup: chemicalGroup ?? "",
            use: use ?? "",
            manufacturer: manufacturer ?? "",
            restrictions: restrictions ?? "",
            notes: notes ?? "",
            crop: crop ?? "",
            problem: problem ?? "",
            activeIngredient: activeIngredient ?? "",
            rates: rates ?? [],
            purchase: purchase,
            labelURL: LabelURLValidator.sanitize(labelUrl ?? ""),
            modeOfAction: modeOfAction ?? ""
        )
    }
}

// MARK: - Saved Spray Presets

nonisolated struct BackendSavedSprayPreset: Codable, Sendable, Identifiable {
    let id: UUID
    let vineyardId: UUID
    let name: String?
    let waterVolume: Double?
    let sprayRatePerHa: Double?
    let concentrationFactor: Double?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?
    let clientUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case name
        case waterVolume = "water_volume"
        case sprayRatePerHa = "spray_rate_per_ha"
        case concentrationFactor = "concentration_factor"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case clientUpdatedAt = "client_updated_at"
    }
}

nonisolated struct BackendSavedSprayPresetUpsert: Encodable, Sendable {
    let id: UUID
    let vineyardId: UUID
    let name: String
    let waterVolume: Double
    let sprayRatePerHa: Double
    let concentrationFactor: Double
    let createdBy: UUID?
    let clientUpdatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case name
        case waterVolume = "water_volume"
        case sprayRatePerHa = "spray_rate_per_ha"
        case concentrationFactor = "concentration_factor"
        case createdBy = "created_by"
        case clientUpdatedAt = "client_updated_at"
    }
}

extension BackendSavedSprayPreset {
    static func upsert(from p: SavedSprayPreset, createdBy: UUID?, clientUpdatedAt: Date) -> BackendSavedSprayPresetUpsert {
        BackendSavedSprayPresetUpsert(
            id: p.id,
            vineyardId: p.vineyardId,
            name: p.name,
            waterVolume: p.waterVolume,
            sprayRatePerHa: p.sprayRatePerHa,
            concentrationFactor: p.concentrationFactor,
            createdBy: createdBy,
            clientUpdatedAt: clientUpdatedAt
        )
    }

    func toSavedSprayPreset() -> SavedSprayPreset {
        SavedSprayPreset(
            id: id,
            vineyardId: vineyardId,
            name: name ?? "",
            waterVolume: waterVolume ?? 0,
            sprayRatePerHa: sprayRatePerHa ?? 0,
            concentrationFactor: concentrationFactor ?? 1.0
        )
    }
}

// MARK: - Spray Equipment

nonisolated struct BackendSprayEquipment: Codable, Sendable, Identifiable {
    let id: UUID
    let vineyardId: UUID
    let name: String?
    let tankCapacityLitres: Double?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?
    let clientUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case name
        case tankCapacityLitres = "tank_capacity_litres"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case clientUpdatedAt = "client_updated_at"
    }
}

nonisolated struct BackendSprayEquipmentUpsert: Encodable, Sendable {
    let id: UUID
    let vineyardId: UUID
    let name: String
    let tankCapacityLitres: Double
    let createdBy: UUID?
    let clientUpdatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case name
        case tankCapacityLitres = "tank_capacity_litres"
        case createdBy = "created_by"
        case clientUpdatedAt = "client_updated_at"
    }
}

extension BackendSprayEquipment {
    static func upsert(from e: SprayEquipmentItem, createdBy: UUID?, clientUpdatedAt: Date) -> BackendSprayEquipmentUpsert {
        BackendSprayEquipmentUpsert(
            id: e.id,
            vineyardId: e.vineyardId,
            name: e.name,
            tankCapacityLitres: e.tankCapacityLitres,
            createdBy: createdBy,
            clientUpdatedAt: clientUpdatedAt
        )
    }

    func toSprayEquipmentItem() -> SprayEquipmentItem {
        SprayEquipmentItem(
            id: id,
            vineyardId: vineyardId,
            name: name ?? "",
            tankCapacityLitres: tankCapacityLitres ?? 0
        )
    }
}

// MARK: - Tractors

nonisolated struct BackendTractor: Codable, Sendable, Identifiable {
    let id: UUID
    let vineyardId: UUID
    let name: String?
    let brand: String?
    let model: String?
    let modelYear: Int?
    let fuelUsageLPerHour: Double?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?
    let clientUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case name
        case brand
        case model
        case modelYear = "model_year"
        case fuelUsageLPerHour = "fuel_usage_l_per_hour"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case clientUpdatedAt = "client_updated_at"
    }
}

nonisolated struct BackendTractorUpsert: Encodable, Sendable {
    let id: UUID
    let vineyardId: UUID
    let name: String
    let brand: String
    let model: String
    let modelYear: Int?
    let fuelUsageLPerHour: Double
    let createdBy: UUID?
    let clientUpdatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case name
        case brand
        case model
        case modelYear = "model_year"
        case fuelUsageLPerHour = "fuel_usage_l_per_hour"
        case createdBy = "created_by"
        case clientUpdatedAt = "client_updated_at"
    }
}

extension BackendTractor {
    static func upsert(from t: Tractor, createdBy: UUID?, clientUpdatedAt: Date) -> BackendTractorUpsert {
        BackendTractorUpsert(
            id: t.id,
            vineyardId: t.vineyardId,
            name: t.name,
            brand: t.brand,
            model: t.model,
            modelYear: t.modelYear,
            fuelUsageLPerHour: t.fuelUsageLPerHour,
            createdBy: createdBy,
            clientUpdatedAt: clientUpdatedAt
        )
    }

    func toTractor() -> Tractor {
        Tractor(
            id: id,
            vineyardId: vineyardId,
            name: name ?? "",
            brand: brand ?? "",
            model: model ?? "",
            modelYear: modelYear,
            fuelUsageLPerHour: fuelUsageLPerHour ?? 0
        )
    }
}

// MARK: - Fuel Purchases

nonisolated struct BackendFuelPurchase: Codable, Sendable, Identifiable {
    let id: UUID
    let vineyardId: UUID
    let volumeLitres: Double?
    let totalCost: Double?
    let date: Date?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?
    let clientUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case volumeLitres = "volume_litres"
        case totalCost = "total_cost"
        case date
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case clientUpdatedAt = "client_updated_at"
    }
}

nonisolated struct BackendFuelPurchaseUpsert: Encodable, Sendable {
    let id: UUID
    let vineyardId: UUID
    let volumeLitres: Double
    let totalCost: Double
    let date: Date
    let createdBy: UUID?
    let clientUpdatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case volumeLitres = "volume_litres"
        case totalCost = "total_cost"
        case date
        case createdBy = "created_by"
        case clientUpdatedAt = "client_updated_at"
    }
}

extension BackendFuelPurchase {
    static func upsert(from f: FuelPurchase, createdBy: UUID?, clientUpdatedAt: Date) -> BackendFuelPurchaseUpsert {
        BackendFuelPurchaseUpsert(
            id: f.id,
            vineyardId: f.vineyardId,
            volumeLitres: f.volumeLitres,
            totalCost: f.totalCost,
            date: f.date,
            createdBy: createdBy,
            clientUpdatedAt: clientUpdatedAt
        )
    }

    func toFuelPurchase() -> FuelPurchase {
        FuelPurchase(
            id: id,
            vineyardId: vineyardId,
            volumeLitres: volumeLitres ?? 0,
            totalCost: totalCost ?? 0,
            date: date ?? Date()
        )
    }
}

// MARK: - Operator Categories

nonisolated struct BackendOperatorCategory: Codable, Sendable, Identifiable {
    let id: UUID
    let vineyardId: UUID
    let name: String?
    let costPerHour: Double?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?
    let clientUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case name
        case costPerHour = "cost_per_hour"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case clientUpdatedAt = "client_updated_at"
    }
}

nonisolated struct BackendOperatorCategoryUpsert: Encodable, Sendable {
    let id: UUID
    let vineyardId: UUID
    let name: String
    let costPerHour: Double
    let createdBy: UUID?
    let clientUpdatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case name
        case costPerHour = "cost_per_hour"
        case createdBy = "created_by"
        case clientUpdatedAt = "client_updated_at"
    }
}

extension BackendOperatorCategory {
    static func upsert(from o: OperatorCategory, createdBy: UUID?, clientUpdatedAt: Date) -> BackendOperatorCategoryUpsert {
        BackendOperatorCategoryUpsert(
            id: o.id,
            vineyardId: o.vineyardId,
            name: o.name,
            costPerHour: o.costPerHour,
            createdBy: createdBy,
            clientUpdatedAt: clientUpdatedAt
        )
    }

    func toOperatorCategory() -> OperatorCategory {
        OperatorCategory(
            id: id,
            vineyardId: vineyardId,
            name: name ?? "",
            costPerHour: costPerHour ?? 0
        )
    }
}

// MARK: - Work Task Types

nonisolated struct BackendWorkTaskType: Codable, Sendable, Identifiable {
    let id: UUID
    let vineyardId: UUID
    let name: String?
    let isDefault: Bool?
    let sortOrder: Int?
    let createdBy: UUID?
    let updatedBy: UUID?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?
    let clientUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case name
        case isDefault = "is_default"
        case sortOrder = "sort_order"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case clientUpdatedAt = "client_updated_at"
    }

    // Per-row resilient decode: tolerate missing optional fields and
    // string-encoded dates from PostgREST so one malformed row does not
    // break sync for the rest of the vineyard's catalog.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.vineyardId = try c.decode(UUID.self, forKey: .vineyardId)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault)
        self.sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder)
        self.createdBy = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
        self.updatedBy = try c.decodeIfPresent(UUID.self, forKey: .updatedBy)
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

nonisolated struct BackendWorkTaskTypeUpsert: Encodable, Sendable {
    let id: UUID
    let vineyardId: UUID
    let name: String
    let isDefault: Bool
    let sortOrder: Int
    let createdBy: UUID?
    let updatedBy: UUID?
    let clientUpdatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case name
        case isDefault = "is_default"
        case sortOrder = "sort_order"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case clientUpdatedAt = "client_updated_at"
    }
}

extension BackendWorkTaskType {
    static func upsert(
        from t: WorkTaskType,
        createdBy: UUID?,
        updatedBy: UUID?,
        clientUpdatedAt: Date
    ) -> BackendWorkTaskTypeUpsert {
        BackendWorkTaskTypeUpsert(
            id: t.id,
            vineyardId: t.vineyardId,
            name: t.name,
            isDefault: t.isDefault,
            sortOrder: t.sortOrder,
            createdBy: createdBy,
            updatedBy: updatedBy,
            clientUpdatedAt: clientUpdatedAt
        )
    }

    func toWorkTaskType() -> WorkTaskType {
        WorkTaskType(
            id: id,
            vineyardId: vineyardId,
            name: name ?? "",
            isDefault: isDefault ?? false,
            sortOrder: sortOrder ?? 0
        )
    }
}

// MARK: - Equipment Items ("Other")

nonisolated struct BackendEquipmentItem: Codable, Sendable, Identifiable {
    let id: UUID
    let vineyardId: UUID
    let name: String?
    let category: String?
    let make: String?
    let model: String?
    let serialNumber: String?
    let notes: String?
    let createdBy: UUID?
    let updatedBy: UUID?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?
    let clientUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case name
        case category
        case make
        case model
        case serialNumber = "serial_number"
        case notes
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case clientUpdatedAt = "client_updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.vineyardId = try c.decode(UUID.self, forKey: .vineyardId)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.category = try c.decodeIfPresent(String.self, forKey: .category)
        self.make = try c.decodeIfPresent(String.self, forKey: .make)
        self.model = try c.decodeIfPresent(String.self, forKey: .model)
        self.serialNumber = try c.decodeIfPresent(String.self, forKey: .serialNumber)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.createdBy = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
        self.updatedBy = try c.decodeIfPresent(UUID.self, forKey: .updatedBy)
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

nonisolated struct BackendEquipmentItemUpsert: Encodable, Sendable {
    let id: UUID
    let vineyardId: UUID
    let name: String
    let category: String
    let make: String?
    let model: String?
    let serialNumber: String?
    let notes: String
    let createdBy: UUID?
    let updatedBy: UUID?
    let clientUpdatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case vineyardId = "vineyard_id"
        case name
        case category
        case make
        case model
        case serialNumber = "serial_number"
        case notes
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case clientUpdatedAt = "client_updated_at"
    }
}

extension BackendEquipmentItem {
    static func upsert(
        from item: EquipmentItem,
        createdBy: UUID?,
        updatedBy: UUID?,
        clientUpdatedAt: Date
    ) -> BackendEquipmentItemUpsert {
        BackendEquipmentItemUpsert(
            id: item.id,
            vineyardId: item.vineyardId,
            name: item.name,
            category: item.category.isEmpty ? "other" : item.category,
            make: item.make,
            model: item.model,
            serialNumber: item.serialNumber,
            notes: item.notes,
            createdBy: createdBy,
            updatedBy: updatedBy,
            clientUpdatedAt: clientUpdatedAt
        )
    }

    func toEquipmentItem() -> EquipmentItem {
        EquipmentItem(
            id: id,
            vineyardId: vineyardId,
            name: name ?? "",
            category: category ?? "other",
            make: make,
            model: model,
            serialNumber: serialNumber,
            notes: notes ?? ""
        )
    }
}
