import SwiftUI

struct LaunchBrandMark: View {
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.primaryLight, .white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .stroke(AppTheme.primary.opacity(0.12), lineWidth: 1)
                )

            Image(systemName: "pills.fill")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: size, height: size)
        .shadow(color: AppTheme.primary.opacity(0.14), radius: 18, y: 8)
    }
}

struct LaunchScreenView: View {
    var locale: Locale = .current
    var showsProgress = true

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            VStack(spacing: 20) {
                LaunchBrandMark()

                VStack(spacing: 8) {
                    Text(L10n.t("app.title", locale: locale))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(L10n.t("app.subtitle", locale: locale))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            if showsProgress {
                VStack {
                    Spacer()
                    ProgressView()
                        .tint(AppTheme.primary)
                        .padding(.bottom, 56)
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

#Preview {
    LaunchScreenView()
}
