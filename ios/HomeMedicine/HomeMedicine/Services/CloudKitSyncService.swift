import CloudKit
import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.homemedicine.app", category: "CloudKitSync")

enum CloudKitSyncService {
    static let containerIdentifier = CloudKitAvailability.containerIdentifier

    static let modelSchema = Schema([
        MedicineCabinet.self,
        Medicine.self,
        MedicineBoxPhoto.self,
        UsageRecord.self,
        Reminder.self,
        Member.self
    ])

    static func makeModelContainer(persistenceController: CloudKitPersistenceController?) -> ModelContainer {
        var candidates: [ModelConfiguration] = []

        if persistenceController != nil {
            candidates.append(localStoreConfiguration(url: CloudKitPersistenceController.cloudStoreURL))
        }

        if CloudKitAvailability.isConfigured {
            candidates.append(
                ModelConfiguration(
                    url: CloudKitPersistenceController.cloudStoreURL,
                    cloudKitDatabase: .automatic
                )
            )
        }

        candidates.append(localStoreConfiguration(url: CloudKitPersistenceController.cloudStoreURL))
        candidates.append(ModelConfiguration(isStoredInMemoryOnly: false))
        candidates.append(ModelConfiguration(isStoredInMemoryOnly: true))

        for configuration in candidates {
            if let container = tryMakeContainer(configuration) {
                return container
            }
        }

        if CloudKitAvailability.isConfigured {
            resetStoreFiles(at: CloudKitPersistenceController.cloudStoreURL)
            resetStoreFiles(at: CloudKitPersistenceController.sharedStoreURL)

            let retryCandidates: [ModelConfiguration] = [
                persistenceController != nil
                    ? localStoreConfiguration(url: CloudKitPersistenceController.cloudStoreURL)
                    : nil,
                CloudKitAvailability.isConfigured
                    ? ModelConfiguration(
                        url: CloudKitPersistenceController.cloudStoreURL,
                        cloudKitDatabase: .automatic
                    )
                    : nil,
                localStoreConfiguration(url: CloudKitPersistenceController.cloudStoreURL),
                ModelConfiguration(isStoredInMemoryOnly: false),
                ModelConfiguration(isStoredInMemoryOnly: true)
            ].compactMap { $0 }

            for configuration in retryCandidates {
                if let container = tryMakeContainer(configuration) {
                    logger.warning("ModelContainer recovered after resetting CloudKit store files.")
                    return container
                }
            }
        }

        logger.fault("All ModelContainer configurations failed; using empty in-memory store.")
        return (try? ModelContainer(for: modelSchema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
            ?? emergencyInMemoryContainer()
    }

    /// SwiftData attaches to an store already opened by Core Data; CloudKit mirroring must stay disabled.
    private static func localStoreConfiguration(url: URL) -> ModelConfiguration {
        ModelConfiguration(url: url, cloudKitDatabase: .none)
    }

    private static func tryMakeContainer(_ configuration: ModelConfiguration) -> ModelContainer? {
        do {
            return try ModelContainer(for: modelSchema, configurations: configuration)
        } catch {
            logger.error("ModelContainer load failed (\(configurationDescription(configuration))): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static func emergencyInMemoryContainer() -> ModelContainer {
        let schema = Schema([MedicineCabinet.self])
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private static func resetStoreFiles(at url: URL) {
        let manager = FileManager.default
        let paths = [url.path, url.path + "-shm", url.path + "-wal"]
        for path in paths where manager.fileExists(atPath: path) {
            try? manager.removeItem(atPath: path)
        }
    }

    private static func configurationDescription(_ configuration: ModelConfiguration) -> String {
        if configuration.isStoredInMemoryOnly {
            return "in-memory"
        }
        return configuration.url.lastPathComponent
    }

    static func ensureDefaultCabinet(in context: ModelContext, defaultName: String) throws -> MedicineCabinet {
        var descriptor = FetchDescriptor<MedicineCabinet>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            try attachOrphans(to: existing, in: context)
            return existing
        }

        let cabinet = MedicineCabinet(name: defaultName)
        context.insert(cabinet)
        try attachOrphans(to: cabinet, in: context)
        try context.save()
        return cabinet
    }

    private static func attachOrphans(to cabinet: MedicineCabinet, in context: ModelContext) throws {
        let medicines = try context.fetch(FetchDescriptor<Medicine>())
        for medicine in medicines where medicine.cabinet == nil {
            medicine.cabinet = cabinet
        }

        let members = try context.fetch(FetchDescriptor<Member>())
        for member in members where member.cabinet == nil {
            member.cabinet = cabinet
        }

        cabinet.touch()
        try context.save()
    }

    static func migrateLegacyContent(in context: ModelContext) {
        MedicineBoxPhotoStore.migrateAllLegacyPhotos(in: context)
    }

    static func accountStatus() async -> CKAccountStatus {
        guard let container = CloudKitAvailability.container else {
            return .couldNotDetermine
        }
        do {
            return try await container.accountStatus()
        } catch {
            return .couldNotDetermine
        }
    }
}
