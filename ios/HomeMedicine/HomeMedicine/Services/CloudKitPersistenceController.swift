import CoreData
import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.homemedicine.app", category: "CloudKitPersistence")

/// Owns the Core Data stack used for CloudKit sharing. Must load **before** SwiftData so both
/// stacks can coexist on the same store URL (WWDC23 "Migrate to SwiftData").
@MainActor
final class CloudKitPersistenceController {
    static let cloudStoreURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudKit.store", isDirectory: false)
    }()

    static let sharedStoreURL: URL = {
        cloudStoreURL.deletingLastPathComponent()
            .appendingPathComponent("CloudKit-shared.store", isDirectory: false)
    }()

    let persistentCloudKitContainer: NSPersistentCloudKitContainer
    let privateStoreURL: URL

    var viewContext: NSManagedObjectContext {
        persistentCloudKitContainer.viewContext
    }

    static func makeIfAvailable() -> CloudKitPersistenceController? {
        guard CloudKitAvailability.isConfigured else {
            logger.error("CloudKit sharing stack skipped: CloudKit not configured in entitlements.")
            return nil
        }
        if let controller = CloudKitPersistenceController(storeURL: cloudStoreURL) {
            return controller
        }

        resetStoreFiles(at: cloudStoreURL)
        resetStoreFiles(at: sharedStoreURL)
        if let controller = CloudKitPersistenceController(storeURL: cloudStoreURL) {
            logger.warning("CloudKit sharing stack recovered after resetting incompatible store files.")
            return controller
        }

        logger.error("CloudKit sharing stack failed to load store at \(Self.cloudStoreURL.path, privacy: .public)")
        return nil
    }

    private static func resetStoreFiles(at url: URL) {
        let manager = FileManager.default
        for path in [url.path, url.path + "-shm", url.path + "-wal"] where manager.fileExists(atPath: path) {
            try? manager.removeItem(atPath: path)
        }
    }

    init?(storeURL: URL) {
        privateStoreURL = storeURL

        guard let model = Self.makeManagedObjectModel() else {
            return nil
        }
        let container = NSPersistentCloudKitContainer(name: "CloudKit", managedObjectModel: model)

        let privateDescription = NSPersistentStoreDescription(url: storeURL)
        privateDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        let cloudKitOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: CloudKitAvailability.containerIdentifier
        )
        privateDescription.cloudKitContainerOptions = cloudKitOptions

        let sharedDescription = privateDescription.copy() as! NSPersistentStoreDescription
        sharedDescription.url = Self.sharedStoreURL
        let sharedCloudKitOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: CloudKitAvailability.containerIdentifier
        )
        sharedCloudKitOptions.databaseScope = .shared
        sharedDescription.cloudKitContainerOptions = sharedCloudKitOptions

        container.persistentStoreDescriptions = [privateDescription, sharedDescription]

        var loadError: Error?
        container.loadPersistentStores { description, error in
            if let error {
                loadError = error
                logger.error(
                    "Failed to load persistent store \(description.url?.lastPathComponent ?? "?", privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        guard loadError == nil else {
            return nil
        }

        persistentCloudKitContainer = container
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// Refreshes the view context so it can see writes performed by the SwiftData stack.
    func syncViewContextWithStore() {
        let context = viewContext
        context.refreshAllObjects()
        context.processPendingChanges()
        try? context.setQueryGenerationFrom(.current)
    }

    func managedObject(entityName: String, id: UUID) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let store = privatePersistentStore {
            request.affectedStores = [store]
        }
        return try? viewContext.fetch(request).first
    }

    var privatePersistentStore: NSPersistentStore? {
        persistentCloudKitContainer.persistentStoreCoordinator.persistentStores.first { store in
            store.url == privateStoreURL
        }
    }

    var sharedPersistentStore: NSPersistentStore? {
        persistentCloudKitContainer.persistentStoreCoordinator.persistentStores.first { store in
            store.url == Self.sharedStoreURL
        }
    }

    /// Builds a Core Data model that exactly matches the SwiftData schema, then assigns generic
    /// NSManagedObject classes so they don't collide with @Model types (KVC `id` lookups fail otherwise).
    private static func makeManagedObjectModel() -> NSManagedObjectModel? {
        guard let baseModel = NSManagedObjectModel.makeManagedObjectModel(for: [
            MedicineCabinet.self,
            Medicine.self,
            MedicineBoxPhoto.self,
            UsageRecord.self,
            Reminder.self,
            Member.self
        ]) else {
            return nil
        }
        guard let model = baseModel.mutableCopy() as? NSManagedObjectModel else {
            return nil
        }

        let managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        for entity in model.entities {
            entity.managedObjectClassName = managedObjectClassName
        }
        return model
    }
}
