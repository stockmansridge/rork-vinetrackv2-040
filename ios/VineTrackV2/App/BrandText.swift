import SwiftUI

/// Brand wordmark color used for the "Track" half of the VineTrack name.
/// Hex #88BC30.
enum BrandColors {
    static let track: Color = Color(red: 136.0 / 255.0, green: 188.0 / 255.0, blue: 48.0 / 255.0)
}

/// Renders the VineTrack brand wordmark with "Vine" in white and
/// "Track" in the brand green (#88BC30). Use this anywhere the
/// brand name is displayed as a title or header so the styling
/// stays consistent across the app.
struct BrandWordmark: View {
    var font: Font = .system(size: 38, weight: .heavy)
    var vineColor: Color = .white
    var trackColor: Color = BrandColors.track

    var body: some View {
        (
            Text("Vine").foregroundStyle(vineColor)
            + Text("Track").foregroundStyle(trackColor)
        )
        .font(font)
    }
}

/// Same wordmark but built as an AttributedString so it can be
/// dropped into contexts that take a `Text` with mixed content.
extension AttributedString {
    static func vineTrackBrand(
        vineColor: Color = .white,
        trackColor: Color = BrandColors.track
    ) -> AttributedString {
        var vine = AttributedString("Vine")
        vine.foregroundColor = vineColor
        var track = AttributedString("Track")
        track.foregroundColor = trackColor
        return vine + track
    }
}

/// Builds a `Text` that automatically stylises any occurrence of
/// the literal substring "VineTrack" with the brand wordmark colours
/// ("Vine" in `vineColor`, "Track" in `trackColor`). Useful for titles
/// like "Welcome to VineTrack" where we still want to keep the
/// surrounding text rendered in the caller's default style.
func brandedText(
    _ string: String,
    vineColor: Color? = nil,
    trackColor: Color = BrandColors.track
) -> Text {
    let token = "VineTrack"
    var result = Text("")
    var remaining = string[...]
    while let range = remaining.range(of: token) {
        let prefix = remaining[remaining.startIndex..<range.lowerBound]
        if !prefix.isEmpty {
            result = result + Text(String(prefix))
        }
        let vinePart = Text("Vine")
        let trackPart = Text("Track").foregroundStyle(trackColor)
        if let vineColor {
            result = result + vinePart.foregroundStyle(vineColor) + trackPart
        } else {
            result = result + vinePart + trackPart
        }
        remaining = remaining[range.upperBound...]
    }
    if !remaining.isEmpty {
        result = result + Text(String(remaining))
    }
    return result
}
