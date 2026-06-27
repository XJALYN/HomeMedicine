import Foundation
import SwiftData

enum MedicineActionService {
    static func markDepleted(_ medicine: Medicine, context: ModelContext) {
        medicine.quantity = 0
        medicine.archiveReason = .depleted
        medicine.archivedAt = Date()
        medicine.touch()
        pauseReminders(for: medicine, reason: .depleted)
        addRecord(medicine: medicine, type: .depleted, context: context)
    }

    static func markDisposed(_ medicine: Medicine, context: ModelContext) {
        medicine.archiveReason = .disposed
        medicine.archivedAt = Date()
        medicine.touch()
        pauseReminders(for: medicine, reason: .depleted)
        addRecord(medicine: medicine, type: .disposed, context: context)
    }

    static func restoreMedicine(_ medicine: Medicine, newQuantity: Int) {
        medicine.quantity = max(1, newQuantity)
        medicine.archiveReason = nil
        medicine.archivedAt = nil
        medicine.touch()
        resumeEligibleReminders(for: medicine)
    }

    static func deleteMedicine(_ medicine: Medicine, context: ModelContext) {
        MedicineBoxPhotoStore.deleteAllPhotos(for: medicine, context: context)
        context.delete(medicine)
    }

    static func syncReminderStates(for medicine: Medicine, thresholdDays: Int) {
        let status = medicine.status(thresholdDays: thresholdDays)
        switch status {
        case .expired, .depleted:
            pauseReminders(for: medicine, reason: status == .expired ? .expired : .depleted)
        case .normal, .expiring:
            if medicine.quantity > 0 {
                resumeEligibleReminders(for: medicine)
            } else {
                pauseReminders(for: medicine, reason: .zeroQuantity)
            }
        }
    }

    static func pauseReminders(for medicine: Medicine, reason: PausedReason) {
        for reminder in medicine.remindersList {
            reminder.enabled = false
            reminder.pausedReason = reason
            reminder.updatedAt = Date()
        }
    }

    static func resumeEligibleReminders(for medicine: Medicine) {
        for reminder in medicine.remindersList where reminder.pausedReason != .manual {
            reminder.enabled = true
            reminder.pausedReason = nil
            reminder.updatedAt = Date()
        }
    }

    private static func addRecord(medicine: Medicine, type: UsageRecordType, context: ModelContext) {
        let record = UsageRecord(type: type, medicine: medicine)
        context.insert(record)
    }
}

struct IntakeConfirmationResult {
    let success: Bool
    let shouldPromptDepleted: Bool
    let requiresStrongConfirmation: Bool
}

enum IntakeService {
    static func confirmIntake(
        medicine: Medicine,
        reminder: Reminder?,
        memberId: UUID?,
        thresholdDays: Int,
        force: Bool = false,
        context: ModelContext
    ) -> IntakeConfirmationResult {
        let status = medicine.status(thresholdDays: thresholdDays)
        let requiresStrong = MedicineStatusCalculator.requiresStrongConfirmation(status: status, quantity: medicine.quantity)

        if requiresStrong && !force {
            return IntakeConfirmationResult(success: false, shouldPromptDepleted: false, requiresStrongConfirmation: true)
        }

        let dosage = reminder?.dosage ?? "1 \(medicine.unit)"
        let newQuantity = MedicineStatusCalculator.decrementQuantity(current: medicine.quantity, dosage: dosage)
        medicine.quantity = newQuantity
        medicine.touch()

        let record = UsageRecord(
            type: .intake,
            dosage: dosage,
            memberId: memberId ?? reminder?.memberId,
            reminderId: reminder?.id,
            medicine: medicine
        )
        context.insert(record)

        if newQuantity == 0 {
            MedicineActionService.syncReminderStates(for: medicine, thresholdDays: thresholdDays)
            return IntakeConfirmationResult(success: true, shouldPromptDepleted: true, requiresStrongConfirmation: false)
        }

        MedicineActionService.syncReminderStates(for: medicine, thresholdDays: thresholdDays)
        return IntakeConfirmationResult(success: true, shouldPromptDepleted: false, requiresStrongConfirmation: false)
    }
}

enum ExpiryOCRService {
    static func suggestDate(from text: String, calendar: Calendar = .current) -> Date? {
        let patterns = [
            #"(\d{4})[-./](\d{1,2})[-./](\d{1,2})"#,
            #"(\d{4})[-./](\d{1,2})"#,
            #"EXP\s*(\d{1,2})[/\-](\d{4})"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                if pattern.contains("EXP") {
                    let monthRange = Range(match.range(at: 1), in: text)!
                    let yearRange = Range(match.range(at: 2), in: text)!
                    let month = Int(text[monthRange]) ?? 1
                    let year = Int(text[yearRange]) ?? 2026
                    return calendar.date(from: DateComponents(year: year, month: month, day: 1))
                } else if match.numberOfRanges >= 4 {
                    let y = Int(text[Range(match.range(at: 1), in: text)!]) ?? 2026
                    let m = Int(text[Range(match.range(at: 2), in: text)!]) ?? 1
                    let d = Int(text[Range(match.range(at: 3), in: text)!]) ?? 1
                    return calendar.date(from: DateComponents(year: y, month: m, day: d))
                } else {
                    let y = Int(text[Range(match.range(at: 1), in: text)!]) ?? 2026
                    let m = Int(text[Range(match.range(at: 2), in: text)!]) ?? 12
                    return calendar.date(from: DateComponents(year: y, month: m, day: 1))
                }
            }
        }
        return nil
    }
}

struct ScheduledIntakeItem: Identifiable {
    let id: String
    let reminder: Reminder
    let medicine: Medicine
    let scheduledDate: Date
    let planDate: Date
    var status: IntakePlanStatus

    var isCompleted: Bool { status == .completed }

    var canModify: Bool {
        status == .upcoming && scheduledDate > Date()
    }
}

enum ReminderActionService {
    static func skipScheduledDose(_ reminder: Reminder, on date: Date, calendar: Calendar = .current) {
        reminder.skip(on: date, calendar: calendar)
    }
}

enum ReminderScheduleService {
    static func itemsForDate(
        reminders: [Reminder],
        medicines: [Medicine],
        date: Date,
        completedRecordKeys: Set<String>,
        thresholdDays: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [ScheduledIntakeItem] {
        let medicineMap = Dictionary(uniqueKeysWithValues: medicines.map { ($0.id, $0) })
        var items: [ScheduledIntakeItem] = []

        for reminder in reminders where reminder.enabled {
            guard reminder.weekdayMatches(date, calendar: calendar),
                  let medicine = medicineMap[reminder.medicineId] else { continue }
            let status = medicine.status(thresholdDays: thresholdDays, referenceDate: date)
            guard status != .depleted else { continue }

            guard let components = reminder.timeComponents(),
                  let scheduled = calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: date) else {
                continue
            }

            let key = recordKey(reminderId: reminder.id, date: date, calendar: calendar)
            let planStatus: IntakePlanStatus
            if completedRecordKeys.contains(key) {
                planStatus = .completed
            } else if reminder.isSkipped(on: date, calendar: calendar) {
                planStatus = .skipped
            } else if scheduled <= referenceDate {
                planStatus = .missed
            } else {
                planStatus = .upcoming
            }

            items.append(
                ScheduledIntakeItem(
                    id: key,
                    reminder: reminder,
                    medicine: medicine,
                    scheduledDate: scheduled,
                    planDate: calendar.startOfDay(for: date),
                    status: planStatus
                )
            )
        }

        return items.sorted { $0.scheduledDate < $1.scheduledDate }
    }

    static func referenceMoment(for date: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: Date())
        let selected = calendar.startOfDay(for: date)
        if selected < today {
            return calendar.date(byAdding: .day, value: 1, to: selected)?.addingTimeInterval(-1) ?? selected
        }
        if selected > today {
            return selected
        }
        return Date()
    }

    static func recordKey(reminderId: UUID, date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date)
        return "\(reminderId.uuidString)-\(day.timeIntervalSince1970)"
    }
}
