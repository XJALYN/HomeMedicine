import Foundation

enum BailianConfig {
    private static let plistName = "BailianConfig"

    static var apiKey: String {
        if let url = Bundle.main.url(forResource: plistName, withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let key = dict["DASHSCOPE_API_KEY"] as? String,
           !key.isEmpty {
            return key
        }
        return ProcessInfo.processInfo.environment["DASHSCOPE_API_KEY"] ?? ""
    }

    static let visionModel = "qwen3-vl-flash"
    static let baseURL = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
}
