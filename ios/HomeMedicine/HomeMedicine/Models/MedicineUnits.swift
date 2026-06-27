import Foundation

enum MedicineUnits {
    /// Stable IDs used for localization keys (`unit.pill`, etc.).
    static let all: [String] = ["pill", "tablet", "bag", "bottle", "stick", "box"]

    /// Values persisted in SwiftData and returned by AI recognition.
    private static let storageValues: [String: String] = [
        "pill": "粒",
        "tablet": "片",
        "bag": "袋",
        "bottle": "瓶",
        "stick": "支",
        "box": "盒"
    ]

    static var defaultStorageValue: String { storageValues["pill"]! }

    static func storageValue(for id: String) -> String {
        storageValues[id] ?? id
    }

    static func id(forStorageValue value: String) -> String? {
        storageValues.first { $0.value == value }?.key
    }

    static func localized(_ storageValue: String, locale: Locale) -> String {
        if let id = id(forStorageValue: storageValue) {
            return L10n.t("unit.\(id)", locale: locale)
        }
        return storageValue
    }

    static func contains(storageValue: String) -> Bool {
        storageValues.values.contains(storageValue)
    }
}
