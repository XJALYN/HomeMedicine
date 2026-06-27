import Foundation
import Combine

@MainActor
final class UsageQuotaStore: ObservableObject {
    private enum Keys {
        static let aiScansUsedThisMonth = "quota.aiScansUsedThisMonth"
        static let aiScanMonthKey = "quota.aiScanMonthKey"
        static let purchasedAICredits = "quota.purchasedAICredits"
    }

    @Published private(set) var aiScansUsedThisMonth = 0
    @Published private(set) var purchasedAICredits = 0

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        aiScansUsedThisMonth = defaults.integer(forKey: Keys.aiScansUsedThisMonth)
        purchasedAICredits = defaults.integer(forKey: Keys.purchasedAICredits)
        resetMonthlyUsageIfNeeded()
    }

    func resetMonthlyUsageIfNeeded() {
        let currentMonthKey = Self.monthKey(for: Date())
        let storedMonthKey = defaults.string(forKey: Keys.aiScanMonthKey)
        guard storedMonthKey != currentMonthKey else { return }
        aiScansUsedThisMonth = 0
        defaults.set(currentMonthKey, forKey: Keys.aiScanMonthKey)
        defaults.set(0, forKey: Keys.aiScansUsedThisMonth)
    }

    func remainingAIScans(tier: SubscriptionTier) -> Int {
        resetMonthlyUsageIfNeeded()
        let monthlyRemaining = max(0, SubscriptionLimits.aiScansPerMonth(for: tier) - aiScansUsedThisMonth)
        return monthlyRemaining + purchasedAICredits
    }

    func canUseAIScan(tier: SubscriptionTier) -> Bool {
        remainingAIScans(tier: tier) > 0
    }

    @discardableResult
    func consumeAIScan(tier: SubscriptionTier) -> Bool {
        resetMonthlyUsageIfNeeded()
        let monthlyAllowance = SubscriptionLimits.aiScansPerMonth(for: tier)
        if aiScansUsedThisMonth < monthlyAllowance {
            aiScansUsedThisMonth += 1
            defaults.set(aiScansUsedThisMonth, forKey: Keys.aiScansUsedThisMonth)
            return true
        }
        guard purchasedAICredits > 0 else { return false }
        purchasedAICredits -= 1
        defaults.set(purchasedAICredits, forKey: Keys.purchasedAICredits)
        return true
    }

    func addPurchasedCredits(_ count: Int) {
        guard count > 0 else { return }
        purchasedAICredits += count
        defaults.set(purchasedAICredits, forKey: Keys.purchasedAICredits)
    }

    static func monthKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }
}
