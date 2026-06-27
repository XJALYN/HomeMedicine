import Foundation
import SwiftData
import UIKit

enum MedicineBoxPhotoStore {
    private static let cloudMarkerPrefix = "cloud:"

    private static var baseDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MedicineBoxPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func directory(for medicineId: UUID) -> URL {
        baseDirectory.appendingPathComponent(medicineId.uuidString, isDirectory: true)
    }

    static func syncPhotos(
        medicine: Medicine,
        images: [UIImage?],
        context: ModelContext
    ) throws {
        migrateLegacyPhotosIfNeeded(medicine: medicine, context: context)

        for index in 0..<MedicineBoxFace.count {
            let image = images.indices.contains(index) ? images[index] : nil
            let existing = medicine.boxPhotoRecordsList.first(where: { $0.faceIndex == index })

            if let image, let data = image.jpegData(compressionQuality: 0.85) {
                if let existing {
                    existing.imageData = data
                    existing.updatedAt = Date()
                } else {
                    context.insert(MedicineBoxPhoto(faceIndex: index, imageData: data, medicine: medicine))
                }
                try writeLocalCache(medicineId: medicine.id, faceIndex: index, data: data)
            } else {
                if let existing {
                    context.delete(existing)
                }
                deleteLocalCache(medicineId: medicine.id, faceIndex: index)
            }
        }

        medicine.boxPhotoPaths = cloudMarkers(for: medicine)
        medicine.touch()
        try context.save()
    }

    static func loadPhotos(for medicine: Medicine, context: ModelContext) -> [UIImage?] {
        migrateLegacyPhotosIfNeeded(medicine: medicine, context: context)

        return (0..<MedicineBoxFace.count).map { index in
            if let record = medicine.boxPhotoRecordsList.first(where: { $0.faceIndex == index }),
               let image = UIImage(data: record.imageData) {
                return image
            }

            if let cached = loadLocalCache(medicineId: medicine.id, faceIndex: index) {
                return cached
            }

            let paths = legacyPhotoPaths(from: medicine.boxPhotosData)
            guard index < paths.count, let path = paths[index], !path.hasPrefix(cloudMarkerPrefix) else {
                return nil
            }
            return loadPhoto(relativePath: path)
        }
    }

    /// Returns the first available box photo for list/detail cover display.
    static func loadCoverPhoto(for medicine: Medicine, context: ModelContext) -> UIImage? {
        migrateLegacyPhotosIfNeeded(medicine: medicine, context: context)

        for index in 0..<MedicineBoxFace.count {
            if let record = medicine.boxPhotoRecordsList.first(where: { $0.faceIndex == index }),
               let image = UIImage(data: record.imageData) {
                return image
            }

            if let cached = loadLocalCache(medicineId: medicine.id, faceIndex: index) {
                return cached
            }

            let paths = legacyPhotoPaths(from: medicine.boxPhotosData)
            guard index < paths.count, let path = paths[index], !path.hasPrefix(cloudMarkerPrefix),
                  let image = loadPhoto(relativePath: path) else {
                continue
            }
            return image
        }

        return nil
    }

    static func deleteAllPhotos(for medicine: Medicine, context: ModelContext) {
        for record in medicine.boxPhotoRecordsList {
            context.delete(record)
        }
        deleteAllLocalPhotos(medicineId: medicine.id)
        medicine.boxPhotoPaths = Array(repeating: nil, count: MedicineBoxFace.count)
        medicine.touch()
        try? context.save()
    }

    static func migrateLegacyPhotosIfNeeded(medicine: Medicine, context: ModelContext) {
        guard medicine.boxPhotoRecordsList.isEmpty else { return }

        let paths = legacyPhotoPaths(from: medicine.boxPhotosData)
        guard paths.contains(where: { $0 != nil }) else { return }

        for (index, path) in paths.enumerated() {
            guard let path, !path.hasPrefix(cloudMarkerPrefix),
                  let image = loadPhoto(relativePath: path),
                  let data = image.jpegData(compressionQuality: 0.85) else { continue }
            context.insert(MedicineBoxPhoto(faceIndex: index, imageData: data, medicine: medicine))
            try? writeLocalCache(medicineId: medicine.id, faceIndex: index, data: data)
        }

        medicine.boxPhotoPaths = cloudMarkers(for: medicine)
        try? context.save()
    }

    static func migrateAllLegacyPhotos(in context: ModelContext) {
        guard let medicines = try? context.fetch(FetchDescriptor<Medicine>()) else { return }
        for medicine in medicines {
            migrateLegacyPhotosIfNeeded(medicine: medicine, context: context)
        }
    }

    @discardableResult
    static func savePhotos(medicineId: UUID, images: [UIImage?], existingPaths: [String?]) throws -> [String?] {
        let dir = directory(for: medicineId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var saved: [String?] = []
        for index in 0..<MedicineBoxFace.count {
            let face = MedicineBoxFace.fileNames[index]
            let image = images.indices.contains(index) ? images[index] : nil
            let oldPath = existingPaths.indices.contains(index) ? existingPaths[index] : nil

            if let image, let data = image.jpegData(compressionQuality: 0.85) {
                let fileName = "\(face).jpg"
                let fileURL = dir.appendingPathComponent(fileName)
                try data.write(to: fileURL, options: .atomic)
                saved.append("\(medicineId.uuidString)/\(fileName)")
            } else {
                if let oldPath { deletePhoto(relativePath: oldPath) }
                saved.append(nil)
            }
        }
        return saved
    }

    static func loadPhoto(relativePath: String) -> UIImage? {
        let url = baseDirectory.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func loadPhotos(relativePaths: [String?]) -> [UIImage?] {
        (0..<MedicineBoxFace.count).map { index in
            guard index < relativePaths.count, let path = relativePaths[index] else { return nil }
            return loadPhoto(relativePath: path)
        }
    }

    static func deleteAllPhotos(medicineId: UUID) {
        deleteAllLocalPhotos(medicineId: medicineId)
    }

    static func deletePhoto(relativePath: String) {
        let url = baseDirectory.appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: url)
    }

    private static func cloudMarkers(for medicine: Medicine) -> [String?] {
        (0..<MedicineBoxFace.count).map { index in
            medicine.boxPhotoRecordsList.contains(where: { $0.faceIndex == index })
                ? "\(cloudMarkerPrefix)\(medicine.id.uuidString)/\(index)"
                : nil
        }
    }

    private static func legacyPhotoPaths(from data: String) -> [String?] {
        let parts = data.split(separator: "||", omittingEmptySubsequences: false).map(String.init)
        return (0..<MedicineBoxFace.count).map { index in
            guard index < parts.count else { return nil }
            let value = parts[index]
            return value.isEmpty ? nil : value
        }
    }

    private static func localCacheURL(medicineId: UUID, faceIndex: Int) -> URL {
        directory(for: medicineId).appendingPathComponent("\(MedicineBoxFace.fileNames[faceIndex]).jpg")
    }

    private static func writeLocalCache(medicineId: UUID, faceIndex: Int, data: Data) throws {
        let dir = directory(for: medicineId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: localCacheURL(medicineId: medicineId, faceIndex: faceIndex), options: .atomic)
    }

    private static func loadLocalCache(medicineId: UUID, faceIndex: Int) -> UIImage? {
        let url = localCacheURL(medicineId: medicineId, faceIndex: faceIndex)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private static func deleteLocalCache(medicineId: UUID, faceIndex: Int) {
        try? FileManager.default.removeItem(at: localCacheURL(medicineId: medicineId, faceIndex: faceIndex))
    }

    private static func deleteAllLocalPhotos(medicineId: UUID) {
        try? FileManager.default.removeItem(at: directory(for: medicineId))
    }
}
