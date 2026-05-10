import SwiftUI

/// Brand wordmark color used for the "Track" half of the VineTrack name.
/// Hex #85B830.
enum BrandColors {
    static let track: Color = Color(red: 133.0 / 255.0, green: 184.0 / 255.0, blue: 48.0 / 255.0)
}

/// Brand typography helpers. The wordmark uses Montserrat ExtraBold when the
/// font is available on the system, falling back to the heaviest system font
/// otherwise so the look stays consistent.
enum BrandTypography {
    /// Returns the Montserrat ExtraBold font at the given size, or a system
    /// black-weight fallback when Montserrat is not installed.
    static func wordmarkFont(size: CGFloat) -> Font {
        Font.custom("Montserrat-ExtraBold", size: size)
            .weight(.heavy)
    }

    /// Slightly tight letter spacing (~-1.5% of the font size) used for the
    /// VineTrack wordmark.
    static func wordmarkTracking(size: CGFloat) -> CGFloat {
        -size * 0.015
    }
}

/// Renders the VineTrack brand wordmark with "Vine" in white and
/// "Track" in the brand green (#85B830). Use this anywhere the
/// brand name is displayed as a title or header so the styling
/// stays consistent across the app.
struct BrandWordmark: View {
    var size: CGFloat = 38
    var vineColor: Color = .white
    var trackColor: Color = BrandColors.track

    var body: some View {
        (
            Text("Vine").foregroundStyle(vineColor)
            + Text("Track").foregroundStyle(trackColor)
        )
        .font(BrandTypography.wordmarkFont(size: size))
        .tracking(BrandTypography.wordmarkTracking(size: size))
    }
}

/// Same wordmark but built as an AttributedString so it can be
/// dropped into contexts that take a `Text` with mixed content.
extension AttributedString {
    static func vineTrackBrand(
        size: CGFloat = 38,
        vineColor: Color = .white,
        trackColor: Color = BrandColors.track
    ) -> AttributedString {
        var vine = AttributedString("Vine")
        vine.foregroundColor = vineColor
        vine.font = BrandTypography.wordmarkFont(size: size)
        vine.tracking = BrandTypography.wordmarkTracking(size: size)
        var track = AttributedString("Track")
        track.foregroundColor = trackColor
        track.font = BrandTypography.wordmarkFont(size: size)
        track.tracking = BrandTypography.wordmarkTracking(size: size)
        return vine + track
    }
}

/// Builds a `Text` that automatically stylises any occurrence of
/// the literal substring "VineTrack" with the brand wordmark colours
/// ("Vine" in `vineColor`, "Track" in `trackColor`). Useful for titles
/// like "Welcome to VineTrack" where we still want to keep the
/// surrounding text rendered in the caller's default style.
///
/// When `applyBrandFont` is true the matched "VineTrack" tokens also use
/// the Montserrat ExtraBold wordmark font and tight tracking. Surrounding
/// text keeps the caller's font.
func brandedText(
    _ string: String,
    vineColor: Color? = nil,
    trackColor: Color = BrandColors.track,
    applyBrandFont: Bool = false,
    brandSize: CGFloat = 17
) -> Text {
    let token = "VineTrack"
    var result = Text("")
    var remaining = string[...]
    while let range = remaining.range(of: token) {
        let prefix = remaining[remaining.startIndex..<range.lowerBound]
        if !prefix.isEmpty {
            result = result + Text(String(prefix))
        }
        var vinePart = Text("Vine")
        var trackPart = Text("Track").foregroundStyle(trackColor)
        if applyBrandFont {
            let f = BrandTypography.wordmarkFont(size: brandSize)
            let t = BrandTypography.wordmarkTracking(size: brandSize)
            vinePart = vinePart.font(f).tracking(t)
            trackPart = trackPart.font(f).tracking(t)
        }
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
