import SwiftUI
import SwiftData

struct ExpiredCleanupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Query(sort: \Medicine.expiryDate) private var medicines: [Medicine]

    private var expiredMedicines: [Medicine] {
        medicines.filter { $0.status(thresholdDays: settingsStore.expiringThresholdDays) == .expired }
    }

    var body: some View {
        NavigationStack {
            List {
                if expiredMedicines.isEmpty {
                    Text(L10n.t("cleanup.empty", locale: localizationManager.locale))
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(expiredMedicines) { medicine in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(medicine.name).font(.subheadline.weight(.semibold))
                                Text(medicine.expiryDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.expired)
                            }
                            Spacer()
                            Button(L10n.t("action.disposed", locale: localizationManager.locale)) {
                                MedicineActionService.markDisposed(medicine, context: modelContext)
                                try? modelContext.save()
                                NotificationCenter.default.post(name: .scheduleNotifications, object: nil)
                            }
                            .font(.caption)
                            .foregroundStyle(AppTheme.primary)
                        }
                    }
                }
            }
            .navigationTitle(L10n.t("cleanup.title", locale: localizationManager.locale))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("action.close", locale: localizationManager.locale)) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

struct DepletedMedicinesView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Query(sort: \Medicine.archivedAt, order: .reverse) private var medicines: [Medicine]

    private var depleted: [Medicine] {
        medicines.filter { $0.status(thresholdDays: settingsStore.expiringThresholdDays) == .depleted }
    }

    var body: some View {
        List {
            ForEach(depleted) { medicine in
                VStack(alignment: .leading, spacing: 4) {
                    Text(medicine.name)
                    Text(medicine.archiveReason == .disposed
                         ? L10n.t("status.disposed", locale: localizationManager.locale)
                         : L10n.t("status.depleted", locale: localizationManager.locale))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textMuted)
                }
                .swipeActions {
                    Button(L10n.t("action.restore", locale: localizationManager.locale)) {
                        MedicineActionService.restoreMedicine(medicine, newQuantity: max(1, medicine.initialQuantity))
                        try? modelContext.save()
                        NotificationCenter.default.post(name: .scheduleNotifications, object: nil)
                    }
                    .tint(AppTheme.primary)
                }
            }
        }
        .navigationTitle(L10n.t("profile.depleted", locale: localizationManager.locale))
        .preferredColorScheme(.light)
    }
}

struct MembersView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Query(sort: \Member.createdAt) private var members: [Member]
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newRelation: MemberRelation = .selfMember
    @State private var paywallTrigger: PaywallTrigger?

    var body: some View {
        List {
            ForEach(members) { member in
                HStack {
                    Circle()
                        .fill(AppTheme.primaryLight)
                        .frame(width: 36, height: 36)
                        .overlay {
                            Text(String(member.name.prefix(1)))
                                .foregroundStyle(AppTheme.primary)
                        }
                    VStack(alignment: .leading) {
                        Text(member.name)
                        Text(L10n.t("relation.\(member.relation.rawValue)", locale: localizationManager.locale))
                            .font(.caption)
                            .foregroundStyle(AppTheme.textMuted)
                    }
                }
            }
            .onDelete(perform: deleteMembers)
        }
        .navigationTitle(L10n.t("members.title", locale: localizationManager.locale))
        .toolbar {
            Button {
                guard EntitlementChecker.canAddMember(currentCount: members.count, tier: subscriptionManager.tier) else {
                    paywallTrigger = .memberLimit
                    return
                }
                showAdd = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(item: $paywallTrigger) { trigger in
            PaywallView(trigger: trigger)
        }
        .alert(L10n.t("members.add", locale: localizationManager.locale), isPresented: $showAdd) {
            TextField(L10n.t("field.name", locale: localizationManager.locale), text: $newName)
            Button(L10n.t("action.save", locale: localizationManager.locale)) { addMember() }
            Button(L10n.t("action.cancel", locale: localizationManager.locale), role: .cancel) {}
        }
        .preferredColorScheme(.light)
    }

    private func addMember() {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let defaultCabinetName = L10n.t("sharing.default_cabinet_name", locale: localizationManager.locale)
        let cabinet = try? CloudKitSyncService.ensureDefaultCabinet(in: modelContext, defaultName: defaultCabinetName)
        let member = Member(name: newName, relation: newRelation)
        member.cabinet = cabinet
        modelContext.insert(member)
        try? modelContext.save()
        newName = ""
    }

    private func deleteMembers(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(members[index])
        }
        try? modelContext.save()
    }
}
