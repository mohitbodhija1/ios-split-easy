import SwiftUI

/// Visual tokens aligned with the SplitEasy-style HTML mockups (purple accent, grouped gray surfaces).
enum SplitMateTheme {
    static let brandPurple = Color(red: 108 / 255, green: 99 / 255, blue: 255 / 255)
    static let brandPink = Color(red: 224 / 255, green: 64 / 255, blue: 251 / 255)
    static let brandPurpleSoft = Color(red: 156 / 255, green: 143 / 255, blue: 1)

    static let groupedBackground = Color(red: 242 / 255, green: 242 / 255, blue: 247 / 255)
    static let labelPrimary = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    static let labelSecondary = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    static let separator = Color(red: 224 / 255, green: 224 / 255, blue: 229 / 255)

    static let negativeRed = Color(red: 1, green: 59 / 255, blue: 48 / 255)
    static let positiveGreen = Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)
    static let orangeAccent = Color(red: 1, green: 149 / 255, blue: 0)

    static func inrString(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "INR"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f.string(from: NSNumber(value: amount)) ?? String(format: "₹%.2f", amount)
    }

    static var brandIconGradient: LinearGradient {
        LinearGradient(
            colors: [brandPurple, brandPink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
