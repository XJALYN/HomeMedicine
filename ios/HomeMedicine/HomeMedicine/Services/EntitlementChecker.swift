import Foundation

enum EntitlementChecker {
    static func activeMedicineCount(in medicines: [Medicine], thresholdDays: Int) -> Int {
        medicines.filter { $0.status(thresholdDays: thresholdDays) != .depleted }.count
    }

    static func canAddMedicine(currentCount: Int, tier: SubscriptionTier) -> Bool {
        guard let limit = SubscriptionLimits.medicineLimit(for: tier) else { return true }
        return currentCount < limit
    }

    static func canAddReminder(currentCount: Int, tier: SubscriptionTier) -> Bool {
        guard let limit = SubscriptionLimits.reminderLimit(for: tier) else { return true }
        return currentCount < limit
    }

    static func canAddMember(currentCount: Int, tier: SubscriptionTier) -> Bool {
        guard let limit = SubscriptionLimits.memberLimit(for: tier) else { return true }
        return currentCount < limit
    }

    static func canExportData(tier: SubscriptionTier) -> Bool {
        tier != .free
    }

    static func canUseFamilySharing(tier: SubscriptionTier) -> Bool {
        tier == .family
    }
}
