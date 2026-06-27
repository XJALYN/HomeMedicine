import SwiftUI
import SwiftData

struct AddReminderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Query(sort: \Medicine.name) private var medicines: [Medicine]
    @Query(sort: \Member.name) private var members: [Member]

    var editingReminder: Reminder?

    @State private var selectedMedicineId: UUID?
    @State private var selectedMemberId: UUID?
    @State private var time = Date()
    @State private var dosage = "1"
    @State private var instruction: ReminderInstruction = .afterMeal
    @State private var repeatDays: Set<Int> = [1, 2, 3, 4, 5, 6, 0]
    @State private var didLoadEditingValues = false

    private var isEditing: Bool { editingReminder != nil }

    private var eligibleMedicines: [Medicine] {
        medicines.filter {
            let status = $0.status(thresholdDays: settingsStore.expiringThresholdDays)
            return (status == .normal || status == .expiring) && $0.quantity > 0
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("reminder.select_medicine", locale: localizationManager.locale)) {
                    if isEditing {
                        if let medicine = editingReminder?.medicine {
                            Text(medicine.name)
                        }
                    } else {
                        Picker(L10n.t("field.name", locale: localizationManager.locale), selection: $selectedMedicineId) {
                            Text(L10n.t("reminder.choose", locale: localizationManager.locale)).tag(UUID?.none)
                            ForEach(eligibleMedicines) { medicine in
                                Text(medicine.name).tag(Optional(medicine.id))
                            }
                        }
                    }
                }

                Section(L10n.t("reminder.schedule", locale: localizationManager.locale)) {
                    DatePicker(L10n.t("field.time", locale: localizationManager.locale), selection: $time, displayedComponents: .hourAndMinute)
                    TextField(L10n.t("field.dosage", locale: localizationManager.locale), text: $dosage)
                    Picker(L10n.t("field.instruction", locale: localizationManager.locale), selection: $instruction) {
                        ForEach(ReminderInstruction.allCases, id: \.self) { value in
                            Text(L10n.t("instruction.\(value.rawValue)", locale: localizationManager.locale)).tag(value)
                        }
                    }
                }

                Section(L10n.t("field.member", locale: localizationManager.locale)) {
                    Picker(L10n.t("field.member", locale: localizationManager.locale), selection: $selectedMemberId) {
                        Text("-").tag(UUID?.none)
                        ForEach(members) { member in
                            Text(member.name).tag(Optional(member.id))
                        }
                    }
                }

                Section(L10n.t("reminder.repeat", locale: localizationManager.locale)) {
                    WeekdaySelector(selectedDays: $repeatDays, locale: localizationManager.locale)
                }
            }
            .navigationTitle(
                L10n.t(isEditing ? "reminder.edit_title" : "reminder.add_title", locale: localizationManager.locale)
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("action.cancel", locale: localizationManager.locale)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("action.save", locale: localizationManager.locale), action: save)
                        .disabled(!isEditing && selectedMedicineId == nil)
                }
            }
            .onAppear {
                ensureDefaultMemberIfNeeded()
                loadInitialValues()
            }
        }
        .preferredColorScheme(.light)
    }

    private func ensureDefaultMemberIfNeeded() {
        guard members.isEmpty else { return }
        let defaultCabinetName = L10n.t("sharing.default_cabinet_name", locale: localizationManager.locale)
        let cabinet = try? CloudKitSyncService.ensureDefaultCabinet(in: modelContext, defaultName: defaultCabinetName)
        let member = Member(
            name: L10n.t("member.self", locale: localizationManager.locale),
            relation: .selfMember
        )
        member.cabinet = cabinet
        modelContext.insert(member)
        try? modelContext.save()
        selectedMemberId = member.id
    }

    private func loadInitialValues() {
        guard !didLoadEditingValues else { return }
        didLoadEditingValues = true

        if let reminder = editingReminder {
            selectedMedicineId = reminder.medicineId
            selectedMemberId = reminder.memberId
            dosage = reminder.dosage.components(separatedBy: " ").first ?? reminder.dosage
            instruction = reminder.instruction
            repeatDays = Set(reminder.repeatDays)
            if let components = reminder.timeComponents() {
                var dateComponents = DateComponents()
                dateComponents.hour = components.hour
                dateComponents.minute = components.minute
                time = Calendar.current.date(from: dateComponents) ?? Date()
            }
        } else {
            selectedMemberId = members.first(where: { $0.relation == .selfMember })?.id
        }
    }

    private func save() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timeString = formatter.string(from: time)

        if let reminder = editingReminder {
            let dosageText = normalizedDosage(for: reminder.medicine)
            reminder.time = timeString
            reminder.dosage = dosageText
            reminder.instruction = instruction
            reminder.repeatDays = Array(repeatDays).sorted()
            reminder.memberId = selectedMemberId
            reminder.updatedAt = Date()
            try? modelContext.save()
            NotificationCenter.default.post(name: .scheduleNotifications, object: nil)
            dismiss()
            return
        }

        guard let medicineId = selectedMedicineId,
              let medicine = medicines.first(where: { $0.id == medicineId }) else { return }

        let dosageText = normalizedDosage(for: medicine)
        let reminder = Reminder(
            medicineId: medicineId,
            memberId: selectedMemberId,
            time: timeString,
            dosage: dosageText,
            instruction: instruction,
            repeatDays: Array(repeatDays).sorted(),
            medicine: medicine
        )
        modelContext.insert(reminder)
        try? modelContext.save()
        NotificationCenter.default.post(name: .scheduleNotifications, object: nil)
        dismiss()
    }

    private func normalizedDosage(for medicine: Medicine?) -> String {
        let unit = medicine?.unit ?? ""
        guard !unit.isEmpty else { return dosage }
        return dosage.contains(unit) ? dosage : "\(dosage) \(unit)"
    }
}

struct WeekdaySelector: View {
    @Binding var selectedDays: Set<Int>
    let locale: Locale

    private let weekdays = WeekdayFormat.displayOrder

    var body: some View {
        HStack {
            ForEach(weekdays, id: \.self) { day in
                let selected = selectedDays.contains(day)
                Button {
                    if selected { selectedDays.remove(day) } else { selectedDays.insert(day) }
                } label: {
                    Text(WeekdayFormat.veryShortSymbol(for: day, locale: locale))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(selected ? .white : AppTheme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(selected ? AppTheme.primary : AppTheme.searchBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

enum WeekdayFormat {
    /// Mon → Sun, matching common picker layout.
    static let displayOrder = [1, 2, 3, 4, 5, 6, 0]

    /// Maps repeat-day index (0=Sun … 6=Sat) to a localized single-character label.
    static func veryShortSymbol(for repeatDay: Int, locale: Locale) -> String {
        var calendar = Calendar.current
        calendar.locale = locale
        let symbols = calendar.veryShortWeekdaySymbols
        guard repeatDay >= 0, repeatDay < symbols.count else { return "?" }
        return symbols[repeatDay]
    }
}
