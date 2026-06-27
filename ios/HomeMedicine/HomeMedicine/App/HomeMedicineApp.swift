import SwiftUI
import SwiftData

@main
struct HomeMedicineApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var bootstrap = AppBootstrap()

    var body: some Scene {
        WindowGroup {
            Group {
                if bootstrap.isReady, let modelContainer = bootstrap.modelContainer {
                    ContentView()
                        .environmentObject(bootstrap.settingsStore)
                        .environmentObject(bootstrap.localizationManager)
                        .environmentObject(bootstrap.quotaStore)
                        .environmentObject(bootstrap.subscriptionManager)
                        .modelContainer(modelContainer)
                        .transition(.opacity)
                } else {
                    LaunchScreenView(locale: bootstrap.localizationManager.locale)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: bootstrap.isReady)
            .preferredColorScheme(.light)
            .task {
                await bootstrap.loadIfNeeded()
            }
            .onChange(of: bootstrap.isReady) { _, isReady in
                guard isReady else { return }
                AppRatingManager.shared.recordLaunchIfNeeded(settings: bootstrap.settingsStore)
                AppRatingManager.shared.requestReviewIfEligible(settings: bootstrap.settingsStore)
            }
        }
    }
}
