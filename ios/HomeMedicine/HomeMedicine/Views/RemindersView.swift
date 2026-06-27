import SwiftUI
import SwiftData
import UserNotifications

struct RemindersView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Query(sort: \Reminder.time) private var reminders: [Reminder]
    @Query(sort: \Medicine.name) private var medicines: [Medicine]
    @Query(sort: \UsageRecord.recordedAt, order: .reverse) private var usageRecords: [UsageRecord]
    @Query(sort: \Member.name) private var members: [Member]

    @State private var selectedDate = Date()
    @State private var showAddReminder = false
    @State private var showStrongConfirm: ScheduledIntakeItem?
    @State private var showDepletedPrompt: Medicine?
    @State private var showCleanup = false
    @State private var paywallTrigger: PaywallTrigger?
    @State private var editingReminder: Reminder?
    @State private var skipConfirmItem: ScheduledIntakeItem?
    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined

    private var scheduledItems: [ScheduledIntakeItem] {
        ReminderScheduleService.itemsForDate(
            reminders: reminders,
            medicines: medicines,
            date: selectedDate,
            completedRecordKeys: completedKeys,
            thresholdDays: settingsStore.expiringThresholdDays,
            referenceDate: ReminderScheduleService.referenceMoment(for: selectedDate)
        )
    }

    private var completedKeys: Set<String> {
        var keys = Set<String>()
        let calendar = Calendar.current
        for record in usageRecords where record.type == .intake {
            if let reminderId = record.reminderId {
                keys.insert(ReminderScheduleService.recordKey(reminderId: reminderId, date: record.recordedAt, calendar: calendar))
            } else if let medicineId = record.medicine?.id {
                for reminder in reminders where reminder.medicineId == medicineId {
                    keys.insert(ReminderScheduleService.recordKey(reminderId: reminder.id, date: record.recordedAt, calendar: calendar))
                }
            }
        }
        return keys
    }

    private var expiringMedicines: [Medicine] {
        medicines.filter {
            let status = $0.status(thresholdDays: settingsStore.expiringThresholdDays, referenceDate: selectedDate)
            return status == .expiring && $0.expiryNotifyEnabled
        }.sorted { $0.daysUntilExpiry(referenceDate: selectedDate) < $1.daysUntilExpiry(referenceDate: selectedDate) }
    }

    private var completedCount: Int { scheduledItems.filter(\.isCompleted).count }
    private var totalCount: Int { scheduledItems.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    dateHeader
                    timelineSection
                    expiringSection
                    notificationBanner
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(AppTheme.background)
            .navigationTitle(L10n.t("reminders.title", locale: localizationManager.locale))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard EntitlementChecker.canAddReminder(currentCount: reminders.count, tier: subscriptionManager.tier) else {
                            paywallTrigger = .reminderLimit
                            return
                        }
                        showAddReminder = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(AppTheme.primary)
                            .clipShape(Circle())
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showCleanup = true } label: {
                        Text(L10n.t("cleanup.title", locale: localizationManager.locale))
                            .font(.caption)
                    }
                }
            }
            .sheet(isPresented: $showAddReminder) {
                AddReminderView()
            }
            .sheet(item: $editingReminder) { reminder in
                AddReminderView(editingReminder: reminder)
            }
            .sheet(isPresented: $showCleanup) {
                ExpiredCleanupView()
            }
            .sheet(item: $paywallTrigger) { trigger in
                PaywallView(trigger: trigger)
            }
            .task {
                await refreshNotificationAuthStatus()
            }
            .onChange(of: settingsStore.notificationsEnabled) { _, _ in
                Task { await refreshNotificationAuthStatus() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleNotifications)) { _ in
                Task { await refreshNotificationAuthStatus() }
            }
            .alert(L10n.t("intake.strong_confirm", locale: localizationManager.locale), isPresented: Binding(
                get: { showStrongConfirm != nil },
                set: { if !$0 { showStrongConfirm = nil } }
            )) {
                Button(L10n.t("action.confirm", locale: localizationManager.locale)) {
                    if let item = showStrongConfirm {
                        confirmIntake(item, force: true)
                        showStrongConfirm = nil
                    }
                }
                Button(L10n.t("action.cancel", locale: localizationManager.locale), role: .cancel) {
                    showStrongConfirm = nil
                }
            }
            .alert(L10n.t("intake.depleted_prompt", locale: localizationManager.locale), isPresented: Binding(
                get: { showDepletedPrompt != nil },
                set: { if !$0 { showDepletedPrompt = nil } }
            )) {
                Button(L10n.t("action.confirm", locale: localizationManager.locale)) {
                    if let medicine = showDepletedPrompt {
                        MedicineActionService.markDepleted(medicine, context: modelContext)
                        try? modelContext.save()
                        NotificationCenter.default.post(name: .scheduleNotifications, object: nil)
                    }
                    showDepletedPrompt = nil
                }
                Button(L10n.t("action.cancel", locale: localizationManager.locale), role: .cancel) {
                    showDepletedPrompt = nil
                }
            }
            .alert(L10n.t("intake.skip_confirm", locale: localizationManager.locale), isPresented: Binding(
                get: { skipConfirmItem != nil },
                set: { if !$0 { skipConfirmItem = nil } }
            )) {
                Button(L10n.t("action.delete", locale: localizationManager.locale), role: .destructive) {
                    if let item = skipConfirmItem {
                        ReminderActionService.skipScheduledDose(item.reminder, on: item.planDate)
                        try? modelContext.save()
                        NotificationCenter.default.post(name: .scheduleNotifications, object: nil)
                    }
                    skipConfirmItem = nil
                }
                Button(L10n.t("action.cancel", locale: localizationManager.locale), role: .cancel) {
                    skipConfirmItem = nil
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var dateHeader: some View {
        HStack {
            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden()
            VStack(alignment: .leading) {
                Text(selectedDate.formatted(date: .complete, time: .omitted))
                    .font(.subheadline.weight(.semibold))
                Text(L10n.t("reminders.today_count", locale: localizationManager.locale, count: totalCount))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .cardStyle()
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.t("reminders.today_plan", locale: localizationManager.locale))
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(L10n.t("reminders.progress", locale: localizationManager.locale, completed: completedCount, total: totalCount))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textMuted)
            }

            ProgressView(value: totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount))
                .tint(AppTheme.primary)

            if scheduledItems.isEmpty {
                Text(L10n.t("reminders.empty", locale: localizationManager.locale))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(scheduledItems) { item in
                    IntakeTimelineRow(
                        item: item,
                        memberName: memberName(for: item.reminder.memberId),
                        locale: localizationManager.locale,
                        onConfirm: { confirmIntake(item) },
                        onEdit: item.canModify ? { editingReminder = item.reminder } : nil,
                        onDelete: item.canModify ? { skipConfirmItem = item } : nil
                    )
                }
            }
        }
        .padding(16)
        .cardStyle()
    }

    private var expiringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("reminders.expiring_section", locale: localizationManager.locale))
                .font(.subheadline.weight(.bold))

            if expiringMedicines.isEmpty {
                Text(L10n.t("reminders.no_expiring", locale: localizationManager.locale))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(expiringMedicines) { medicine in
                    NavigationLink {
                        MedicineDetailView(medicine: medicine)
                    } label: {
                        ExpiringWarningCard(medicine: medicine, thresholdDays: settingsStore.expiringThresholdDays, locale: localizationManager.locale)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .cardStyle()
    }

    private var notificationBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: notificationBannerIcon)
                    .foregroundStyle(notificationBannerIconColor)
                    .font(.body.weight(.semibold))
                VStack(alignment: .leading, spacing: 4) {
                    Text(notificationBannerTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(notificationBannerMessage)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            if shouldShowOpenSettingsButton {
                Button {
                    openAppNotificationSettings()
                } label: {
                    Text(L10n.t("reminders.open_settings", locale: localizationManager.locale))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(notificationBannerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var notificationBannerIcon: String {
        if !settingsStore.notificationsEnabled {
            return "bell.slash"
        }
        switch notificationAuthStatus {
        case .authorized, .provisional, .ephemeral:
            return "bell.badge"
        case .denied:
            return "bell.slash.fill"
        default:
            return "bell"
        }
    }

    private var notificationBannerIconColor: Color {
        if !settingsStore.notificationsEnabled || notificationAuthStatus == .denied {
            return AppTheme.amber
        }
        return AppTheme.primary
    }

    private var notificationBannerBackground: Color {
        if !settingsStore.notificationsEnabled || notificationAuthStatus == .denied {
            return AppTheme.amber.opacity(0.12)
        }
        return AppTheme.primaryLight
    }

    private var notificationBannerTitle: String {
        let locale = localizationManager.locale
        if !settingsStore.notificationsEnabled {
            return L10n.t("reminders.notification_disabled_title", locale: locale)
        }
        switch notificationAuthStatus {
        case .authorized, .provisional, .ephemeral:
            return L10n.t("reminders.notification_ready_title", locale: locale)
        case .denied:
            return L10n.t("reminders.notification_denied_title", locale: locale)
        default:
            return L10n.t("reminders.notification_pending_title", locale: locale)
        }
    }

    private var notificationBannerMessage: String {
        let locale = localizationManager.locale
        if !settingsStore.notificationsEnabled {
            return L10n.t("reminders.notification_disabled_message", locale: locale)
        }
        switch notificationAuthStatus {
        case .authorized, .provisional, .ephemeral:
            return String(
                format: L10n.t("reminders.notification_ready_message", locale: locale),
                settingsStore.intakeNotifyLeadMinutes
            )
        case .denied:
            return L10n.t("reminders.notification_denied_message", locale: locale)
        default:
            return L10n.t("reminders.notification_hint", locale: locale)
        }
    }

    private var shouldShowOpenSettingsButton: Bool {
        !settingsStore.notificationsEnabled || notificationAuthStatus == .denied
    }

    private func refreshNotificationAuthStatus() async {
        notificationAuthStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func openAppNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func memberName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return members.first(where: { $0.id == id })?.name
    }

    private func confirmIntake(_ item: ScheduledIntakeItem, force: Bool = false) {
        let result = IntakeService.confirmIntake(
            medicine: item.medicine,
            reminder: item.reminder,
            memberId: item.reminder.memberId,
            thresholdDays: settingsStore.expiringThresholdDays,
            force: force,
            context: modelContext
        )

        if result.requiresStrongConfirmation {
            showStrongConfirm = item
            return
        }

        try? modelContext.save()
        NotificationCenter.default.post(name: .scheduleNotifications, object: nil)

        if result.shouldPromptDepleted {
            showDepletedPrompt = item.medicine
        }
    }
}

struct IntakeTimelineRow: View {
    let item: ScheduledIntakeItem
    let memberName: String?
    let locale: Locale
    let onConfirm: () -> Void
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    private var isCurrent: Bool {
        !item.isCompleted && item.status != .skipped && item.scheduledDate <= Date().addingTimeInterval(30 * 60)
    }

    private var showConfirmButton: Bool { isCurrent }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .stroke(timelineColor, lineWidth: 2)
                    .frame(width: 20, height: 20)
                if item.isCompleted {
                    Circle().fill(AppTheme.primary).frame(width: 20, height: 20)
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                } else if item.status == .skipped {
                    Circle().fill(AppTheme.textMuted.opacity(0.3)).frame(width: 20, height: 20)
                    Image(systemName: "minus").font(.system(size: 10, weight: .bold)).foregroundStyle(AppTheme.textMuted)
                } else if item.status == .missed {
                    Circle().fill(AppTheme.expired.opacity(0.15)).frame(width: 20, height: 20)
                    Image(systemName: "exclamationmark").font(.system(size: 10, weight: .bold)).foregroundStyle(AppTheme.expired)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.scheduledDate.formatted(date: .omitted, time: .shortened))
                        .font(.caption.weight(.semibold))
                    Spacer()
                    if item.status != .upcoming {
                        Text(item.status.localizedName(locale: locale))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(statusBadgeColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(statusBadgeColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Text(item.medicine.name).font(.subheadline.weight(.medium))
                Text(item.reminder.dosage).font(.caption).foregroundStyle(AppTheme.textSecondary)
                if let memberName {
                    Text(L10n.t("field.member", locale: locale) + ": \(memberName)")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textMuted)
                }

                if showConfirmButton {
                    Button(L10n.t("intake.confirm", locale: locale), action: onConfirm)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppTheme.primary)
                        .clipShape(Capsule())
                }

                if onEdit != nil || onDelete != nil {
                    HStack(spacing: 8) {
                        if let onEdit {
                            Button(L10n.t("action.edit", locale: locale), action: onEdit)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.primary)
                        }
                        if let onDelete {
                            Button(L10n.t("action.delete", locale: locale), role: .destructive, action: onDelete)
                                .font(.caption2.weight(.semibold))
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(rowBorder))
            .contextMenu {
                if let onEdit {
                    Button(L10n.t("action.edit", locale: locale), action: onEdit)
                }
                if let onDelete {
                    Button(L10n.t("action.delete", locale: locale), role: .destructive, action: onDelete)
                }
            }
        }
    }

    private var timelineColor: Color {
        switch item.status {
        case .completed: return AppTheme.primary
        case .skipped: return AppTheme.textMuted
        case .missed: return AppTheme.expired
        case .upcoming: return AppTheme.border
        }
    }

    private var statusBadgeColor: Color {
        switch item.status {
        case .completed: return AppTheme.primary
        case .skipped: return AppTheme.textMuted
        case .missed: return AppTheme.expired
        case .upcoming: return AppTheme.textSecondary
        }
    }

    private var rowBackground: Color {
        if isCurrent { return AppTheme.primaryLight }
        if item.status == .missed { return AppTheme.expired.opacity(0.05) }
        if item.status == .skipped { return AppTheme.searchBackground }
        return Color.white
    }

    private var rowBorder: Color {
        if isCurrent { return AppTheme.primary.opacity(0.3) }
        if item.status == .missed { return AppTheme.expired.opacity(0.2) }
        return AppTheme.border
    }
}

struct ExpiringWarningCard: View {
    let medicine: Medicine
    let thresholdDays: Int
    let locale: Locale

    private var days: Int { medicine.daysUntilExpiry() }
    private var urgency: ExpiryUrgency {
        MedicineStatusCalculator.expiryUrgency(
            daysUntilExpiry: days,
            status: medicine.status(thresholdDays: thresholdDays)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(medicine.name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(L10n.t("status.days_left", locale: locale, days: days))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(labelColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(labelColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            Text(L10n.t("detail.replace_hint", locale: locale))
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
            Text("\(L10n.t("list.remaining", locale: locale)): \(medicine.quantity)\(MedicineUnits.localized(medicine.unit, locale: locale)) · \(medicine.storageLocation)")
                .font(.caption2)
                .foregroundStyle(AppTheme.textMuted)
        }
        .padding(12)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(labelColor.opacity(0.2)))
    }

    private var labelColor: Color {
        switch urgency {
        case .urgent: return AppTheme.urgent
        case .warning: return AppTheme.amber
        case .general: return AppTheme.expiring
        case .normal: return AppTheme.normal
        }
    }

    private var backgroundColor: Color {
        switch urgency {
        case .urgent: return AppTheme.urgent.opacity(0.08)
        case .warning, .general: return Color.white
        case .normal: return AppTheme.primaryLight
        }
    }
}
