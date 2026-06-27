import Foundation

enum BarcodeLookupService {
    struct ProductInfo: Equatable {
        let name: String
        let specification: String
        let manufacturer: String?
        let approvalNumber: String?
        let isOTC: Bool
    }

    enum LookupResult: Equatable {
        case found(ProductInfo)
        case notFound(normalizedBarcode: String)
    }

    private struct Database: Decodable {
        let products: [ProductRecord]
    }

    private struct ProductRecord: Decodable {
        let barcode: String
        let name: String
        let specification: String
        let manufacturer: String?
        let approvalNumber: String?
        let isOTC: Bool
    }

    private static let pendingKey = "pendingBarcodeSubmissions"

    private static let database: [String: ProductInfo] = {
        guard let url = Bundle.main.url(forResource: "medicine_barcodes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Database.self, from: data) else {
            return [:]
        }

        var map: [String: ProductInfo] = [:]
        for record in decoded.products {
            let info = ProductInfo(
                name: record.name,
                specification: record.specification,
                manufacturer: record.manufacturer,
                approvalNumber: record.approvalNumber,
                isOTC: record.isOTC
            )
            for key in lookupKeys(for: record.barcode) {
                map[key] = info
            }
        }
        return map
    }()

    static func lookup(barcode raw: String) -> ProductInfo? {
        switch lookupResult(barcode: raw) {
        case .found(let info):
            return info
        case .notFound:
            return nil
        }
    }

    static func lookupResult(barcode raw: String) -> LookupResult {
        let normalized = normalizeBarcode(raw)
        guard !normalized.isEmpty else {
            return .notFound(normalizedBarcode: "")
        }

        for key in lookupKeys(for: normalized) {
            if let info = database[key] {
                return .found(info)
            }
        }

        return .notFound(normalizedBarcode: normalized)
    }

    /// Strips non-digits and normalizes UPC-A (12) / EAN-13 (13) / EAN-8 (8).
    static func normalizeBarcode(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        switch digits.count {
        case 13:
            return digits
        case 12:
            return "0" + digits
        case 8, 14:
            return digits
        default:
            return digits
        }
    }

    static func lookupKeys(for raw: String) -> [String] {
        let normalized = normalizeBarcode(raw)
        guard !normalized.isEmpty else { return [] }

        var keys = [normalized]
        if normalized.count == 13, normalized.hasPrefix("0") {
            let upc = String(normalized.dropFirst())
            if upc.count == 12 {
                keys.append(upc)
            }
        }
        if normalized.count == 12 {
            keys.append("0" + normalized)
        }
        return Array(Set(keys))
    }

    static func submitUnknownBarcode(_ barcode: String) {
        let normalized = normalizeBarcode(barcode)
        guard !normalized.isEmpty else { return }

        var pending = pendingBarcodes()
        guard !pending.contains(normalized) else { return }
        pending.append(normalized)
        UserDefaults.standard.set(pending, forKey: pendingKey)
    }

    static func pendingBarcodes() -> [String] {
        UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
    }
}
