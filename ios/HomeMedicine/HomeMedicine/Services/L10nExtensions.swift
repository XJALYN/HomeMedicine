import Foundation

extension L10n {
    static func t(_ key: String, locale: Locale, days: Int) -> String {
        String(format: t(key, locale: locale), days)
    }

    static func t(_ key: String, locale: Locale, count: Int) -> String {
        String(format: t(key, locale: locale), count)
    }

    static func t(_ key: String, locale: Locale, completed: Int, total: Int) -> String {
        String(format: t(key, locale: locale), completed, total)
    }

    static func t(_ key: String, locale: Locale, current: Int, total: Int) -> String {
        String(format: t(key, locale: locale), current, total)
    }

    static func t(_ key: String, locale: Locale, message: String) -> String {
        String(format: t(key, locale: locale), message)
    }
}
