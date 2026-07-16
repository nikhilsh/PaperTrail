import SwiftUI

/// Tiny standalone palette for the widget extension. Deliberately not
/// sharing `PT`/`PTTheme` from the app target — there's no shared framework
/// between targets, and the widget doesn't need the app's full theme, just
/// these few colors.
enum WidgetPalette {
    /// Dark warm background.
    static let background = Color(red: 0x14 / 255, green: 0x12 / 255, blue: 0x10 / 255)
    /// Primary text.
    static let cream = Color(red: 0xEF / 255, green: 0xE6 / 255, blue: 0xD2 / 255)
    /// Default accent, healthy/far-out dates.
    static let gold = Color(red: 0xC2 / 255, green: 0xA1 / 255, blue: 0x5C / 255)
    /// Due within a week.
    static let amber = Color(red: 0xD9 / 255, green: 0x8A / 255, blue: 0x3D / 255)
    /// Due today or already past.
    static let terra = Color(red: 0xB5 / 255, green: 0x4A / 255, blue: 0x3C / 255)
}
