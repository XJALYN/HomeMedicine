import XCTest
@testable import HomeMedicine

final class EntitlementTests: XCTestCase {
    func testFreeMedicineLimit() {
        XCTAssertTrue(EntitlementChecker.canAddMedicine(currentCount: 14, tier: .free))
        XCTAssertFalse(EntitlementChecker.canAddMedicine(currentCount: 15, tier: .free))
        XCTAssertTrue(EntitlementChecker.canAddMedicine(currentCount: 100, tier: .pro))
    }

    func testFreeReminderLimit() {
        XCTAssertTrue(EntitlementChecker.canAddReminder(currentCount: 2, tier: .free))
        XCTAssertFalse(EntitlementChecker.canAddReminder(currentCount: 3, tier: .free))
        XCTAssertTrue(EntitlementChecker.canAddReminder(currentCount: 50, tier: .family))
    }

    func testFreeMemberLimit() {
        XCTAssertTrue(EntitlementChecker.canAddMember(currentCount: 0, tier: .free))
        XCTAssertFalse(EntitlementChecker.canAddMember(currentCount: 1, tier: .free))
        XCTAssertTrue(EntitlementChecker.canAddMember(currentCount: 5, tier: .pro))
        XCTAssertFalse(EntitlementChecker.canAddMember(currentCount: 6, tier: .pro))
        XCTAssertTrue(EntitlementChecker.canAddMember(currentCount: 20, tier: .family))
    }

    func testExportRequiresPaidTier() {
        XCTAssertFalse(EntitlementChecker.canExportData(tier: .free))
        XCTAssertTrue(EntitlementChecker.canExportData(tier: .pro))
    }

    func testFamilySharingRequiresFamilyTier() {
        XCTAssertFalse(EntitlementChecker.canUseFamilySharing(tier: .free))
        XCTAssertFalse(EntitlementChecker.canUseFamilySharing(tier: .pro))
        XCTAssertTrue(EntitlementChecker.canUseFamilySharing(tier: .family))
    }
}

@MainActor
final class UsageQuotaStoreTests: XCTestCase {
    func testMonthlyAIScanConsumption() {
        let defaults = UserDefaults(suiteName: "UsageQuotaStoreTests")!
        defaults.removePersistentDomain(forName: "UsageQuotaStoreTests")
        let store = UsageQuotaStore(defaults: defaults)

        XCTAssertEqual(store.remainingAIScans(tier: .free), 3)
        XCTAssertTrue(store.consumeAIScan(tier: .free))
        XCTAssertEqual(store.remainingAIScans(tier: .free), 2)
    }

    func testPurchasedCreditsUsedAfterMonthlyAllowance() {
        let defaults = UserDefaults(suiteName: "UsageQuotaStoreCreditsTests")!
        defaults.removePersistentDomain(forName: "UsageQuotaStoreCreditsTests")
        let store = UsageQuotaStore(defaults: defaults)
        store.addPurchasedCredits(5)

        for _ in 0..<3 {
            XCTAssertTrue(store.consumeAIScan(tier: .free))
        }
        XCTAssertTrue(store.consumeAIScan(tier: .free))
        XCTAssertEqual(store.remainingAIScans(tier: .free), 4)
    }

    func testMonthResetUsesNewKey() {
        let defaults = UserDefaults(suiteName: "UsageQuotaStoreResetTests")!
        defaults.removePersistentDomain(forName: "UsageQuotaStoreResetTests")
        let store = UsageQuotaStore(defaults: defaults)
        XCTAssertTrue(store.consumeAIScan(tier: .free))
        defaults.set("1999-1", forKey: "quota.aiScanMonthKey")
        store.resetMonthlyUsageIfNeeded()
        XCTAssertEqual(store.remainingAIScans(tier: .free), 3)
    }
}

final class SubscriptionLimitsTests: XCTestCase {
    func testAICreditsMapping() {
        XCTAssertEqual(SubscriptionLimits.aiCreditsAmount(for: SubscriptionProductID.aiCredits10), 10)
        XCTAssertEqual(SubscriptionLimits.aiCreditsAmount(for: SubscriptionProductID.aiCredits30), 30)
        XCTAssertEqual(SubscriptionLimits.tier(for: SubscriptionProductID.proYearly), .pro)
        XCTAssertEqual(SubscriptionLimits.tier(for: SubscriptionProductID.familyYearly), .family)
    }
}
