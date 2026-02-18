import SwiftUI

struct SetupView: View {
    @Binding var hasCompletedSetup: Bool
    @EnvironmentObject private var theme: ThemeModel

    var body: some View {
        ZStack {
            CantusBackground()

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Cantus")
                        .font(.largeTitle)
                    Text("ROLEPLAY DJ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    Text("Welcome to Cantus")
                        .font(.title2)

                    Text("To get started, connect your music service so you can build and play epic soundtracks for your roleplaying adventures.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(spacing: 14) {
                    Button {
                        hasCompletedSetup = true
                    } label: {
                        Label("Connect to Apple Music", systemImage: "music.note")
                            .font(.body)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        hasCompletedSetup = true
                    } label: {
                        Label("Connect to Spotify", systemImage: "dot.radiowaves.left.and.right")
                            .font(.body)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal, 28)
                .padding(.top, 12)

                Spacer()
            }
            .padding(.top, 60)
        }
    }
}

#Preview {
    SetupView(hasCompletedSetup: .constant(false))
}
