import Foundation

enum SubscriptionTier: String, Codable, CaseIterable, Sendable {
    case free
    case pro
    case family

    var rank: Int {
        switch self {
        case .free: return 0
        case .pro: return 1
        case .family: return 2
        }
    }
}

enum PaywallTrigger: String, Identifiable, Sendable {
    case general
    case medicineLimit
    case aiScanLimit
    case reminderLimit
    case memberLimit
    case export
    case familySharing

    var id: String { rawValue }
}

enum SubscriptionProductID {
    static let proMonthly = "com.homemedicine.app.pro.monthly"
    static let proYearly = "com.homemedicine.app.pro.yearly"
    static let familyYearly = "com.homemedicine.app.family.yearly"
    static let aiCredits10 = "com.homemedicine.app.ai.credits10"
    static let aiCredits30 = "com.homemedicine.app.ai.credits30"
    static let aiCredits100 = "com.homemedicine.app.ai.credits100"

    static let subscriptions: [String] = [proMonthly, proYearly, familyYearly]
    static let consumables: [String] = [aiCredits10, aiCredits30, aiCredits100]
    static let all: [String] = subscriptions + consumables
}

enum SubscriptionLimits {
    static let freeMedicineCount = 15
    static let freeAIScansPerMonth = 3
    static let freeReminderCount = 3
    static let freeMemberCount = 1

    static let proAIScansPerMonth = 50
    static let proMemberCount = 6

    static let familyAIScansPerMonth = 150

    static func medicineLimit(for tier: SubscriptionTier) -> Int? {
        switch tier {
        case .free: return freeMedicineCount
        case .pro, .family: return nil
        }
    }

    static func aiScansPerMonth(for tier: SubscriptionTier) -> Int {
        switch tier {
        case .free: return freeAIScansPerMonth
        case .pro: return proAIScansPerMonth
        case .family: return familyAIScansPerMonth
        }
    }

    static func reminderLimit(for tier: SubscriptionTier) -> Int? {
        switch tier {
        case .free: return freeReminderCount
        case .pro, .family: return nil
        }
    }

    static func memberLimit(for tier: SubscriptionTier) -> Int? {
        switch tier {
        case .free: return freeMemberCount
        case .pro: return proMemberCount
        case .family: return nil
        }
    }

    static func aiCreditsAmount(for productID: String) -> Int? {
        switch productID {
        case SubscriptionProductID.aiCredits10: return 10
        case SubscriptionProductID.aiCredits30: return 30
        case SubscriptionProductID.aiCredits100: return 100
        default: return nil
        }
    }

    static func tier(for productID: String) -> SubscriptionTier? {
        switch productID {
        case SubscriptionProductID.proMonthly, SubscriptionProductID.proYearly:
            return .pro
        case SubscriptionProductID.familyYearly:
            return .family
        default:
            return nil
        }
    }
}
