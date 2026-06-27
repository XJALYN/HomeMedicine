import CloudKit
import CoreData
import Foundation
import SwiftData
import UIKit

@MainActor
final class CloudKitSharingService: ObservableObject {
    static let shared = CloudKitSharingService()

    @Published private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published private(set) var isCheckingAccount = false
    @Published var activeShare: CKShare?
    @Published var shareContainer: CKContainer?
    @Published var lastErrorMessage: String?

    private weak var modelContainer: ModelContainer?
    private var persistenceController: CloudKitPersistenceController?

    var modelContainerForAcceptance: ModelContainer? { modelContainer }

    func configure(modelContainer: ModelContainer, persistenceController: CloudKitPersistenceController?) {
        self.modelContainer = modelContainer
        self.persistenceController = persistenceController
    }

    func refreshAccountStatus() async {
        isCheckingAccount = true
        defer { isCheckingAccount = false }
        accountStatus = await CloudKitSyncService.accountStatus()
    }

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func createShare(for cabinet: MedicineCabinet, modelContext: ModelContext) async throws -> CKShare {
        guard CloudKitAvailability.isConfigured else {
            throw CloudKitSharingError.cloudKitNotConfigured
        }
        guard accountStatus == .available else {
            throw CloudKitSharingError.iCloudUnavailable
        }
        guard let persistenceController else {
            throw CloudKitSharingError.containerUnavailable
        }
        let cloudKitContainer = persistenceController.persistentCloudKitContainer

        try modelContext.save()
        persistenceController.syncViewContextWithStore()

        guard let managedObject = await resolveManagedCabinet(
            persistenceController: persistenceController,
            cabinetId: cabinet.id
        ) else {
            throw CloudKitSharingError.recordNotSynced
        }

        if let existingShare = try fetchExistingShare(for: managedObject, cloudKitContainer: cloudKitContainer) {
            activeShare = existingShare
            shareContainer = CloudKitAvailability.container
            return existingShare
        }

        let share = try await shareManagedObject(managedObject, cloudKitContainer: cloudKitContainer)
        share[CKShare.SystemFieldKey.title] = cabinet.name as CKRecordValue
        share.publicPermission = .none
        activeShare = share
        shareContainer = CloudKitAvailability.container
        return share
    }

    func acceptShare(metadata: CKShare.Metadata, modelContext _: ModelContext) async {
        guard let persistenceController else {
            lastErrorMessage = CloudKitSharingError.containerUnavailable.localizedDescription
            return
        }
        let cloudKitContainer = persistenceController.persistentCloudKitContainer
        guard let store = persistenceController.sharedPersistentStore ?? persistenceController.privatePersistentStore else {
            lastErrorMessage = CloudKitSharingError.containerUnavailable.localizedDescription
            return
        }

        await withCheckedContinuation { continuation in
            cloudKitContainer.acceptShareInvitations(from: [metadata], into: store) { _, error in
                Task { @MainActor in
                    if let error {
                        self.lastErrorMessage = error.localizedDescription
                    } else {
                        await self.refreshAccountStatus()
                    }
                    continuation.resume()
                }
            }
        }
    }

    private func resolveManagedCabinet(
        persistenceController: CloudKitPersistenceController,
        cabinetId: UUID
    ) async -> NSManagedObject? {
        for attempt in 0..<6 {
            persistenceController.syncViewContextWithStore()
            if let managedObject = persistenceController.managedObject(
                entityName: "MedicineCabinet",
                id: cabinetId
            ) {
                return managedObject
            }
            guard attempt < 5 else { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return nil
    }

    private func fetchExistingShare(
        for managedObject: NSManagedObject,
        cloudKitContainer: NSPersistentCloudKitContainer
    ) throws -> CKShare? {
        let shares = try cloudKitContainer.fetchShares(matching: [managedObject.objectID])
        return shares[managedObject.objectID]
    }

    private func shareManagedObject(
        _ managedObject: NSManagedObject,
        cloudKitContainer: NSPersistentCloudKitContainer
    ) async throws -> CKShare {
        try await withCheckedThrowingContinuation { continuation in
            cloudKitContainer.share([managedObject], to: nil) { _, share, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let share {
                    continuation.resume(returning: share)
                } else {
                    continuation.resume(throwing: CloudKitSharingError.shareCreationFailed)
                }
            }
        }
    }
}

enum CloudKitSharingError: LocalizedError {
    case containerUnavailable
    case iCloudUnavailable
    case cloudKitNotConfigured
    case recordNotSynced
    case shareCreationFailed

    var errorDescription: String? {
        localizedMessage(locale: .current)
    }

    func localizedMessage(locale: Locale) -> String {
        let key: String
        switch self {
        case .containerUnavailable:
            key = "sharing.error.container_unavailable"
        case .iCloudUnavailable:
            key = "sharing.error.icloud_unavailable"
        case .cloudKitNotConfigured:
            key = "sharing.error.cloudkit_not_configured"
        case .recordNotSynced:
            key = "sharing.error.record_not_synced"
        case .shareCreationFailed:
            key = "sharing.error.share_creation_failed"
        }
        return L10n.t(key, locale: locale)
    }
}
