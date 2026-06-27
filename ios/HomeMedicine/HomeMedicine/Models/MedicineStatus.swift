import Foundation

enum MedicineStatus: String, Codable, CaseIterable, Sendable {
    case normal
    case expiring
    case expired
    case depleted

    var priority: Int {
        switch self {
        case .depleted: return 0
        case .expired: return 1
        case .expiring: return 2
        case .normal: return 3
        }
    }
}

enum ArchiveReason: String, Codable, Sendable {
    case depleted
    case disposed
}

enum UsageRecordType: String, Codable, Sendable {
    case intake
    case stockIn = "stock_in"
    case depleted
    case disposed

    func localizedName(locale: Locale) -> String {
        L10n.t("usage_record.\(rawValue)", locale: locale)
    }
}

enum MemberRelation: String, Codable, CaseIterable, Sendable {
    case selfMember = "self"
    case father
    case mother
    case child
    case other
}

enum ReminderInstruction: String, Codable, CaseIterable, Sendable {
    case beforeMeal = "before"
    case afterMeal = "after"
    case withMeal = "with"
}

enum PausedReason: String, Codable, Sendable {
    case expired
    case depleted
    case zeroQuantity = "zero_quantity"
    case manual
}

enum IntakePlanStatus: String, Codable, Sendable {
    case upcoming
    case completed
    case missed
    case skipped

    func localizedName(locale: Locale) -> String {
        L10n.t("intake.status.\(rawValue)", locale: locale)
    }
}

enum ExpiryUrgency: Sendable {
    case normal
    case general
    case warning
    case urgent
}

struct MedicineStatusInput: Sendable {
    var quantity: Int
    var expiryDate: Date
    var archiveReason: ArchiveReason?
    var expiringThresholdDays: Int
    var referenceDate: Date
    var calendar: Calendar

    init(
        quantity: Int,
        expiryDate: Date,
        archiveReason: ArchiveReason? = nil,
        expiringThresholdDays: Int = 30,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.quantity = quantity
        self.expiryDate = expiryDate
        self.archiveReason = archiveReason
        self.expiringThresholdDays = expiringThresholdDays
        self.referenceDate = referenceDate
        self.calendar = calendar
    }
}

enum MedicineStatusCalculator {
    static func calculateStatus(for input: MedicineStatusInput) -> MedicineStatus {
        if input.archiveReason != nil {
            return .depleted
        }

        let startOfReference = input.calendar.startOfDay(for: input.referenceDate)
        let startOfExpiry = input.calendar.startOfDay(for: input.expiryDate)

        if input.quantity <= 0 {
            return .depleted
        }

        if startOfReference > startOfExpiry {
            return .expired
        }

        if let thresholdEnd = input.calendar.date(byAdding: .day, value: input.expiringThresholdDays, to: startOfReference),
           startOfExpiry <= thresholdEnd {
            return .expiring
        }

        return .normal
    }

    static func daysUntilExpiry(from referenceDate: Date, expiryDate: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: referenceDate)
        let end = calendar.startOfDay(for: expiryDate)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    static func expiryUrgency(daysUntilExpiry: Int, status: MedicineStatus) -> ExpiryUrgency {
        guard status == .expiring else {
            if status == .expired { return .urgent }
            return .normal
        }
        if daysUntilExpiry <= 2 { return .urgent }
        if daysUntilExpiry <= 7 { return .warning }
        return .general
    }

    static func canConfirmIntake(status: MedicineStatus, quantity: Int) -> Bool {
        status == .normal || status == .expiring && quantity > 0
    }

    static func requiresStrongConfirmation(status: MedicineStatus, quantity: Int) -> Bool {
        !canConfirmIntake(status: status, quantity: quantity)
    }

    static func parseDosageAmount(_ dosage: String) -> Int {
        let digits = dosage.filter { $0.isNumber }
        return Int(digits) ?? 1
    }

    static func decrementQuantity(current: Int, dosage: String) -> Int {
        max(0, current - parseDosageAmount(dosage))
    }
}

enum MedicineFilter: String, CaseIterable, Identifiable {
    case all
    case expiring
    case expired
    case normal

    var id: String { rawValue }
}

struct MedicineFilterService {
    static func filter(
        medicines: [MedicineSnapshot],
        filter: MedicineFilter,
        searchText: String,
        includeArchived: Bool = false
    ) -> [MedicineSnapshot] {
        var result = medicines

        if !includeArchived {
            result = result.filter { $0.status != .depleted }
        }

        switch filter {
        case .all:
            break
        case .expiring:
            result = result.filter { $0.status == .expiring }
        case .expired:
            result = result.filter { $0.status == .expired }
        case .normal:
            result = result.filter { $0.status == .normal }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return result }

        return result.filter { medicine in
            medicine.name.lowercased().contains(query)
                || medicine.symptoms.lowercased().contains(query)
                || (medicine.usage?.lowercased().contains(query) ?? false)
                || medicine.storageLocation.lowercased().contains(query)
        }
    }

    static func counts(for medicines: [MedicineSnapshot], includeArchived: Bool = false) -> [MedicineFilter: Int] {
        let visible = includeArchived ? medicines : medicines.filter { $0.status != .depleted }
        return [
            .all: visible.count,
            .expiring: visible.filter { $0.status == .expiring }.count,
            .expired: visible.filter { $0.status == .expired }.count,
            .normal: visible.filter { $0.status == .normal }.count
        ]
    }
}

struct MedicineSnapshot: Identifiable, Sendable {
    let id: UUID
    let name: String
    let symptoms: String
    let usage: String?
    let storageLocation: String
    let quantity: Int
    let unit: String
    let expiryDate: Date
    let status: MedicineStatus
    let daysUntilExpiry: Int
    let tags: [String]
}
