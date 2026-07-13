import SwiftUI
import UIKit

extension Color {
    /// Liftoff brand color #E86F4A.
    static let brand = Color(red: 0xE8 / 255, green: 0x6F / 255, blue: 0x4A / 255)

    init?(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// The white Liftoff logo bundled with the app.
enum Brand {
    static let logo: UIImage? = {
        guard let path = Bundle.main.path(forResource: "icon", ofType: "png") else { return nil }
        return UIImage(contentsOfFile: path)
    }()
}
