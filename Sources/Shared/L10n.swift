import Foundation

enum L10n {
    static var forcedLanguage: String? = {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-ui_lang"), idx + 1 < args.count {
            return args[idx + 1]
        }
        return nil
    }()

    static var effectiveLanguageCode: String {
        forcedLanguage ?? Locale.preferredLanguages.first ?? "en"
    }

    static var isChinese: Bool {
        effectiveLanguageCode.lowercased().hasPrefix("zh")
    }

    static var isTraditionalChinese: Bool {
        isTraditionalChinese(languageCode: effectiveLanguageCode)
    }

    static func isTraditionalChinese(languageCode: String) -> Bool {
        let lower = languageCode.lowercased().replacingOccurrences(of: "_", with: "-")
        guard lower.hasPrefix("zh") else { return false }
        return lower.contains("hant")
            || lower == "zh-tw" || lower.hasPrefix("zh-tw-")
            || lower == "zh-hk" || lower.hasPrefix("zh-hk-")
            || lower == "zh-mo" || lower.hasPrefix("zh-mo-")
    }

    static func t(_ en: String, _ zh: String) -> String {
        isChinese ? zh : en
    }

    static func t(_ en: String, _ zhHans: String, _ zhHant: String) -> String {
        if isTraditionalChinese {
            return zhHant
        }
        return isChinese ? zhHans : en
    }
}
