import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum CantusColors {
    static let CantusPink = Color(red: 255.0 / 255.0, green: 23.0 / 255.0, blue: 124.0 / 255.0)
    static let CantusIndigo = Color(red: 84.0 / 255.0, green: 19.0 / 255.0, blue: 136.0 / 255.0)
    static let CantusSpace = Color(red: 28.0 / 255.0, green: 23.0 / 255.0, blue: 54.0 / 255.0)
    static let CantusCyan = Color(red: 11.0 / 255.0, green: 234.0 / 255.0, blue: 173.0 / 255.0)
    static let CantusDungeonRed = Color(red: 197.0 / 255.0, green: 0.0 / 255.0, blue: 9.0 / 255.0)
    static let CantusDungeonGold = Color(red: 215.0 / 255.0, green: 190.0 / 255.0, blue: 130.0 / 255.0)
    static let CantusDungeonBlack = Color(red: 20.0 / 255.0, green: 24.0 / 255.0, blue: 29.0 / 255.0)
    static let CantusDungeonDarkRed = Color(red: 96.0 / 255.0, green: 0.0 / 255.0, blue: 14.0 / 255.0)
    static let CantusSage = Color(red: 106.0 / 255.0, green: 184.0 / 255.0, blue: 148.0 / 255.0)
    static let CantusSageLight = Color(red: 176.0 / 255.0, green: 224.0 / 255.0, blue: 198.0 / 255.0)
    static let CantusSageDusk = Color(red: 46.0 / 255.0, green: 70.0 / 255.0, blue: 62.0 / 255.0)
    static let CantusRosePink = Color(red: 232.0 / 255.0, green: 124.0 / 255.0, blue: 167.0 / 255.0)
    static let CantusMidnightPlum = Color(red: 36.0 / 255.0, green: 26.0 / 255.0, blue: 46.0 / 255.0)
    static let CantusElectricGreen = Color(red: 0.0 / 255.0, green: 232.0 / 255.0, blue: 118.0 / 255.0)
    static let CantusNeonYellow = Color(red: 244.0 / 255.0, green: 242.0 / 255.0, blue: 112.0 / 255.0)
    static let CantusNeonNight = Color(red: 18.0 / 255.0, green: 22.0 / 255.0, blue: 20.0 / 255.0)
    static let CantusNeonGreenDeep = Color(red: 0.0 / 255.0, green: 138.0 / 255.0, blue: 80.0 / 255.0)
    static let CantusSoftOrchidPink = Color(red: 236.0 / 255.0, green: 130.0 / 255.0, blue: 186.0 / 255.0)
    static let CantusSoftOrchid = Color(red: 189.0 / 255.0, green: 144.0 / 255.0, blue: 218.0 / 255.0)
    static let CantusSoftOrchidNight = Color(red: 38.0 / 255.0, green: 26.0 / 255.0, blue: 52.0 / 255.0)
    static let CantusSoftOrchidDeep = Color(red: 128.0 / 255.0, green: 86.0 / 255.0, blue: 164.0 / 255.0)
    static let CantusGrayNight = Color(red: 18.0 / 255.0, green: 18.0 / 255.0, blue: 20.0 / 255.0)
    static let CantusGraySteel = Color(red: 156.0 / 255.0, green: 156.0 / 255.0, blue: 162.0 / 255.0)
    static let CantusGrayMist = Color(red: 208.0 / 255.0, green: 208.0 / 255.0, blue: 214.0 / 255.0)
    static let CantusGraySlate = Color(red: 86.0 / 255.0, green: 86.0 / 255.0, blue: 93.0 / 255.0)
    static let CantusBlueAbyss = Color(red: 8.0 / 255.0, green: 23.0 / 255.0, blue: 51.0 / 255.0)
    static let CantusBlueCurrent = Color(red: 43.0 / 255.0, green: 160.0 / 255.0, blue: 172.0 / 255.0)
    static let CantusBlueFoam = Color(red: 145.0 / 255.0, green: 198.0 / 255.0, blue: 242.0 / 255.0)
    static let CantusBlueDepth = Color(red: 21.0 / 255.0, green: 62.0 / 255.0, blue: 112.0 / 255.0)
    static let CantusInternationalOrange = Color(red: 255.0 / 255.0, green: 79.0 / 255.0, blue: 0.0 / 255.0)
    static let CantusInternationalOrangeDeep = Color(red: 160.0 / 255.0, green: 40.0 / 255.0, blue: 0.0 / 255.0)
    static let CantusSlateNight = Color(red: 26.0 / 255.0, green: 34.0 / 255.0, blue: 43.0 / 255.0)
    static let CantusSlateMist = Color(red: 151.0 / 255.0, green: 166.0 / 255.0, blue: 182.0 / 255.0)
    static let CantusSlateBlue = Color(red: 63.0 / 255.0, green: 81.0 / 255.0, blue: 99.0 / 255.0)
}

struct CantusThemePalette: Identifiable, Equatable {
    let id: String
    let name: String
    let accentPrimary: Color
    let accentSecondary: Color
    let background: Color
    let indigo: Color

    static let neon = CantusThemePalette(
        id: "neon",
        name: "Default",
        accentPrimary: CantusColors.CantusPink,
        accentSecondary: CantusColors.CantusCyan,
        background: CantusColors.CantusSpace,
        indigo: CantusColors.CantusIndigo
    )

    static let dungeonRed = CantusThemePalette(
        id: "dungeon_red",
        name: "Dungeon Red",
        accentPrimary: CantusColors.CantusDungeonRed,
        accentSecondary: CantusColors.CantusDungeonGold,
        background: CantusColors.CantusDungeonBlack,
        indigo: CantusColors.CantusDungeonDarkRed
    )

    static let sageRose = CantusThemePalette(
        id: "sage_rose",
        name: "Sage Rose",
        accentPrimary: CantusColors.CantusRosePink,
        accentSecondary: CantusColors.CantusSage,
        background: CantusColors.CantusSageDusk,
        indigo: CantusColors.CantusSageLight
    )

    static let electricLime = CantusThemePalette(
        id: "electric_lime",
        name: "Electric Lime",
        accentPrimary: CantusColors.CantusElectricGreen,
        accentSecondary: CantusColors.CantusNeonYellow,
        background: CantusColors.CantusNeonNight,
        indigo: CantusColors.CantusNeonGreenDeep
    )

    static let pinkPurple = CantusThemePalette(
        id: "pink_purple",
        name: "Soft Orchid",
        accentPrimary: CantusColors.CantusSoftOrchidPink,
        accentSecondary: CantusColors.CantusSoftOrchid,
        background: CantusColors.CantusSoftOrchidNight,
        indigo: CantusColors.CantusSoftOrchidDeep
    )

    static let fiftyShades = CantusThemePalette(
        id: "fifty_shades",
        name: "50 Shades",
        accentPrimary: CantusColors.CantusGrayMist,
        accentSecondary: CantusColors.CantusGraySteel,
        background: CantusColors.CantusGrayNight,
        indigo: CantusColors.CantusGraySlate
    )

    static let deepBlue = CantusThemePalette(
        id: "deep_blue",
        name: "Deep Blue",
        accentPrimary: CantusColors.CantusBlueFoam,
        accentSecondary: CantusColors.CantusBlueCurrent,
        background: CantusColors.CantusBlueAbyss,
        indigo: CantusColors.CantusBlueDepth
    )

    static let orangeSlate = CantusThemePalette(
        id: "orange_slate",
        name: "Orange Slate",
        accentPrimary: CantusColors.CantusInternationalOrange,
        accentSecondary: CantusColors.CantusInternationalOrange,
        background: CantusColors.CantusSlateNight,
        indigo: CantusColors.CantusInternationalOrangeDeep
    )

    static let all: [CantusThemePalette] = [
        .neon,
        .dungeonRed,
        .sageRose,
        .electricLime,
        .pinkPurple,
        .fiftyShades,
        .deepBlue,
        .orangeSlate
    ]
    static func palette(for id: String?) -> CantusThemePalette? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}

final class ThemeModel: ObservableObject {
    @Published private(set) var palette: CantusThemePalette
    private let storageKey = "CantusThemePalette"

    init() {
        let stored = UserDefaults.standard.string(forKey: storageKey)
        palette = CantusThemePalette.palette(for: stored) ?? .neon
    }

    func selectPalette(_ palette: CantusThemePalette) {
        guard self.palette != palette else { return }
        self.palette = palette
        UserDefaults.standard.set(palette.id, forKey: storageKey)
    }

    var color: Color { palette.accentSecondary }

    var headerColor: Color {
        palette.accentPrimary
    }

    var closeIconColor: Color {
        headerColor
    }

    var confirmIconColor: Color {
        palette.accentSecondary
    }

    var ellipsisIconColor: Color {
        .secondary
    }

    var gearIconColor: Color {
        .secondary
    }

    var plusIconColor: Color {
        .secondary
    }

    var mixSliderColor: Color {
        headerColor
    }

    var otherSliderColor: Color {
        palette.accentSecondary
    }

    var listHighlightColor: Color {
        otherSliderColor
    }

    var waveformStyle: AnyShapeStyle {
        AnyShapeStyle(palette.accentSecondary)
    }

    var backgroundColor: Color {
        palette.background
    }

    var indigoColor: Color {
        palette.indigo
    }

}

struct CantusBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var theme: ThemeModel

    var body: some View {
        let base = theme.backgroundColor
        LinearGradient(
            colors: [base, base],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct PlayBackground: View {
    @EnvironmentObject private var theme: ThemeModel

    var body: some View {
        theme.backgroundColor
            .ignoresSafeArea()
    }
}

struct PanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

extension View {
    func panelSurface() -> some View {
        modifier(PanelSurface())
    }

    func glassPanelSurface() -> some View {
        padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
