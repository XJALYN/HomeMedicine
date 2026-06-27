import Foundation
import SwiftData

@Model
final class Medicine {
    var id: UUID = UUID()
    var name: String = ""
    var nameEn: String?
    var specification: String = ""
    var unit: String = ""
    var initialQuantity: Int = 0
    var quantity: Int = 0
    var expiryDate: Date = Date()
    var purchaseDate: Date?
    var symptoms: String = ""
    var storageLocation: String = ""
    var usage: String?
    var notes: String?
    var tagsData: String = ""
    var manufacturer: String?
    var approvalNumber: String?
    var isOTC: Bool = true
    var batchNumber: String?
    var imageUrl: String?
    var boxPhotosData: String = ""
    var barcode: String?
    var traceCode: String?
    var precautionsData: String = ""
    var expiryNotifyEnabled: Bool = true
    var archiveReasonRaw: String?
    var archivedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \UsageRecord.medicine)
    var usageRecords: [UsageRecord]? = []

    @Relationship(deleteRule: .cascade, inverse: \Reminder.medicine)
    var reminders: [Reminder]? = []

    @Relationship(deleteRule: .cascade, inverse: \MedicineBoxPhoto.medicine)
    var boxPhotoRecords: [MedicineBoxPhoto]? = []

    var cabinet: MedicineCabinet?

    init(
        id: UUID = UUID(),
        name: String,
        nameEn: String? = nil,
        specification: String,
        unit: String,
        initialQuantity: Int,
        quantity: Int? = nil,
        expiryDate: Date,
        purchaseDate: Date? = nil,
        symptoms: String,
        storageLocation: String,
        usage: String? = nil,
        notes: String? = nil,
        tags: [String] = [],
        manufacturer: String? = nil,
        approvalNumber: String? = nil,
        isOTC: Bool = true,
        batchNumber: String? = nil,
        imageUrl: String? = nil,
        boxPhotoPaths: [String?] = Array(repeating: nil, count: MedicineBoxFace.count),
        barcode: String? = nil,
        traceCode: String? = nil,
        precautions: [String] = [],
        expiryNotifyEnabled: Bool = true,
        archiveReason: ArchiveReason? = nil,
        archivedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.nameEn = nameEn
        self.specification = specification
        self.unit = unit
        self.initialQuantity = initialQuantity
        self.quantity = quantity ?? initialQuantity
        self.expiryDate = expiryDate
        self.purchaseDate = purchaseDate
        self.symptoms = symptoms
        self.storageLocation = storageLocation
        self.usage = usage
        self.notes = notes
        self.tagsData = tags.joined(separator: "||")
        self.manufacturer = manufacturer
        self.approvalNumber = approvalNumber
        self.isOTC = isOTC
        self.batchNumber = batchNumber
        self.imageUrl = imageUrl
        self.boxPhotosData = Self.encodePhotoPaths(boxPhotoPaths)
        self.barcode = barcode
        self.traceCode = traceCode
        self.precautionsData = precautions.joined(separator: "||")
        self.expiryNotifyEnabled = expiryNotifyEnabled
        self.archiveReasonRaw = archiveReason?.rawValue
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var tags: [String] {
        get { tagsData.split(separator: "||").map(String.init).filter { !$0.isEmpty } }
        set { tagsData = newValue.joined(separator: "||") }
    }

    var precautions: [String] {
        get { precautionsData.split(separator: "||").map(String.init).filter { !$0.isEmpty } }
        set { precautionsData = newValue.joined(separator: "||") }
    }

    var boxPhotoPaths: [String?] {
        get { Self.decodePhotoPaths(from: boxPhotosData) }
        set { boxPhotosData = Self.encodePhotoPaths(newValue) }
    }

    private static func encodePhotoPaths(_ paths: [String?]) -> String {
        (0..<MedicineBoxFace.count).map { index in
            guard index < paths.count, let path = paths[index] else { return "" }
            return path
        }.joined(separator: "||")
    }

    private static func decodePhotoPaths(from data: String) -> [String?] {
        let parts = data.split(separator: "||", omittingEmptySubsequences: false).map(String.init)
        return (0..<MedicineBoxFace.count).map { index in
            guard index < parts.count else { return nil }
            let value = parts[index]
            return value.isEmpty ? nil : value
        }
    }

    var archiveReason: ArchiveReason? {
        get { archiveReasonRaw.flatMap(ArchiveReason.init(rawValue:)) }
        set { archiveReasonRaw = newValue?.rawValue }
    }

    func status(thresholdDays: Int, referenceDate: Date = Date(), calendar: Calendar = .current) -> MedicineStatus {
        MedicineStatusCalculator.calculateStatus(
            for: MedicineStatusInput(
                quantity: quantity,
                expiryDate: expiryDate,
                archiveReason: archiveReason,
                expiringThresholdDays: thresholdDays,
                referenceDate: referenceDate,
                calendar: calendar
            )
        )
    }

    func daysUntilExpiry(referenceDate: Date = Date(), calendar: Calendar = .current) -> Int {
        MedicineStatusCalculator.daysUntilExpiry(from: referenceDate, expiryDate: expiryDate, calendar: calendar)
    }

    func snapshot(thresholdDays: Int, referenceDate: Date = Date()) -> MedicineSnapshot {
        let currentStatus = status(thresholdDays: thresholdDays, referenceDate: referenceDate)
        return MedicineSnapshot(
            id: id,
            name: name,
            symptoms: symptoms,
            usage: usage,
            storageLocation: storageLocation,
            quantity: quantity,
            unit: unit,
            expiryDate: expiryDate,
            status: currentStatus,
            daysUntilExpiry: daysUntilExpiry(referenceDate: referenceDate),
            tags: tags
        )
    }

    func touch() {
        updatedAt = Date()
    }
}

@Model
final class UsageRecord {
    var id: UUID = UUID()
    var typeRaw: String = UsageRecordType.intake.rawValue
    var dosage: String?
    var memberId: UUID?
    var reminderId: UUID?
    var notes: String?
    var recordedAt: Date = Date()
    var medicine: Medicine?

    init(
        id: UUID = UUID(),
        type: UsageRecordType,
        dosage: String? = nil,
        memberId: UUID? = nil,
        reminderId: UUID? = nil,
        notes: String? = nil,
        recordedAt: Date = Date(),
        medicine: Medicine? = nil
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.dosage = dosage
        self.memberId = memberId
        self.reminderId = reminderId
        self.notes = notes
        self.recordedAt = recordedAt
        self.medicine = medicine
    }

    var type: UsageRecordType {
        get { UsageRecordType(rawValue: typeRaw) ?? .intake }
        set { typeRaw = newValue.rawValue }
    }
}

@Model
final class Reminder {
    var id: UUID = UUID()
    var medicineId: UUID = UUID()
    var memberId: UUID?
    var time: String = "08:00"
    var dosage: String = ""
    var instructionRaw: String = ReminderInstruction.afterMeal.rawValue
    var repeatDaysData: String = "1,2,3,4,5,6,0"
    var skippedDatesData: String = ""
    var enabled: Bool = true
    var pausedReasonRaw: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var medicine: Medicine?

    init(
        id: UUID = UUID(),
        medicineId: UUID,
        memberId: UUID? = nil,
        time: String,
        dosage: String,
        instruction: ReminderInstruction = .afterMeal,
        repeatDays: [Int] = [1, 2, 3, 4, 5, 6, 0],
        enabled: Bool = true,
        pausedReason: PausedReason? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        medicine: Medicine? = nil
    ) {
        self.id = id
        self.medicineId = medicineId
        self.memberId = memberId
        self.time = time
        self.dosage = dosage
        self.instructionRaw = instruction.rawValue
        self.repeatDaysData = repeatDays.map(String.init).joined(separator: ",")
        self.enabled = enabled
        self.pausedReasonRaw = pausedReason?.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.medicine = medicine
    }

    var instruction: ReminderInstruction {
        get { ReminderInstruction(rawValue: instructionRaw) ?? .afterMeal }
        set { instructionRaw = newValue.rawValue }
    }

    var repeatDays: [Int] {
        get { repeatDaysData.split(separator: ",").compactMap { Int($0) } }
        set { repeatDaysData = newValue.map(String.init).joined(separator: ",") }
    }

    var skippedDayTimestamps: Set<TimeInterval> {
        get {
            Set(
                skippedDatesData
                    .split(separator: ",")
                    .compactMap { TimeInterval($0) }
            )
        }
        set {
            skippedDatesData = newValue.sorted().map { String($0) }.joined(separator: ",")
        }
    }

    func isSkipped(on date: Date, calendar: Calendar = .current) -> Bool {
        skippedDayTimestamps.contains(calendar.startOfDay(for: date).timeIntervalSince1970)
    }

    func skip(on date: Date, calendar: Calendar = .current) {
        var timestamps = skippedDayTimestamps
        timestamps.insert(calendar.startOfDay(for: date).timeIntervalSince1970)
        skippedDayTimestamps = timestamps
        updatedAt = Date()
    }

    var pausedReason: PausedReason? {
        get { pausedReasonRaw.flatMap(PausedReason.init(rawValue:)) }
        set { pausedReasonRaw = newValue?.rawValue }
    }

    func weekdayMatches(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date) - 1
        return repeatDays.contains(weekday)
    }

    func timeComponents() -> DateComponents? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return DateComponents(hour: hour, minute: minute)
    }
}

@Model
final class Member {
    var id: UUID = UUID()
    var name: String = ""
    var relationRaw: String = MemberRelation.selfMember.rawValue
    var avatarUrl: String?
    var createdAt: Date = Date()
    var cabinet: MedicineCabinet?

    init(
        id: UUID = UUID(),
        name: String,
        relation: MemberRelation = .selfMember,
        avatarUrl: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.relationRaw = relation.rawValue
        self.avatarUrl = avatarUrl
        self.createdAt = createdAt
    }

    var relation: MemberRelation {
        get { MemberRelation(rawValue: relationRaw) ?? .other }
        set { relationRaw = newValue.rawValue }
    }
}

@Model
final class MedicineBoxPhoto {
    var id: UUID = UUID()
    var faceIndex: Int = 0
    @Attribute(.externalStorage) var imageData: Data = Data()
    var updatedAt: Date = Date()
    var medicine: Medicine?

    init(
        id: UUID = UUID(),
        faceIndex: Int,
        imageData: Data,
        updatedAt: Date = Date(),
        medicine: Medicine? = nil
    ) {
        self.id = id
        self.faceIndex = faceIndex
        self.imageData = imageData
        self.updatedAt = updatedAt
        self.medicine = medicine
    }
}

@Model
final class MedicineCabinet {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Medicine.cabinet)
    var medicines: [Medicine]? = []

    @Relationship(deleteRule: .cascade, inverse: \Member.cabinet)
    var members: [Member]? = []

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func touch() {
        updatedAt = Date()
    }
}

extension Medicine {
    var usageRecordsList: [UsageRecord] { usageRecords ?? [] }
    var remindersList: [Reminder] { reminders ?? [] }
    var boxPhotoRecordsList: [MedicineBoxPhoto] { boxPhotoRecords ?? [] }
}

extension MedicineCabinet {
    var medicinesList: [Medicine] { medicines ?? [] }
    var membersList: [Member] { members ?? [] }
}
