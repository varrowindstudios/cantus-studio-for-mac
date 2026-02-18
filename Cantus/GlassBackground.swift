import SwiftUI

extension View {
    @ViewBuilder
    func cantusGlassBackground() -> some View {
        cantusGlassEffectRegular(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder
    func cantusGlassEffectRegular<S: Shape>(in shape: S) -> some View {
        #if compiler(>=6.0)
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
        #else
        self.background(.regularMaterial, in: shape)
        #endif
    }

    @ViewBuilder
    func cantusGlassEffectClear<S: Shape>(in shape: S) -> some View {
        #if compiler(>=6.0)
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.clear, in: shape)
        } else {
            self.background(.thinMaterial, in: shape)
        }
        #else
        self.background(.thinMaterial, in: shape)
        #endif
    }
}
