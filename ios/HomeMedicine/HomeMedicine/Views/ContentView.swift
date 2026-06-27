import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MedicineListView()
                .tabItem {
                    Label(L10n.t("tab.medicines", locale: localizationManager.locale), systemImage: "pills.fill")
                }
                .tag(0)

            RemindersView()
                .tabItem {
                    Label(L10n.t("tab.reminders", locale: localizationManager.locale), systemImage: "bell.fill")
                }
                .tag(1)

            ProfileView()
                .tabItem {
                    Label(L10n.t("tab.profile", locale: localizationManager.locale), systemImage: "person.fill")
                }
                .tag(2)
        }
        .tint(AppTheme.primary)
        .preferredColorScheme(.light)
        .dynamicTypeSize(settingsStore.fontSize.dynamicTypeSize)
        .environment(\.locale, localizationManager.locale)
        .onAppear {
            localizationManager.applyLanguage(code: settingsStore.preferredLanguageCode, settingsStore: settingsStore)
            CloudKitSyncService.migrateLegacyContent(in: modelContext)
            rescheduleNotifications()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                rescheduleNotifications()
            }
        }
        .onChange(of: settingsStore.notificationsEnabled) { _, _ in
            rescheduleNotifications(requestPermission: settingsStore.notificationsEnabled)
        }
        .onChange(of: settingsStore.expiringThresholdDays) { _, _ in
            rescheduleNotifications()
        }
        .onChange(of: settingsStore.intakeNotifyLeadMinutes) { _, _ in
            rescheduleNotifications()
        }
        .onChange(of: settingsStore.preferredLanguageCode) { _, _ in
            rescheduleNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: .scheduleNotifications)) { _ in
            rescheduleNotifications()
        }
    }

    private func rescheduleNotifications(requestPermission: Bool = true) {
        NotificationCoordinator.reschedule(
            modelContext: modelContext,
            settings: settingsStore,
            locale: localizationManager.locale,
            requestPermissionIfNeeded: requestPermission
        )
    }
}
