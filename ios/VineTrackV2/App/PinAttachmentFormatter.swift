import Foundation

/// Customer-facing wording for "this pin is attached to row/path X.5 — Side".
/// Stored `rowNumber` is an integer X representing the path between rows X and
/// X+1, displayed as "X.5" in the UI. Side is preserved when known.
nonisolated enum PinAttachmentFormatter {

    /// e.g. "Row 19.5", "Row 19.5 — Left", or nil when no row context.
    static func rowAndSide(rowNumber: Int?, side: PinSide?) -> String? {
        guard let rowNumber else { return nil }
        let row = "Row \(rowNumber).5"
        guard let side else { return row }
        return "\(row) — \(side.rawValue)"
    }

    /// e.g. "Attached to Row 19.5 — Left", or "Pin location not snapped to a row"
    /// when the active trip has no confident row lock.
    static func attachedTo(rowNumber: Int?, side: PinSide?) -> String {
        if let label = rowAndSide(rowNumber: rowNumber, side: side) {
            return "Attached to \(label)"
        }
        return "Pin location not snapped to a row"
    }

    /// Short subtitle suitable for confirmation toasts. Falls back to a side
    /// label when no row is known.
    static func toastSubtitle(rowNumber: Int?, side: PinSide) -> String {
        if let row = rowNumber {
            return "Attached to Row \(row).5 — \(side.rawValue)"
        }
        return "\(side.rawValue) side"
    }
}
