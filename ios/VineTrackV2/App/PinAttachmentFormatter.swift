import Foundation

/// Customer-facing wording for "this pin is attached to row/path X — Side".
///
/// New attachment model:
///   * `pin_row_number` is the actual vine row the issue is attached to
///     (e.g. 14 or 15). Display as `Row 14`.
///   * `driving_row_number` is the driving path / mid-row the tractor was
///     on (e.g. 14.5). Display as `Driving Path 14.5`.
///   * `pin_side` is the operator's-POV side. Display as `— Left/Right`.
///
/// Legacy fallback: when only the legacy integer `rowNumber` is stored,
/// it represented the driving path floor and is shown as `Row X.5`.
nonisolated enum PinAttachmentFormatter {

    /// Preferred attachment line, e.g.
    /// "Row 14 — Left" or "Row 14.5" (legacy).
    static func attachmentLine(_ pin: VinePin) -> String? {
        if let pinRow = pin.pinRowNumber {
            let base = "Row \(pinRow)"
            if let side = pin.pinSide ?? pin.side as PinSide? {
                return "\(base) — \(side.rawValue)"
            }
            return base
        }
        if let legacy = pin.rowNumber {
            return "Row \(legacy).5"
        }
        return nil
    }

    /// Optional second line for the driving path, e.g. "Driving Path 14.5".
    /// Returns nil when no driving_row_number is recorded or when it would
    /// duplicate the legacy attachment line.
    static func drivingPathLine(_ pin: VinePin) -> String? {
        guard let path = pin.drivingRowNumber else { return nil }
        let formatted = formatPath(path)
        return "Driving Path \(formatted)"
    }

    /// Subtitle for confirmation toasts after a pin is dropped during a
    /// trip. Prefers the resolved attached-row wording.
    static func toastSubtitle(
        attachment: PinAttachmentResolver.Attachment,
        fallbackSide: PinSide
    ) -> String {
        if attachment.snappedToRow,
           let row = attachment.pinRowNumber,
           let side = attachment.pinSide {
            return "Attached to Row \(row) — \(side.rawValue)"
        }
        if let path = attachment.drivingRowNumber {
            return "Driving Path \(formatPath(path)) — \(fallbackSide.rawValue) side"
        }
        return "\(fallbackSide.rawValue) side"
    }

    /// Short attached-to subtitle for inline labels (e.g. growth-stage toast).
    static func attachmentSubtitle(attachment: PinAttachmentResolver.Attachment) -> String? {
        if attachment.snappedToRow, let row = attachment.pinRowNumber {
            if let side = attachment.pinSide {
                return "Attached to Row \(row) — \(side.rawValue)"
            }
            return "Attached to Row \(row)"
        }
        if let path = attachment.drivingRowNumber {
            return "Driving Path \(formatPath(path))"
        }
        return nil
    }

    /// Legacy formatter kept for places that still pass raw rowNumber/side
    /// (e.g. older export paths). Prefer `attachmentLine(_:)` for new code.
    static func rowAndSide(rowNumber: Int?, side: PinSide?) -> String? {
        guard let rowNumber else { return nil }
        let row = "Row \(rowNumber).5"
        guard let side else { return row }
        return "\(row) — \(side.rawValue)"
    }

    /// Legacy "attached to" wording for cases without a VinePin instance.
    static func attachedTo(rowNumber: Int?, side: PinSide?) -> String {
        if let label = rowAndSide(rowNumber: rowNumber, side: side) {
            return "Attached to \(label)"
        }
        return "Pin location not snapped to a row"
    }

    private static func formatPath(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.1f", value)
        }
        // Trim trailing zeros while keeping at least one decimal for X.5 paths.
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
