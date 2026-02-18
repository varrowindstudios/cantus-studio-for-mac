import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

enum CantusTextInputAutocapitalization {
    case never
    case words
}

extension View {
    @ViewBuilder
    func cantusInsetGroupedListStyle() -> some View {
#if os(iOS)
        self.listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .hoverEffectDisabled(true)
#else
        self
#endif
    }

    @ViewBuilder
    func cantusTextInputAutocapitalization(_ style: CantusTextInputAutocapitalization) -> some View {
#if os(iOS)
        switch style {
        case .never:
            self.textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        case .words:
            self.textInputAutocapitalization(.words)
                .disableAutocorrection(true)
        }
#else
        self
#endif
    }

    @ViewBuilder
    func cantusDisableAutocorrection() -> some View {
#if os(iOS)
        self.disableAutocorrection(true)
#else
        self
#endif
    }
}

extension Color {
    static var cantusSecondarySystemFill: Color {
#if canImport(UIKit)
        return Color(.secondarySystemFill)
#elseif canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor).opacity(0.8)
#else
        return Color.gray.opacity(0.25)
#endif
    }

    static var cantusTertiarySystemFill: Color {
#if canImport(UIKit)
        return Color(.tertiarySystemFill)
#elseif canImport(AppKit)
        return Color(nsColor: .controlBackgroundColor).opacity(0.9)
#else
        return Color.gray.opacity(0.18)
#endif
    }
}
