import Foundation
import Combine
import SwiftUI

enum AppFontSize: String, CaseIterable, Identifiable {
    case `default`
    case medium
    case large

    var id: String { rawValue }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .default: return .medium
        case .medium: return .large
        case .large: return .xLarge
        }
    }

    func displayName(locale: Locale) -> String {
        switch self {
        case .default: return L10n.t("settings.font_size.default", locale: locale)
        case .medium: return L10n.t("settings.font_size.medium", locale: locale)
        case .large: return L10n.t("settings.font_size.large", locale: locale)
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let expiringThresholdDays = "expiringThresholdDays"
        static let intakeNotifyLeadMinutes = "intakeNotifyLeadMinutes"
        static let notificationsEnabled = "notificationsEnabled"
        static let preferredLanguageCode = "preferredLanguageCode"
        static let fontSize = "fontSize"
        static let firstLaunchDate = "firstLaunchDate"
        static let lastReviewPromptVersion = "lastReviewPromptVersion"
        static let lastReviewPromptDate = "lastReviewPromptDate"
    }

    @Published var expiringThresholdDays: Int {
        didSet { UserDefaults.standard.set(expiringThresholdDays, forKey: Keys.expiringThresholdDays) }
    }

    @Published var intakeNotifyLeadMinutes: Int {
        didSet { UserDefaults.standard.set(intakeNotifyLeadMinutes, forKey: Keys.intakeNotifyLeadMinutes) }
    }

    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    @Published var preferredLanguageCode: String? {
        didSet {
            if let preferredLanguageCode {
                UserDefaults.standard.set(preferredLanguageCode, forKey: Keys.preferredLanguageCode)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.preferredLanguageCode)
            }
        }
    }

    @Published var fontSize: AppFontSize {
        didSet { UserDefaults.standard.set(fontSize.rawValue, forKey: Keys.fontSize) }
    }

    init() {
        let defaults = UserDefaults.standard
        expiringThresholdDays = defaults.object(forKey: Keys.expiringThresholdDays) as? Int ?? 30
        intakeNotifyLeadMinutes = defaults.object(forKey: Keys.intakeNotifyLeadMinutes) as? Int ?? 15
        notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        preferredLanguageCode = defaults.string(forKey: Keys.preferredLanguageCode)
        if let raw = defaults.string(forKey: Keys.fontSize),
           let size = AppFontSize(rawValue: raw) {
            fontSize = size
        } else {
            fontSize = .default
        }
    }

    var firstLaunchDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.firstLaunchDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.firstLaunchDate) }
    }

    var lastReviewPromptVersion: String? {
        get { UserDefaults.standard.string(forKey: Keys.lastReviewPromptVersion) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastReviewPromptVersion) }
    }

    var lastReviewPromptDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.lastReviewPromptDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastReviewPromptDate) }
    }
}

enum SupportedLanguages {
    static let bundleCodes: [String] = [
        "en", "zh-Hans", "ja", "es", "de", "fr", "pt-BR", "ko", "it", "ru", "ar",
        "zh-Hant", "tr", "nl", "hi", "pl", "id", "th", "vi", "sv", "ms", "da", "fi", "nb", "el", "cs"
    ]

    static let all: [(code: String, name: String)] = [
        ("en", "English"),
        ("zh-Hans", "简体中文"),
        ("ja", "日本語"),
        ("es", "Español"),
        ("de", "Deutsch"),
        ("fr", "Français"),
        ("pt-BR", "Português (Brasil)"),
        ("ko", "한국어"),
        ("it", "Italiano"),
        ("ru", "Русский"),
        ("ar", "العربية"),
        ("zh-Hant", "繁體中文"),
        ("tr", "Türkçe"),
        ("nl", "Nederlands"),
        ("hi", "हिन्दी"),
        ("pl", "Polski"),
        ("id", "Indonesia"),
        ("th", "ไทย"),
        ("vi", "Tiếng Việt"),
        ("sv", "Svenska"),
        ("ms", "Bahasa Melayu"),
        ("da", "Dansk"),
        ("fi", "Suomi"),
        ("nb", "Norsk"),
        ("el", "Ελληνικά"),
        ("cs", "Čeština")
    ]
}

enum LocalizationBundle {
    static let supportedBundleNames: [String] = SupportedLanguages.bundleCodes

    static func bundle(for languageCode: String) -> Bundle {
        for name in candidateBundleNames(for: languageCode) {
            if let bundle = bundle(named: name) {
                return bundle
            }
        }
        return bundle(named: "en") ?? .main
    }

    static func resolvedBundleName(for languageCode: String) -> String {
        candidateBundleNames(for: languageCode).first { bundle(named: $0) != nil } ?? "en"
    }

    static func candidateBundleNames(for languageCode: String) -> [String] {
        var candidates: [String] = []
        func append(_ name: String) {
            guard !name.isEmpty, !candidates.contains(name) else { return }
            candidates.append(name)
        }

        let normalized = languageCode.replacingOccurrences(of: "_", with: "-")
        append(normalized)

        let locale = Locale(identifier: normalized)
        if let language = locale.language.languageCode?.identifier {
            if let script = locale.language.script?.identifier {
                append("\(language)-\(script)")
            }
            append(language)
        }

        let lower = normalized.lowercased()
        if lower.hasPrefix("zh") {
            if lower.contains("hant")
                || lower.hasSuffix("-tw")
                || lower.hasSuffix("-hk")
                || lower.hasSuffix("-mo") {
                append("zh-Hant")
                append("zh-Hans")
            } else {
                append("zh-Hans")
                append("zh-Hant")
            }
        }

        if lower.hasPrefix("pt") {
            append("pt-BR")
        }

        for name in supportedBundleNames where lower.hasPrefix(name.lowercased()) {
            append(name)
        }

        append("en")
        return candidates
    }

    private static func bundle(named name: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: name, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let supportedLanguages: [(code: String, name: String)] = SupportedLanguages.all

    @Published private(set) var locale: Locale

    init(settingsStore: SettingsStore? = nil) {
        locale = Self.locale(forPreferredLanguageCode: settingsStore?.preferredLanguageCode)
    }

    func applyLanguage(code: String?, settingsStore: SettingsStore) {
        settingsStore.preferredLanguageCode = code
        locale = Self.locale(forPreferredLanguageCode: code)
    }

    private static func locale(forPreferredLanguageCode code: String?) -> Locale {
        if let code {
            return Locale(identifier: code)
        }
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        let bundleName = LocalizationBundle.resolvedBundleName(for: preferred)
        return Locale(identifier: bundleName)
    }

    func localized(_ key: String) -> String {
        let bundle = LocalizationBundle.bundle(for: locale.identifier)
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }
}

enum L10n {
    static func t(_ key: String, locale: Locale = .current) -> String {
        let bundle = LocalizationBundle.bundle(for: locale.identifier)
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
