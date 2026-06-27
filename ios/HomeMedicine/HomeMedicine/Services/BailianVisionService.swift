import Foundation
import UIKit

struct MedicineRecognitionResult: Equatable {
    let name: String
    let specification: String
    let manufacturer: String?
    let approvalNumber: String?
    let batchNumber: String?
    let barcode: String?
    let expiryDate: Date?
    let usage: String?
    let symptoms: String?
    let isOTC: Bool
    let unit: String?
    let quantity: Int?
    let tags: [String]
}

enum BailianVisionError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case parseError

    var errorDescription: String? {
        localizedMessage(locale: .current)
    }

    func localizedMessage(locale: Locale) -> String {
        switch self {
        case .missingAPIKey:
            return L10n.t("scan.error.missing_api_key", locale: locale)
        case .invalidResponse:
            return L10n.t("scan.error.invalid_response", locale: locale)
        case .apiError(let message):
            return L10n.t("scan.error.api_error", locale: locale, message: message)
        case .parseError:
            return L10n.t("scan.error.parse_error", locale: locale)
        }
    }
}

enum BailianVisionService {
    private static let systemPrompt = """
    你是药品包装识别助手。用户会提供药盒六个面的照片（正面、背面、左侧面、右侧面、顶面、底面）。
    请综合所有图片中的文字与图形信息，提取药品信息。
    只返回 JSON，不要 markdown 代码块，不要额外说明。字段缺失时用 null。
    tags 字段：根据药品功效从下列分类 ID 中选取 1～4 个最匹配的（只返回 ID，不要中文）：
    \(MedicineTags.tagDescriptionsForPrompt)
    JSON 格式：
    {
      "name": "药品名称",
      "specification": "规格或 null",
      "manufacturer": "生产厂家或 null",
      "approvalNumber": "批准文号或 null",
      "batchNumber": "批号或 null",
      "barcode": "条码数字或 null",
      "expiryDate": "YYYY-MM-DD 或 null",
      "usage": "用法用量或 null",
      "symptoms": "适用症状/用途或 null",
      "isOTC": true,
      "unit": "粒/片/袋/瓶/支/盒 之一或 null",
      "quantity": 数字或 null,
      "tags": ["cold", "fever"]
    }
    """

    static func recognizeMedicine(from images: [UIImage]) async throws -> MedicineRecognitionResult {
        let apiKey = BailianConfig.apiKey
        guard !apiKey.isEmpty else { throw BailianVisionError.missingAPIKey }
        guard !images.isEmpty else { throw BailianVisionError.invalidResponse }

        var content: [[String: Any]] = [
            ["type": "text", "text": "请识别这 \(images.count) 张药盒照片并返回 JSON。"]
        ]

        for image in images {
            guard let jpeg = image.jpegData(compressionQuality: 0.75) else { continue }
            let base64 = jpeg.base64EncodedString()
            content.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
            ])
        }

        let body: [String: Any] = [
            "model": BailianConfig.visionModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": content]
            ],
            "max_tokens": 2048,
            "temperature": 0.1
        ]

        var request = URLRequest(url: BailianConfig.baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if let err = try? JSONDecoder().decode(DashScopeErrorResponse.self, from: data) {
                throw BailianVisionError.apiError(err.message ?? err.error?.message ?? "HTTP \(http.statusCode)")
            }
            throw BailianVisionError.apiError("HTTP \(http.statusCode)")
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let text = completion.choices.first?.message.content, !text.isEmpty else {
            throw BailianVisionError.invalidResponse
        }

        return try parseResult(from: text)
    }

    static func parseResult(from text: String) throws -> MedicineRecognitionResult {
        let jsonString = extractJSON(from: text)
        guard let data = jsonString.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawRecognition.self, from: data) else {
            throw BailianVisionError.parseError
        }

        let name = raw.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            throw BailianVisionError.parseError
        }

        return MedicineRecognitionResult(
            name: name,
            specification: raw.specification?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            manufacturer: raw.manufacturer?.nilIfEmpty,
            approvalNumber: raw.approvalNumber?.nilIfEmpty,
            batchNumber: raw.batchNumber?.nilIfEmpty,
            barcode: raw.barcode.map { BarcodeLookupService.normalizeBarcode($0) }.flatMap { $0.isEmpty ? nil : $0 },
            expiryDate: parseDate(raw.expiryDate),
            usage: raw.usage?.nilIfEmpty,
            symptoms: raw.symptoms?.nilIfEmpty,
            isOTC: raw.isOTC ?? true,
            unit: raw.unit?.nilIfEmpty,
            quantity: raw.quantity,
            tags: MedicineTags.normalize(raw.tags)
        )
    }

    static func extractJSON(from text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }
        return trimmed
    }

    static func parseDate(_ value: String?) -> Date? {
        guard let value = value?.nilIfEmpty else { return nil }
        let formatters = ["yyyy-MM-dd", "yyyy-MM", "yyyy/MM/dd", "yyyy.MM.dd"].map { format -> DateFormatter in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            return f
        }
        for formatter in formatters {
            if let date = formatter.date(from: value) { return date }
        }
        return ExpiryOCRService.suggestDate(from: value)
    }
}

private struct RawRecognition: Decodable {
    let name: String?
    let specification: String?
    let manufacturer: String?
    let approvalNumber: String?
    let batchNumber: String?
    let barcode: String?
    let expiryDate: String?
    let usage: String?
    let symptoms: String?
    let isOTC: Bool?
    let unit: String?
    let quantity: Int?
    let tags: [String]?
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

private struct DashScopeErrorResponse: Decodable {
    struct NestedError: Decodable {
        let message: String?
    }
    let message: String?
    let error: NestedError?
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
