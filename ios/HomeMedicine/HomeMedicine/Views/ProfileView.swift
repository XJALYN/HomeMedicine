import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var quotaStore: UsageQuotaStore
    @Query private var members: [Member]

    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("paywall.membership", locale: localizationManager.locale)) {
                    membershipRow
                    Button(L10n.t("paywall.upgrade", locale: localizationManager.locale)) {
                        showPaywall = true
                    }
                }

                Section(L10n.t("profile.settings", locale: localizationManager.locale)) {
                    Stepper(
                        L10n.t("settings.expiring_threshold", locale: localizationManager.locale) + ": \(settingsStore.expiringThresholdDays)",
                        value: $settingsStore.expiringThresholdDays,
                        in: 7...90
                    )
                    Stepper(
                        L10n.t("settings.intake_lead", locale: localizationManager.locale) + ": \(settingsStore.intakeNotifyLeadMinutes)",
                        value: $settingsStore.intakeNotifyLeadMinutes,
                        in: 0...60
                    )
                    Toggle(L10n.t("settings.notifications", locale: localizationManager.locale), isOn: $settingsStore.notificationsEnabled)
                    Picker(L10n.t("settings.font_size", locale: localizationManager.locale), selection: $settingsStore.fontSize) {
                        ForEach(AppFontSize.allCases) { size in
                            Text(size.displayName(locale: localizationManager.locale)).tag(size)
                        }
                    }
                }

                Section(L10n.t("settings.language", locale: localizationManager.locale)) {
                    Picker(L10n.t("settings.language", locale: localizationManager.locale), selection: Binding(
                        get: { settingsStore.preferredLanguageCode ?? "system" },
                        set: { code in
                            let value = code == "system" ? nil : code
                            localizationManager.applyLanguage(code: value, settingsStore: settingsStore)
                        }
                    )) {
                        Text(L10n.t("settings.language_system", locale: localizationManager.locale)).tag("system")
                        ForEach(LocalizationManager.supportedLanguages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                }

                Section(L10n.t("profile.management", locale: localizationManager.locale)) {
                    NavigationLink(L10n.t("sharing.title", locale: localizationManager.locale)) {
                        FamilySharingView()
                    }
                    NavigationLink(L10n.t("members.title", locale: localizationManager.locale)) {
                        MembersView()
                    }
                    NavigationLink(L10n.t("cleanup.title", locale: localizationManager.locale)) {
                        ExpiredCleanupView()
                    }
                    NavigationLink(L10n.t("profile.depleted", locale: localizationManager.locale)) {
                        DepletedMedicinesView()
                    }
                }

                Section(L10n.t("profile.about", locale: localizationManager.locale)) {
                    HStack {
                        Text(L10n.t("profile.version", locale: localizationManager.locale))
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(AppTheme.textMuted)
                    }
                }
            }
            .navigationTitle(L10n.t("tab.profile", locale: localizationManager.locale))
            .onAppear {
                ensureDefaultMember()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(trigger: .general)
            }
        }
        .preferredColorScheme(.light)
    }

    private var membershipRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("paywall.current_plan.\(subscriptionManager.tier.rawValue)", locale: localizationManager.locale))
                .font(.subheadline.weight(.semibold))
            Text(L10n.t("paywall.ai_remaining", locale: localizationManager.locale, count: quotaStore.remainingAIScans(tier: subscriptionManager.tier)))
                .font(.caption)
                .foregroundStyle(AppTheme.textMuted)
        }
    }

    private func ensureDefaultMember() {
        let defaultCabinetName = L10n.t("sharing.default_cabinet_name", locale: localizationManager.locale)
        let cabinet = try? CloudKitSyncService.ensureDefaultCabinet(in: modelContext, defaultName: defaultCabinetName)
        guard members.isEmpty else { return }
        let member = Member(
            name: L10n.t("member.self", locale: localizationManager.locale),
            relation: .selfMember
        )
        member.cabinet = cabinet
        modelContext.insert(member)
        try? modelContext.save()
    }
}
