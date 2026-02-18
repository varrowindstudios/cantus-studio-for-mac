import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum AppIconManager {
    static var supportsAlternateIcons: Bool {
#if canImport(UIKit)
        return UIApplication.shared.supportsAlternateIcons
#else
        return false
#endif
    }

    static func currentAlternateName() -> String? {
#if canImport(UIKit)
        return UIApplication.shared.alternateIconName
#else
        return nil
#endif
    }

    static func setAlternateIconName(_ name: String?) async throws {
#if canImport(UIKit)
        try await UIApplication.shared.setAlternateIconName(name)
#else
        _ = name
#endif
    }
}
