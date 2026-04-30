import Foundation

nonisolated struct GrapeVariety: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var vineyardId: UUID
    var name: String
    var optimalGDD: Double
    var isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        vineyardId: UUID = UUID(),
        name: String,
        optimalGDD: Double,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.vineyardId = vineyardId
        self.name = name
        self.optimalGDD = optimalGDD
        self.isBuiltIn = isBuiltIn
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case id, vineyardId, name, optimalGDD, isBuiltIn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        vineyardId = try c.decode(UUID.self, forKey: .vineyardId)
        name = try c.decode(String.self, forKey: .name)
        optimalGDD = try c.decode(Double.self, forKey: .optimalGDD)
        isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }
}

extension GrapeVariety {
    static func defaults(for vineyardId: UUID) -> [GrapeVariety] {
        // Optimal growing degree days (base 10°C) to harvest ripeness.
        // Values are typical ranges from viticulture references.
        // Approx BEDD (Biologically Effective Degree Days) values from viticulture reference table.
        // Midpoint used for ranges.
        let data: [(String, Double)] = [
            ("Chardonnay", 1145),
            ("Pinot Gris / Grigio", 1100),
            ("Riesling", 1200),
            ("Sauvignon Blanc", 1150),
            ("Semillon", 1200),
            ("Chenin Blanc", 1250),
            ("Gewurztraminer", 1150),
            ("Viognier", 1260),
            ("Shiraz", 1255),
            ("Merlot", 1250),
            ("Cabernet Franc", 1255),
            ("Cabernet Sauvignon", 1310),
            ("Pinot Noir", 1145),
            ("Tempranillo", 1230),
            ("Sangiovese", 1285),
            ("Grenache", 1365),
            ("Mataro / Mourvedre", 1440),
            ("Barbera", 1285),
            ("Malbec", 1230),
            ("Colombard", 1300),
            ("Muscat Gordo Blanco", 1350),
            ("Fiano", 1320),
            ("Prosecco", 1410),
            ("Vermentino", 1290),
            ("Gruner Veltliner", 1200),
            ("Primitivo", 1200)
        ]
        return data.map { GrapeVariety(vineyardId: vineyardId, name: $0.0, optimalGDD: $0.1, isBuiltIn: true) }
    }
}

nonisolated struct PaddockVarietyAllocation: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var varietyId: UUID
    var percent: Double

    init(id: UUID = UUID(), varietyId: UUID, percent: Double) {
        self.id = id
        self.varietyId = varietyId
        self.percent = percent
    }

    nonisolated enum CodingKeys: String, CodingKey {
        case id, varietyId, percent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        varietyId = try c.decode(UUID.self, forKey: .varietyId)
        percent = try c.decode(Double.self, forKey: .percent)
    }
}
