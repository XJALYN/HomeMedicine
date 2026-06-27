import Foundation
import SwiftData
import UserNotifications

struct ScheduledNotificationPayload: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let hour: Int
    let minute: Int
    let weekday: Int?
    let repeats: Bool
}

struct ReminderNotificationInput: Sendable {
    let id: UUID
    let medicineId: UUID
    let medicineName: String
    let dosage: String
    let time: String
    let repeatDays: [Int]
    let enabled: Bool
    let medicineEligible: Bool
}

struct MedicineExpiryNotificationInput: Sendable {
    let id: UUID
    let name: String
    let expiryNotifyEnabled: Bool
    let status: MedicineStatus
    let daysUntilExpiry: Int
}

struct NotificationScheduleSettings: Sendable {
    let notificationsEnabled: Bool
    let expiringThresholdDays: Int
    let intakeLeadMinutes: Int
}

enum NotificationScheduler {
    static let expiryHour = 9
    static let expiryMinute = 0

    static func intakeIdentifier(reminderId: UUID, weekday: Int) -> String {
        "intake.\(reminderId.uuidString).\(weekday)"
    }

    static func expiryIdentifier(medicineId: UUID) -> String {
        "expiry.\(medicineId.uuidString)"
    }

    static func allManagedIdentifiers(
        reminders: [ReminderNotificationInput],
        medicines: [MedicineExpiryNotificationInput]
    ) -> Set<String> {
        var ids = Set<String>()
        for reminder in reminders {
            for day in reminder.repeatDays {
                ids.insert(intakeIdentifier(reminderId: reminder.id, weekday: day))
            }
        }
        for medicine in medicines {
            ids.insert(expiryIdentifier(medicineId: medicine.id))
        }
        return ids
    }

    static func fireTime(hour: Int, minute: Int, leadMinutes: Int) -> (hour: Int, minute: Int) {
        let totalMinutes = hour * 60 + minute - leadMinutes
        let normalized = ((totalMinutes % (24 * 60)) + (24 * 60)) % (24 * 60)
        return (normalized / 60, normalized % 60)
    }

    static func calendarWeekday(fromRepeatDay day: Int) -> Int {
        day + 1
    }

    static func buildIntakeNotifications(
        reminders: [ReminderNotificationInput],
        settings: NotificationScheduleSettings,
        locale: Locale
    ) -> [ScheduledNotificationPayload] {
        guard settings.notificationsEnabled else { return [] }

        var payloads: [ScheduledNotificationPayload] = []
        for reminder in reminders where reminder.enabled && reminder.medicineEligible {
            guard let components = parseTime(reminder.time) else { continue }
            let fire = fireTime(
                hour: components.hour,
                minute: components.minute,
                leadMinutes: settings.intakeLeadMinutes
            )
            let title = L10n.t("notification.intake.title", locale: locale)
            let body = String(
                format: L10n.t("notification.intake.body", locale: locale),
                reminder.medicineName,
                reminder.dosage
            )

            for day in reminder.repeatDays {
                payloads.append(
                    ScheduledNotificationPayload(
                        identifier: intakeIdentifier(reminderId: reminder.id, weekday: day),
                        title: title,
                        body: body,
                        hour: fire.hour,
                        minute: fire.minute,
                        weekday: calendarWeekday(fromRepeatDay: day),
                        repeats: true
                    )
                )
            }
        }
        return payloads
    }

    static func buildExpiryNotifications(
        medicines: [MedicineExpiryNotificationInput],
        settings: NotificationScheduleSettings,
        locale: Locale
    ) -> [ScheduledNotificationPayload] {
        guard settings.notificationsEnabled else { return [] }

        return medicines.compactMap { medicine in
            guard medicine.expiryNotifyEnabled, medicine.status == .expiring else { return nil }
            let title = L10n.t("notification.expiry.title", locale: locale)
            let body = String(
                format: L10n.t("notification.expiry.body", locale: locale),
                medicine.name,
                medicine.daysUntilExpiry
            )
            return ScheduledNotificationPayload(
                identifier: expiryIdentifier(medicineId: medicine.id),
                title: title,
                body: body,
                hour: expiryHour,
                minute: expiryMinute,
                weekday: nil,
                repeats: true
            )
        }
    }

    static func buildAllNotifications(
        reminders: [ReminderNotificationInput],
        medicines: [MedicineExpiryNotificationInput],
        settings: NotificationScheduleSettings,
        locale: Locale
    ) -> [ScheduledNotificationPayload] {
        buildIntakeNotifications(reminders: reminders, settings: settings, locale: locale)
            + buildExpiryNotifications(medicines: medicines, settings: settings, locale: locale)
    }

    private static func parseTime(_ time: String) -> (hour: Int, minute: Int)? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return (hour, minute)
    }
}

protocol NotificationSchedulingClient: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
    func pendingIdentifiers() async -> Set<String>
    func removePending(withIdentifiers identifiers: [String]) async
    func add(_ payload: ScheduledNotificationPayload) async throws
}

struct LiveNotificationClient: NotificationSchedulingClient {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func pendingIdentifiers() async -> Set<String> {
        let requests = await center.pendingNotificationRequests()
        return Set(requests.map(\.identifier))
    }

    func removePending(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(_ payload: ScheduledNotificationPayload) async throws {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = payload.hour
        dateComponents.minute = payload.minute
        if let weekday = payload.weekday {
            dateComponents.weekday = weekday
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: payload.repeats)
        let request = UNNotificationRequest(identifier: payload.identifier, content: content, trigger: trigger)
        try await center.add(request)
    }
}

enum NotificationSyncService {
    static func sync(
        reminders: [ReminderNotificationInput],
        medicines: [MedicineExpiryNotificationInput],
        settings: NotificationScheduleSettings,
        locale: Locale,
        client: NotificationSchedulingClient,
        requestPermissionIfNeeded: Bool
    ) async {
        let desired = NotificationScheduler.buildAllNotifications(
            reminders: reminders,
            medicines: medicines,
            settings: settings,
            locale: locale
        )
        let desiredIDs = Set(desired.map(\.identifier))
        let managedIDs = NotificationScheduler.allManagedIdentifiers(reminders: reminders, medicines: medicines)

        if settings.notificationsEnabled && requestPermissionIfNeeded && !desired.isEmpty {
            let status = await client.authorizationStatus()
            if status == .notDetermined {
                let granted = await client.requestAuthorization()
                guard granted else { return }
            }
        }

        guard settings.notificationsEnabled else {
            await client.removePending(withIdentifiers: Array(managedIDs))
            return
        }

        let status = await client.authorizationStatus()
        guard status == .authorized || status == .provisional else {
            await client.removePending(withIdentifiers: Array(managedIDs))
            return
        }

        let pending = await client.pendingIdentifiers()
        let stale = pending.intersection(managedIDs).subtracting(desiredIDs)
        if !stale.isEmpty {
            await client.removePending(withIdentifiers: Array(stale))
        }

        for payload in desired {
            try? await client.add(payload)
        }
    }
}

extension Notification.Name {
    static let scheduleNotifications = Notification.Name("HomeMedicine.scheduleNotifications")
}

@MainActor
enum NotificationCoordinator {
    private static var syncTask: Task<Void, Never>?

    static func reschedule(
        modelContext: ModelContext,
        settings: SettingsStore,
        locale: Locale,
        requestPermissionIfNeeded: Bool = true
    ) {
        syncTask?.cancel()
        syncTask = Task {
            let medicines = (try? modelContext.fetch(FetchDescriptor<Medicine>())) ?? []
            let reminders = (try? modelContext.fetch(FetchDescriptor<Reminder>())) ?? []
            guard !Task.isCancelled else { return }
            await performReschedule(
                medicines: medicines,
                reminders: reminders,
                settings: settings,
                locale: locale,
                requestPermissionIfNeeded: requestPermissionIfNeeded
            )
        }
    }

    static func performReschedule(
        medicines: [Medicine],
        reminders: [Reminder],
        settings: SettingsStore,
        locale: Locale,
        requestPermissionIfNeeded: Bool = true,
        client: NotificationSchedulingClient = LiveNotificationClient()
    ) async {
        let threshold = settings.expiringThresholdDays
        let reminderInputs = reminders.map { reminder -> ReminderNotificationInput in
            let medicine = medicines.first { $0.id == reminder.medicineId }
            let eligible: Bool
            if let medicine {
                let status = medicine.status(thresholdDays: threshold)
                eligible = (status == .normal || status == .expiring) && medicine.quantity > 0
            } else {
                eligible = false
            }
            return ReminderNotificationInput(
                id: reminder.id,
                medicineId: reminder.medicineId,
                medicineName: medicine?.name ?? "",
                dosage: reminder.dosage,
                time: reminder.time,
                repeatDays: reminder.repeatDays,
                enabled: reminder.enabled,
                medicineEligible: eligible
            )
        }

        let medicineInputs = medicines.map { medicine in
            MedicineExpiryNotificationInput(
                id: medicine.id,
                name: medicine.name,
                expiryNotifyEnabled: medicine.expiryNotifyEnabled,
                status: medicine.status(thresholdDays: threshold),
                daysUntilExpiry: medicine.daysUntilExpiry()
            )
        }

        let scheduleSettings = NotificationScheduleSettings(
            notificationsEnabled: settings.notificationsEnabled,
            expiringThresholdDays: threshold,
            intakeLeadMinutes: settings.intakeNotifyLeadMinutes
        )

        await NotificationSyncService.sync(
            reminders: reminderInputs,
            medicines: medicineInputs,
            settings: scheduleSettings,
            locale: locale,
            client: client,
            requestPermissionIfNeeded: requestPermissionIfNeeded
        )
    }
}
