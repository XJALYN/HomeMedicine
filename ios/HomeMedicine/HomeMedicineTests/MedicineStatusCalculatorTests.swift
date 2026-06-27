import XCTest
@testable import HomeMedicine

final class MedicineStatusCalculatorTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testDepletedPriorityOverExpired() {
        let expiry = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let input = MedicineStatusInput(
            quantity: 5,
            expiryDate: expiry,
            archiveReason: .depleted,
            expiringThresholdDays: 30,
            referenceDate: reference,
            calendar: calendar
        )
        XCTAssertEqual(MedicineStatusCalculator.calculateStatus(for: input), .depleted)
    }

    func testExpiredWhenPastExpiryDate() {
        let expiry = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let input = MedicineStatusInput(quantity: 5, expiryDate: expiry, expiringThresholdDays: 30, referenceDate: reference, calendar: calendar)
        XCTAssertEqual(MedicineStatusCalculator.calculateStatus(for: input), .expired)
    }

    func testExpiringWithinThreshold() {
        let reference = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let expiry = calendar.date(from: DateComponents(year: 2026, month: 6, day: 20))!
        let input = MedicineStatusInput(quantity: 5, expiryDate: expiry, expiringThresholdDays: 30, referenceDate: reference, calendar: calendar)
        XCTAssertEqual(MedicineStatusCalculator.calculateStatus(for: input), .expiring)
    }

    func testNormalBeyondThreshold() {
        let reference = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let expiry = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let input = MedicineStatusInput(quantity: 5, expiryDate: expiry, expiringThresholdDays: 30, referenceDate: reference, calendar: calendar)
        XCTAssertEqual(MedicineStatusCalculator.calculateStatus(for: input), .normal)
    }

    func testZeroQuantityIsDepleted() {
        let expiry = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let input = MedicineStatusInput(quantity: 0, expiryDate: expiry, expiringThresholdDays: 30, referenceDate: reference, calendar: calendar)
        XCTAssertEqual(MedicineStatusCalculator.calculateStatus(for: input), .depleted)
    }

    func testDaysUntilExpiry() {
        let reference = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let expiry = calendar.date(from: DateComponents(year: 2026, month: 6, day: 11))!
        XCTAssertEqual(MedicineStatusCalculator.daysUntilExpiry(from: reference, expiryDate: expiry, calendar: calendar), 10)
    }

    func testExpiryUrgencyTiers() {
        XCTAssertEqual(MedicineStatusCalculator.expiryUrgency(daysUntilExpiry: 2, status: .expiring), .urgent)
        XCTAssertEqual(MedicineStatusCalculator.expiryUrgency(daysUntilExpiry: 5, status: .expiring), .warning)
        XCTAssertEqual(MedicineStatusCalculator.expiryUrgency(daysUntilExpiry: 20, status: .expiring), .general)
    }

    func testCanConfirmIntake() {
        XCTAssertTrue(MedicineStatusCalculator.canConfirmIntake(status: .normal, quantity: 3))
        XCTAssertTrue(MedicineStatusCalculator.canConfirmIntake(status: .expiring, quantity: 1))
        XCTAssertFalse(MedicineStatusCalculator.canConfirmIntake(status: .expired, quantity: 3))
        XCTAssertFalse(MedicineStatusCalculator.canConfirmIntake(status: .depleted, quantity: 0))
    }

    func testDecrementQuantity() {
        XCTAssertEqual(MedicineStatusCalculator.decrementQuantity(current: 10, dosage: "2 粒"), 8)
        XCTAssertEqual(MedicineStatusCalculator.decrementQuantity(current: 1, dosage: "3"), 0)
        XCTAssertEqual(MedicineStatusCalculator.parseDosageAmount("1 tablet"), 1)
    }
}

final class MedicineFilterServiceTests: XCTestCase {
    private func snapshot(name: String, status: MedicineStatus, symptoms: String = "cold") -> MedicineSnapshot {
        MedicineSnapshot(
            id: UUID(),
            name: name,
            symptoms: symptoms,
            usage: nil,
            storageLocation: "cabinet",
            quantity: 5,
            unit: "粒",
            expiryDate: Date(),
            status: status,
            daysUntilExpiry: 10,
            tags: []
        )
    }

    func testFilterByStatus() {
        let items = [
            snapshot(name: "A", status: .normal),
            snapshot(name: "B", status: .expiring),
            snapshot(name: "C", status: .expired),
            snapshot(name: "D", status: .depleted)
        ]
        XCTAssertEqual(MedicineFilterService.filter(medicines: items, filter: .expiring, searchText: "").count, 1)
        XCTAssertEqual(MedicineFilterService.filter(medicines: items, filter: .all, searchText: "").count, 3)
    }

    func testSearchBySymptoms() {
        let items = [snapshot(name: "A", status: .normal, symptoms: "headache")]
        XCTAssertEqual(MedicineFilterService.filter(medicines: items, filter: .all, searchText: "head").count, 1)
        XCTAssertEqual(MedicineFilterService.filter(medicines: items, filter: .all, searchText: "fever").count, 0)
    }

    func testStatusCounts() {
        let items = [
            snapshot(name: "A", status: .normal),
            snapshot(name: "B", status: .expiring),
            snapshot(name: "C", status: .expired)
        ]
        let counts = MedicineFilterService.counts(for: items)
        XCTAssertEqual(counts[.all], 3)
        XCTAssertEqual(counts[.normal], 1)
        XCTAssertEqual(counts[.expiring], 1)
        XCTAssertEqual(counts[.expired], 1)
    }
}

final class ExpiryOCRServiceTests: XCTestCase {
    func testParseISOFormat() {
        let date = ExpiryOCRService.suggestDate(from: "有效期至 2026-06-30")
        XCTAssertNotNil(date)
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.year, from: date!), 2026)
        XCTAssertEqual(calendar.component(.month, from: date!), 6)
        XCTAssertEqual(calendar.component(.day, from: date!), 30)
    }
}
