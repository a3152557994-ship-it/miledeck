import Foundation

enum FunnelEvent: String, CaseIterable {
    case onboardingCompleted = "onboarding_completed"
    case driveClassified = "drive_classified"
    case paywallViewed = "paywall_viewed"
    case purchaseTapped = "purchase_tapped"
    case abandonOfferShown = "abandon_offer_shown"
    case reviewYes = "review_yes"
    case reviewNo = "review_no"
}

/// 100% local UserDefaults funnel counter (zero network calls, preserves Apple "Data Not Collected").
enum FunnelMetrics {
    private static let keyPrefix = "miledeck.metrics."

    static func storageKey(for event: FunnelEvent) -> String {
        keyPrefix + event.rawValue
    }

    static func record(_ event: FunnelEvent, by delta: Int = 1, defaults: UserDefaults = .standard) {
        let key = storageKey(for: event)
        let next = defaults.integer(forKey: key) + delta
        defaults.set(next, forKey: key)
    }

    static func count(for event: FunnelEvent, defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: storageKey(for: event))
    }

    static func snapshot(defaults: UserDefaults = .standard) -> [String: Int] {
        var result: [String: Int] = [:]
        for event in FunnelEvent.allCases {
            result[event.rawValue] = count(for: event, defaults: defaults)
        }
        return result
    }

    static func resetAll(defaults: UserDefaults = .standard) {
        for event in FunnelEvent.allCases {
            defaults.removeObject(forKey: storageKey(for: event))
        }
    }
}
