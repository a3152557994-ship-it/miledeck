import Foundation

enum L10n {
    static var forcedLanguage: String? = {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-ui_lang"), idx + 1 < args.count {
            return args[idx + 1]
        }
        return nil
    }()

    static var isChinese: Bool {
        if let forced = forcedLanguage {
            return forced.lowercased().hasPrefix("zh")
        }
        let pref = Locale.preferredLanguages.first ?? "en"
        return pref.lowercased().hasPrefix("zh")
    }

    static func t(_ en: String, _ zh: String) -> String {
        isChinese ? zh : en
    }
}
