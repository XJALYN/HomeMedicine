import SwiftData
import XCTest
@testable import HomeMedicine

final class MedicineBoxPhotoStoreTests: XCTestCase {
    func testEncodeDecodePhotoPaths() {
        let paths: [String?] = ["abc/front.jpg", nil, "abc/left.jpg", nil, nil, "abc/bottom.jpg"]
        let encoded = Medicine(
            name: "Test",
            specification: "",
            unit: "粒",
            initialQuantity: 1,
            expiryDate: Date(),
            symptoms: "",
            storageLocation: "",
            boxPhotoPaths: paths
        ).boxPhotoPaths

        XCTAssertEqual(encoded[0], "abc/front.jpg")
        XCTAssertNil(encoded[1])
        XCTAssertEqual(encoded[2], "abc/left.jpg")
        XCTAssertEqual(encoded[5], "abc/bottom.jpg")
    }

    func testSaveAndLoadPhotos() throws {
        let id = UUID()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        var images: [UIImage?] = Array(repeating: nil, count: MedicineBoxFace.count)
        images[0] = image

        let paths = try MedicineBoxPhotoStore.savePhotos(
            medicineId: id,
            images: images,
            existingPaths: Array(repeating: nil, count: MedicineBoxFace.count)
        )

        XCTAssertNotNil(paths[0])
        XCTAssertNotNil(MedicineBoxPhotoStore.loadPhotos(relativePaths: paths)[0])
        MedicineBoxPhotoStore.deleteAllPhotos(medicineId: id)
    }

    func testSyncPhotosStoresCloudKitReadyRecords() throws {
        let schema = Schema([Medicine.self, MedicineBoxPhoto.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let medicine = Medicine(
            name: "Test",
            specification: "10mg",
            unit: "粒",
            initialQuantity: 1,
            expiryDate: Date(),
            symptoms: "test",
            storageLocation: "drawer"
        )
        context.insert(medicine)

        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        var images: [UIImage?] = Array(repeating: nil, count: MedicineBoxFace.count)
        images[1] = image

        try MedicineBoxPhotoStore.syncPhotos(medicine: medicine, images: images, context: context)

        XCTAssertEqual(medicine.boxPhotoRecordsList.count, 1)
        XCTAssertEqual(medicine.boxPhotoRecordsList.first?.faceIndex, 1)
        XCTAssertFalse(medicine.boxPhotoRecordsList.first?.imageData.isEmpty ?? true)

        let loaded = MedicineBoxPhotoStore.loadPhotos(for: medicine, context: context)
        XCTAssertNotNil(loaded[1])
        XCTAssertNil(loaded[0])
    }
}
