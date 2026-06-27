import SwiftUI
import SwiftData

struct MedicineDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var localizationManager: LocalizationManager

    @Bindable var medicine: Medicine
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showDepletedConfirm = false
    @State private var showDisposedConfirm = false
    @State private var usageExpanded = true
    @State private var notesExpanded = false

    private var status: MedicineStatus {
        medicine.status(thresholdDays: settingsStore.expiringThresholdDays)
    }

    private var daysUntilExpiry: Int {
        medicine.daysUntilExpiry()
    }

    private var urgency: ExpiryUrgency {
        MedicineStatusCalculator.expiryUrgency(daysUntilExpiry: daysUntilExpiry, status: status)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroCard
                if status == .expiring || status == .expired { warningCard }
                if status == .depleted || medicine.quantity == 0 { unavailableBanner }
                if hasBoxPhotos { boxPhotosCard }
                infoCard
                expiryCard
                if let usage = medicine.usage, !usage.isEmpty { collapsibleSection(title: L10n.t("section.usage", locale: localizationManager.locale), text: usage, expanded: $usageExpanded) }
                if let notes = medicine.notes, !notes.isEmpty { collapsibleSection(title: L10n.t("section.notes", locale: localizationManager.locale), text: notes, expanded: $notesExpanded) }
                historySection
                if !medicine.remindersList.isEmpty { remindersSection }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(AppTheme.background)
        .navigationTitle(L10n.t("detail.title", locale: localizationManager.locale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                AddMedicineView(editingMedicine: medicine)
            }
        }
        .alert(L10n.t("detail.delete_confirm", locale: localizationManager.locale), isPresented: $showDeleteConfirm) {
            Button(L10n.t("action.delete", locale: localizationManager.locale), role: .destructive) {
                MedicineActionService.deleteMedicine(medicine, context: modelContext)
                try? modelContext.save()
                NotificationCenter.default.post(name: .scheduleNotifications, object: nil)
                dismiss()
            }
            Button(L10n.t("action.cancel", locale: localizationManager.locale), role: .cancel) {}
        }
        .alert(L10n.t("detail.depleted_confirm", locale: localizationManager.locale), isPresented: $showDepletedConfirm) {
            Button(L10n.t("action.confirm", locale: localizationManager.locale)) {
                MedicineActionService.markDepleted(medicine, context: modelContext)
                try? modelContext.save()
                NotificationCenter.default.post(name: .scheduleNotifications, object: nil)
            }
            Button(L10n.t("action.cancel", locale: localizationManager.locale), role: .cancel) {}
        }
        .alert(L10n.t("detail.disposed_confirm", locale: localizationManager.locale), isPresented: $showDisposedConfirm) {
            Button(L10n.t("action.confirm", locale: localizationManager.locale)) {
                MedicineActionService.markDisposed(medicine, context: modelContext)
                try? modelContext.save()
                NotificationCenter.default.post(name: .scheduleNotifications, object: nil)
            }
            Button(L10n.t("action.cancel", locale: localizationManager.locale), role: .cancel) {}
        }
        .preferredColorScheme(.light)
        .dynamicTypeSize(settingsStore.fontSize.dynamicTypeSize)
    }

    private var shareText: String {
        "\(medicine.name)\n\(medicine.specification)\n\(L10n.t("field.expiry_date", locale: localizationManager.locale)): \(medicine.expiryDate.formatted(date: .abbreviated, time: .omitted))"
    }

    private var loadedBoxPhotos: [UIImage?] {
        MedicineBoxPhotoStore.loadPhotos(for: medicine, context: modelContext)
    }

    private var hasBoxPhotos: Bool {
        loadedBoxPhotos.contains { $0 != nil }
    }

    private var heroImage: UIImage? {
        MedicineBoxPhotoStore.loadCoverPhoto(for: medicine, context: modelContext)
    }

    private var boxPhotosCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(AppTheme.primary).frame(width: 6, height: 16)
                Text(L10n.t("section.box_photos", locale: localizationManager.locale))
                    .font(.subheadline.weight(.semibold))
            }
            MedicineBoxPhotosEditorView(photos: .constant(loadedBoxPhotos), editable: false)
        }
        .padding(16)
        .cardStyle()
    }

    private var heroCard: some View {
        VStack(spacing: 12) {
            Group {
                if let heroImage {
                    Image(uiImage: heroImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "pills.fill")
                        .font(.largeTitle)
                        .imageScale(.large)
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .frame(width: 128, height: 128)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            HStack {
                Text(medicine.name).font(.title3.bold())
                StatusBadge(status: status, locale: localizationManager.locale)
            }
            if let nameEn = medicine.nameEn {
                Text(nameEn).font(.caption).foregroundStyle(AppTheme.textSecondary)
            }
            if medicine.isOTC {
                Label(L10n.t("field.is_otc", locale: localizationManager.locale), systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.primaryLight)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(LinearGradient(colors: [AppTheme.primaryLight, .white], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius).stroke(AppTheme.primary.opacity(0.2)))
    }

    private var warningCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(urgency == .urgent ? AppTheme.urgent : AppTheme.amber)
            Text(L10n.t("detail.expiry_warning", locale: localizationManager.locale, days: daysUntilExpiry))
                .font(.caption)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((urgency == .urgent ? AppTheme.urgent : AppTheme.amber).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private var unavailableBanner: some View {
        Text(L10n.t("detail.unavailable", locale: localizationManager.locale))
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(AppTheme.searchBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            infoRow(L10n.t("field.specification", locale: localizationManager.locale), medicine.specification)
            infoRow(L10n.t("field.manufacturer", locale: localizationManager.locale), medicine.manufacturer ?? "-")
            infoRow(L10n.t("field.approval_number", locale: localizationManager.locale), medicine.approvalNumber ?? "-")
            infoRow(L10n.t("field.storage_location", locale: localizationManager.locale), medicine.storageLocation)
            infoRow(L10n.t("field.remaining_quantity", locale: localizationManager.locale), "\(medicine.quantity)/\(medicine.initialQuantity) \(MedicineUnits.localized(medicine.unit, locale: localizationManager.locale))")
            if let batch = medicine.batchNumber { infoRow(L10n.t("field.batch_number", locale: localizationManager.locale), batch) }
        }
        .padding(16)
        .cardStyle()
    }

    private var expiryCard: some View {
        VStack(spacing: 8) {
            Text(expiryCountdownText)
                .font(.title2.bold())
                .foregroundStyle(expiryColor)
            Text(medicine.expiryDate.formatted(date: .long, time: .omitted))
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            if status == .expiring || status == .expired {
                Text(L10n.t("detail.replace_hint", locale: localizationManager.locale))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .cardStyle(borderColor: expiryColor.opacity(0.3))
    }

    private var expiryCountdownText: String {
        if daysUntilExpiry < 0 {
            return L10n.t("status.expired_days", locale: localizationManager.locale, days: abs(daysUntilExpiry))
        }
        return L10n.t("status.days_left", locale: localizationManager.locale, days: daysUntilExpiry)
    }

    private var expiryColor: Color {
        switch urgency {
        case .urgent: return AppTheme.urgent
        case .warning: return AppTheme.amber
        case .general: return AppTheme.expiring
        case .normal: return AppTheme.normal
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Text(value).font(.caption.weight(.medium)).foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    private func collapsibleSection(title: String, text: String, expanded: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.wrappedValue.toggle() } label: {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                }
            }
            .buttonStyle(.plain)
            if expanded.wrappedValue {
                Text(text).font(.caption).foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(16)
        .cardStyle()
    }

    private var sortedUsageRecords: [UsageRecord] {
        medicine.usageRecordsList.sorted { $0.recordedAt > $1.recordedAt }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.primary)
                    .frame(width: 6, height: 16)
                Text(L10n.t("detail.history", locale: localizationManager.locale))
                    .font(.subheadline.weight(.semibold))
            }

            if sortedUsageRecords.isEmpty {
                Text(L10n.t("detail.history_empty", locale: localizationManager.locale))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sortedUsageRecords.enumerated()), id: \.element.id) { index, record in
                        historyRow(record, showDivider: index < sortedUsageRecords.count - 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardStyle()
    }

    private func historyRow(_ record: UsageRecord, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(historyAccentColor(for: record.type))
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(record.type.localizedName(locale: localizationManager.locale))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer(minLength: 0)
                        Text(record.recordedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textMuted)
                            .multilineTextAlignment(.trailing)
                    }
                    if let dosage = record.dosage, !dosage.isEmpty {
                        Text(dosage)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)

            if showDivider {
                Divider().padding(.leading, 20)
            }
        }
    }

    private func historyAccentColor(for type: UsageRecordType) -> Color {
        switch type {
        case .intake: return AppTheme.primary
        case .stockIn: return AppTheme.normal
        case .depleted: return AppTheme.depleted
        case .disposed: return AppTheme.expired
        }
    }

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("detail.linked_reminders", locale: localizationManager.locale))
                .font(.subheadline.weight(.semibold))
            ForEach(medicine.remindersList) { reminder in
                HStack {
                    Text(reminder.time)
                    Text(reminder.dosage)
                    Spacer()
                    Text(reminder.enabled ? L10n.t("status.active", locale: localizationManager.locale) : L10n.t("status.paused", locale: localizationManager.locale))
                        .font(.caption2)
                        .foregroundStyle(reminder.enabled ? AppTheme.normal : AppTheme.depleted)
                }
                .font(.caption)
            }
        }
        .padding(16)
        .cardStyle()
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            DetailActionButton(title: L10n.t("action.depleted", locale: localizationManager.locale), style: .secondary) {
                showDepletedConfirm = true
            }
            if status == .expired {
                DetailActionButton(title: L10n.t("action.disposed", locale: localizationManager.locale), style: .secondary) {
                    showDisposedConfirm = true
                }
            }
            DetailActionButton(title: L10n.t("action.edit", locale: localizationManager.locale), style: .primary) {
                showEdit = true
            }
            DetailActionButton(title: L10n.t("action.delete", locale: localizationManager.locale), style: .danger) {
                showDeleteConfirm = true
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white)
    }
}

struct DetailActionButton: View {
    enum Style { case primary, secondary, danger }
    let title: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var foreground: Color {
        switch style {
        case .primary: return .white
        case .secondary: return AppTheme.textPrimary
        case .danger: return AppTheme.expired
        }
    }

    private var background: Color {
        switch style {
        case .primary: return AppTheme.primary
        case .secondary: return AppTheme.searchBackground
        case .danger: return AppTheme.expired.opacity(0.1)
        }
    }
}
