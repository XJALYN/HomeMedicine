import CloudKit
import SwiftData
import SwiftUI

struct FamilySharingView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @StateObject private var sharingService = CloudKitSharingService.shared

    @Query(sort: \MedicineCabinet.createdAt) private var cabinets: [MedicineCabinet]

    @State private var showPaywall = false
    @State private var showSharingController = false
    @State private var isCreatingShare = false
    @State private var cabinetName = ""

    var body: some View {
        Form {
            Section {
                accountStatusRow
            } footer: {
                if CloudKitAvailability.isConfigured {
                    Text(L10n.t("sharing.icloud_footer", locale: localizationManager.locale))
                } else {
                    Text(L10n.t("sharing.icloud_not_configured", locale: localizationManager.locale))
                }
            }

            Section(L10n.t("sharing.cabinet_section", locale: localizationManager.locale)) {
                if let cabinet = cabinets.first {
                    TextField(
                        L10n.t("sharing.cabinet_name", locale: localizationManager.locale),
                        text: Binding(
                            get: { cabinetName.isEmpty ? cabinet.name : cabinetName },
                            set: { cabinetName = $0 }
                        )
                    )
                    .onSubmit { saveCabinetName(cabinet) }

                    Text(L10n.t("sharing.cabinet_stats", locale: localizationManager.locale, completed: cabinet.medicinesList.count, total: cabinet.membersList.count))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textMuted)
                } else {
                    Text(L10n.t("sharing.cabinet_loading", locale: localizationManager.locale))
                        .foregroundStyle(AppTheme.textMuted)
                }
            }

            Section {
                Button {
                    inviteFamily()
                } label: {
                    HStack {
                        Label(L10n.t("sharing.invite", locale: localizationManager.locale), systemImage: "person.2.badge.gearshape")
                        Spacer()
                        if isCreatingShare {
                            ProgressView()
                        }
                    }
                }
                .disabled(isCreatingShare || cabinets.isEmpty || !CloudKitAvailability.isConfigured || sharingService.accountStatus != .available)
            } footer: {
                Text(L10n.t("sharing.invite_footer", locale: localizationManager.locale))
            }

            Section(L10n.t("sharing.how_it_works", locale: localizationManager.locale)) {
                Label(L10n.t("sharing.step1", locale: localizationManager.locale), systemImage: "1.circle")
                Label(L10n.t("sharing.step2", locale: localizationManager.locale), systemImage: "2.circle")
                Label(L10n.t("sharing.step3", locale: localizationManager.locale), systemImage: "3.circle")
            }
        }
        .navigationTitle(L10n.t("sharing.title", locale: localizationManager.locale))
        .task {
            await subscriptionManager.refreshEntitlements()
            await bootstrapCabinetIfNeeded()
            await sharingService.refreshAccountStatus()
        }
        .refreshable {
            await subscriptionManager.refreshEntitlements()
            await sharingService.refreshAccountStatus()
        }
        .onChange(of: subscriptionManager.tier) { _, tier in
            if EntitlementChecker.canUseFamilySharing(tier: tier) {
                showPaywall = false
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(trigger: .familySharing)
        }
        .sheet(isPresented: $showSharingController, onDismiss: {
            sharingService.activeShare = nil
            sharingService.shareContainer = nil
        }) {
            if let share = sharingService.activeShare,
               let container = sharingService.shareContainer {
                CloudSharingController(share: share, container: container) {
                    showSharingController = false
                } onError: { message in
                    sharingService.lastErrorMessage = message
                }
            }
        }
        .alert(
            L10n.t("sharing.error_title", locale: localizationManager.locale),
            isPresented: Binding(
                get: { sharingService.lastErrorMessage != nil },
                set: { if !$0 { sharingService.lastErrorMessage = nil } }
            )
        ) {
            Button(L10n.t("action.ok", locale: localizationManager.locale), role: .cancel) {}
        } message: {
            Text(sharingService.lastErrorMessage ?? "")
        }
        .preferredColorScheme(.light)
    }

    private var accountStatusRow: some View {
        HStack {
            Label(L10n.t("sharing.icloud_status", locale: localizationManager.locale), systemImage: "icloud")
            Spacer()
            if sharingService.isCheckingAccount {
                ProgressView()
            } else {
                Text(statusText)
                    .foregroundStyle(statusColor)
            }
        }
    }

    private var statusText: String {
        if !CloudKitAvailability.isConfigured {
            return L10n.t("sharing.icloud_not_configured_short", locale: localizationManager.locale)
        }
        switch sharingService.accountStatus {
        case .available:
            return L10n.t("sharing.icloud_available", locale: localizationManager.locale)
        case .noAccount:
            return L10n.t("sharing.icloud_no_account", locale: localizationManager.locale)
        case .restricted:
            return L10n.t("sharing.icloud_restricted", locale: localizationManager.locale)
        case .couldNotDetermine:
            return L10n.t("sharing.icloud_unknown", locale: localizationManager.locale)
        case .temporarilyUnavailable:
            return L10n.t("sharing.icloud_unavailable", locale: localizationManager.locale)
        @unknown default:
            return L10n.t("sharing.icloud_unknown", locale: localizationManager.locale)
        }
    }

    private var statusColor: Color {
        sharingService.accountStatus == .available ? AppTheme.primary : AppTheme.textMuted
    }

    private func bootstrapCabinetIfNeeded() async {
        let defaultName = L10n.t("sharing.default_cabinet_name", locale: localizationManager.locale)
        _ = try? CloudKitSyncService.ensureDefaultCabinet(in: modelContext, defaultName: defaultName)
    }

    private func saveCabinetName(_ cabinet: MedicineCabinet) {
        let trimmed = cabinetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        cabinet.name = trimmed
        cabinet.touch()
        try? modelContext.save()
    }

    private func inviteFamily() {
        guard EntitlementChecker.canUseFamilySharing(tier: subscriptionManager.tier) else {
            showPaywall = true
            return
        }
        guard let cabinet = cabinets.first else { return }

        isCreatingShare = true
        Task {
            defer { isCreatingShare = false }
            do {
                _ = try await sharingService.createShare(for: cabinet, modelContext: modelContext)
                showSharingController = true
            } catch {
                if let sharingError = error as? CloudKitSharingError {
                    sharingService.lastErrorMessage = sharingError.localizedMessage(locale: localizationManager.locale)
                } else {
                    sharingService.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }
}
