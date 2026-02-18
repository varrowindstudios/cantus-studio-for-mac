import SwiftUI

@available(iOS 18.0, *)
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Cantus")
                .font(.title)
                .fontWeight(.bold)
            Text("Roleplay DJ")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Version 0.2.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(.thinMaterial)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                ToolbarIconButton(systemName: "xmark", action: { dismiss() }, accessibilityLabel: "Close")
            }
        }
    }
}
