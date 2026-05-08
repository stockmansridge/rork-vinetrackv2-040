import Foundation

/// Optional structured Seeding Details payload attached to a Trip when
/// `tripFunction == "seeding"`. Persisted as JSONB at `trips.seeding_details`
/// in Supabase. All fields are optional. Nested keys are snake_case to match
/// the agreed JSON shape used by future Lovable reporting.
nonisolated struct SeedingBox: Codable, Sendable, Hashable {
    var mixName: String?
    var ratePerHa: Double?
    var shutterSlide: String?      // "3/4" | "Full"
    var bottomFlap: String?        // "1" | "3"
    var meteringWheel: String?     // "N" | "F"
    var seedVolumeKg: Double?
    var gearboxSetting: Double?

    init(
        mixName: String? = nil,
        ratePerHa: Double? = nil,
        shutterSlide: String? = nil,
        bottomFlap: String? = nil,
        meteringWheel: String? = nil,
        seedVolumeKg: Double? = nil,
        gearboxSetting: Double? = nil
    ) {
        self.mixName = mixName
        self.ratePerHa = ratePerHa
        self.shutterSlide = shutterSlide
        self.bottomFlap = bottomFlap
        self.meteringWheel = meteringWheel
        self.seedVolumeKg = seedVolumeKg
        self.gearboxSetting = gearboxSetting
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case mixName = "mix_name"
        case ratePerHa = "rate_per_ha"
        case shutterSlide = "shutter_slide"
        case bottomFlap = "bottom_flap"
        case meteringWheel = "metering_wheel"
        case seedVolumeKg = "seed_volume_kg"
        case gearboxSetting = "gearbox_setting"
    }

    var hasAnyValue: Bool {
        let trimmedMix = mixName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedMix.isEmpty { return true }
        if ratePerHa != nil { return true }
        if !(shutterSlide?.isEmpty ?? true) { return true }
        if !(bottomFlap?.isEmpty ?? true) { return true }
        if !(meteringWheel?.isEmpty ?? true) { return true }
        if seedVolumeKg != nil { return true }
        if gearboxSetting != nil { return true }
        return false
    }
}

nonisolated struct SeedingMixLine: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String?
    var percentOfMix: Double?
    var seedBox: String?    // "Front" | "Back"
    var kgPerHa: Double?
    var supplierManufacturer: String?

    init(
        id: UUID = UUID(),
        name: String? = nil,
        percentOfMix: Double? = nil,
        seedBox: String? = nil,
        kgPerHa: Double? = nil,
        supplierManufacturer: String? = nil
    ) {
        self.id = id
        self.name = name
        self.percentOfMix = percentOfMix
        self.seedBox = seedBox
        self.kgPerHa = kgPerHa
        self.supplierManufacturer = supplierManufacturer
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case id
        case name
        case percentOfMix = "percent_of_mix"
        case seedBox = "seed_box"
        case kgPerHa = "kg_per_ha"
        case supplierManufacturer = "supplier_manufacturer"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name)
        percentOfMix = try c.decodeIfPresent(Double.self, forKey: .percentOfMix)
        seedBox = try c.decodeIfPresent(String.self, forKey: .seedBox)
        kgPerHa = try c.decodeIfPresent(Double.self, forKey: .kgPerHa)
        supplierManufacturer = try c.decodeIfPresent(String.self, forKey: .supplierManufacturer)
    }

    var hasAnyValue: Bool {
        if !(name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) { return true }
        if percentOfMix != nil { return true }
        if !(seedBox?.isEmpty ?? true) { return true }
        if kgPerHa != nil { return true }
        if !(supplierManufacturer?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) { return true }
        return false
    }
}

nonisolated struct SeedingDetails: Codable, Sendable, Hashable {
    var frontBox: SeedingBox?
    var backBox: SeedingBox?
    var sowingDepthCm: Double?
    var mixLines: [SeedingMixLine]?

    init(
        frontBox: SeedingBox? = nil,
        backBox: SeedingBox? = nil,
        sowingDepthCm: Double? = nil,
        mixLines: [SeedingMixLine]? = nil
    ) {
        self.frontBox = frontBox
        self.backBox = backBox
        self.sowingDepthCm = sowingDepthCm
        self.mixLines = mixLines
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case frontBox = "front_box"
        case backBox = "back_box"
        case sowingDepthCm = "sowing_depth_cm"
        case mixLines = "mix_lines"
    }

    /// True when at least one field has a meaningful value entered.
    var hasAnyValue: Bool {
        if frontBox?.hasAnyValue == true { return true }
        if backBox?.hasAnyValue == true { return true }
        if sowingDepthCm != nil { return true }
        if let lines = mixLines, lines.contains(where: { $0.hasAnyValue }) { return true }
        return false
    }
}
