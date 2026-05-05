import Foundation
import CoreLocation

/// Maps a multi-block selection into a single global row/path index, sorted in
/// the same order used by `StartTripSheet` (lowest local row first, then by
/// name). Used at runtime by Active Trip to convert a local row hit inside a
/// paddock into a global path number that lines up with `trip.rowSequence`.
nonisolated struct GlobalRowIndex: Sendable {
    struct Entry: Sendable, Hashable {
        let paddockId: UUID
        let paddockName: String
        let globalRowStart: Int   // 1-based, inclusive
        let globalRowEnd: Int     // 1-based, inclusive
        let localRowStart: Int    // typically 1
        let rowCount: Int
    }

    let entries: [Entry]
    let totalRows: Int

    init(paddocks: [Paddock]) {
        let sorted = paddocks.sorted { a, b in
            let aMin = a.rows.map(\.number).min() ?? Int.max
            let bMin = b.rows.map(\.number).min() ?? Int.max
            if aMin != bMin { return aMin < bMin }
            return a.name.lowercased() < b.name.lowercased()
        }

        var built: [Entry] = []
        var cursor = 0
        for paddock in sorted {
            let rows = paddock.rows
            let count = rows.count
            guard count > 0 else { continue }
            let localStart = rows.map(\.number).min() ?? 1
            built.append(Entry(
                paddockId: paddock.id,
                paddockName: paddock.name,
                globalRowStart: cursor + 1,
                globalRowEnd: cursor + count,
                localRowStart: localStart,
                rowCount: count
            ))
            cursor += count
        }
        self.entries = built
        self.totalRows = cursor
    }

    /// Find which entry contains the given global row number.
    func entry(forGlobalRow globalRow: Int) -> Entry? {
        entries.first { globalRow >= $0.globalRowStart && globalRow <= $0.globalRowEnd }
    }

    /// Convert a local row inside a paddock to a global row number.
    func globalRow(paddockId: UUID, localRow: Int) -> Int? {
        guard let entry = entries.first(where: { $0.paddockId == paddockId }) else { return nil }
        let offset = localRow - entry.localRowStart
        guard offset >= 0, offset < entry.rowCount else { return nil }
        return entry.globalRowStart + offset
    }
}
