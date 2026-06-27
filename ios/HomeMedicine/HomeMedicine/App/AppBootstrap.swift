import SwiftData
import SwiftUI

@MainActor
final class AppBootstrap: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var modelContainer: ModelContainer?

    let settingsStore: SettingsStore
    let localizationManager: LocalizationManager
    let quotaStore: UsageQuotaStore
    let subscriptionManager: SubscriptionManager

    init() {
        let settings = SettingsStore()
        settingsStore = settings
        quotaStore = UsageQuotaStore()
        localizationManager = LocalizationManager(settingsStore: settings)
        subscriptionManager = SubscriptionManager(quotaStore: quotaStore)
    }

    func loadIfNeeded() async {
        guard !isReady else { return }

        let persistenceController = CloudKitPersistenceController.makeIfAvailable()
        let container = CloudKitSyncService.makeModelContainer(persistenceController: persistenceController)
        CloudKitSharingService.shared.configure(
            modelContainer: container,
            persistenceController: persistenceController
        )

        modelContainer = container
        isReady = true
    }
}
