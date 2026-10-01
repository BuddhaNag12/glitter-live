import SwiftUI

struct LibraryEmptyView: View {
    var onConvert: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(Theme.accent)
                Text("No wallpapers yet").typography(.headlineSmall).foregroundStyle(Theme.textPrimary)
                Text("Every live wallpaper you convert is kept here, so you can preview it, save it again, or set it later.")
                    .typography(.bodyMedium)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button(action: onConvert) {
                    Label("Convert a Video", systemImage: "livephoto")
                }
                .buttonStyle(GlassPillButtonStyle(tint: Theme.accent))
                .padding(.top, 4)
            }
            .padding(26)
            .glass(.floating, cornerRadius: 30)
            .padding(16)
            Spacer()
            Spacer()
        }
        .screenHeader("Library")
    }
}
