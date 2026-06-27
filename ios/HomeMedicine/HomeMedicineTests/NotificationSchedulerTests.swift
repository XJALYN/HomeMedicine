import XCTest
@testable import HomeMedicine

final class NotificationSchedulerTests: XCTestCase {
    private let locale = Locale(identifier: "en")
    private let reminderId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let medicineId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    func testFireTimeAppliesLeadMinutes() {
        let first = NotificationScheduler.fireTime(hour: 8, minute: 30, leadMinutes: 15)
        XCTAssertEqual(first.0, 8)
        XCTAssertEqual(first.1, 15)
        let second = NotificationScheduler.fireTime(hour: 0, minute: 10, leadMinutes: 15)
        XCTAssertEqual(second.0, 23)
        XCTAssertEqual(second.1, 55)
    }

    func testCalendarWeekdayMapping() {
        XCTAssertEqual(NotificationScheduler.calendarWeekday(fromRepeatDay: 0), 1)
        XCTAssertEqual(NotificationScheduler.calendarWeekday(fromRepeatDay: 1), 2)
    }

    func testBuildIntakeNotificationsRespectsToggleAndEligibility() {
        let settingsOff = NotificationScheduleSettings(
            notificationsEnabled: false,
            expiringThresholdDays: 30,
            intakeLeadMinutes: 10
        )
        let reminder = ReminderNotificationInput(
            id: reminderId,
            medicineId: medicineId,
            medicineName: "Ibuprofen",
            dosage: "1 tablet",
            time: "09:00",
            repeatDays: [1, 3],
            enabled: true,
            medicineEligible: true
        )
        XCTAssertTrue(NotificationScheduler.buildIntakeNotifications(
            reminders: [reminder],
            settings: settingsOff,
            locale: locale
        ).isEmpty)

        let settingsOn = NotificationScheduleSettings(
            notificationsEnabled: true,
            expiringThresholdDays: 30,
            intakeLeadMinutes: 10
        )
        let disabled = ReminderNotificationInput(
            id: reminderId,
            medicineId: medicineId,
            medicineName: "Ibuprofen",
            dosage: "1 tablet",
            time: "09:00",
            repeatDays: [1],
            enabled: false,
            medicineEligible: true
        )
        XCTAssertTrue(NotificationScheduler.buildIntakeNotifications(
            reminders: [disabled],
            settings: settingsOn,
            locale: locale
        ).isEmpty)

        let payloads = NotificationScheduler.buildIntakeNotifications(
            reminders: [reminder],
            settings: settingsOn,
            locale: locale
        )
        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(payloads[0].hour, 8)
        XCTAssertEqual(payloads[0].minute, 50)
        XCTAssertEqual(payloads[0].weekday, 2)
        XCTAssertTrue(payloads[0].repeats)
        XCTAssertEqual(payloads[0].identifier, NotificationScheduler.intakeIdentifier(reminderId: reminderId, weekday: 1))
    }

    func testBuildExpiryNotificationsRequiresPerMedicineToggle() {
        let settings = NotificationScheduleSettings(
            notificationsEnabled: true,
            expiringThresholdDays: 30,
            intakeLeadMinutes: 0
        )
        let expiring = MedicineExpiryNotificationInput(
            id: medicineId,
            name: "Vitamin C",
            expiryNotifyEnabled: true,
            status: .expiring,
            daysUntilExpiry: 12
        )
        let normal = MedicineExpiryNotificationInput(
            id: UUID(),
            name: "Aspirin",
            expiryNotifyEnabled: true,
            status: .normal,
            daysUntilExpiry: 120
        )
        let disabled = MedicineExpiryNotificationInput(
            id: UUID(),
            name: "Calcium",
            expiryNotifyEnabled: false,
            status: .expiring,
            daysUntilExpiry: 5
        )

        let payloads = NotificationScheduler.buildExpiryNotifications(
            medicines: [expiring, normal, disabled],
            settings: settings,
            locale: locale
        )
        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads[0].identifier, NotificationScheduler.expiryIdentifier(medicineId: medicineId))
        XCTAssertEqual(payloads[0].hour, NotificationScheduler.expiryHour)
        XCTAssertNil(payloads[0].weekday)
    }

    func testAllManagedIdentifiers() {
        let reminders = [
            ReminderNotificationInput(
                id: reminderId,
                medicineId: medicineId,
                medicineName: "A",
                dosage: "1",
                time: "08:00",
                repeatDays: [0, 6],
                enabled: true,
                medicineEligible: true
            )
        ]
        let medicines = [
            MedicineExpiryNotificationInput(
                id: medicineId,
                name: "A",
                expiryNotifyEnabled: true,
                status: .expiring,
                daysUntilExpiry: 3
            )
        ]
        let ids = NotificationScheduler.allManagedIdentifiers(reminders: reminders, medicines: medicines)
        XCTAssertEqual(ids.count, 3)
    }
}

final class NotificationSyncServiceTests: XCTestCase {
    private final class MockClient: NotificationSchedulingClient, @unchecked Sendable {
        var status: UNAuthorizationStatus = .authorized
        var requestedAuthorization = false
        var removed: [String] = []
        var added: [ScheduledNotificationPayload] = []
        var pending = Set<String>()

        func authorizationStatus() async -> UNAuthorizationStatus { status }

        func requestAuthorization() async -> Bool {
            requestedAuthorization = true
            status = .authorized
            return true
        }

        func pendingIdentifiers() async -> Set<String> { pending }

        func removePending(withIdentifiers identifiers: [String]) async {
            removed.append(contentsOf: identifiers)
            pending.subtract(identifiers)
        }

        func add(_ payload: ScheduledNotificationPayload) async throws {
            added.append(payload)
            pending.insert(payload.identifier)
        }
    }

    func testSyncRequestsPermissionOnFirstUse() async {
        let client = MockClient()
        client.status = .notDetermined
        let reminderId = UUID()
        let medicineId = UUID()
        let settings = NotificationScheduleSettings(
            notificationsEnabled: true,
            expiringThresholdDays: 30,
            intakeLeadMinutes: 0
        )
        let reminders = [
            ReminderNotificationInput(
                id: reminderId,
                medicineId: medicineId,
                medicineName: "Med",
                dosage: "1",
                time: "10:00",
                repeatDays: [1],
                enabled: true,
                medicineEligible: true
            )
        ]

        await NotificationSyncService.sync(
            reminders: reminders,
            medicines: [],
            settings: settings,
            locale: Locale(identifier: "en"),
            client: client,
            requestPermissionIfNeeded: true
        )

        XCTAssertTrue(client.requestedAuthorization)
        XCTAssertEqual(client.added.count, 1)
    }

    func testSyncClearsWhenNotificationsDisabled() async {
        let client = MockClient()
        client.pending = ["intake.old", "expiry.old"]
        let settings = NotificationScheduleSettings(
            notificationsEnabled: false,
            expiringThresholdDays: 30,
            intakeLeadMinutes: 0
        )
        let reminderId = UUID()
        let medicineId = UUID()

        await NotificationSyncService.sync(
            reminders: [
                ReminderNotificationInput(
                    id: reminderId,
                    medicineId: medicineId,
                    medicineName: "Med",
                    dosage: "1",
                    time: "10:00",
                    repeatDays: [1],
                    enabled: true,
                    medicineEligible: true
                )
            ],
            medicines: [
                MedicineExpiryNotificationInput(
                    id: medicineId,
                    name: "Med",
                    expiryNotifyEnabled: true,
                    status: .expiring,
                    daysUntilExpiry: 2
                )
            ],
            settings: settings,
            locale: Locale(identifier: "en"),
            client: client,
            requestPermissionIfNeeded: false
        )

        XCTAssertTrue(client.added.isEmpty)
        XCTAssertFalse(client.removed.isEmpty)
        XCTAssertTrue(client.removed.contains(NotificationScheduler.intakeIdentifier(reminderId: reminderId, weekday: 1)))
        XCTAssertTrue(client.removed.contains(NotificationScheduler.expiryIdentifier(medicineId: medicineId)))
    }
}
