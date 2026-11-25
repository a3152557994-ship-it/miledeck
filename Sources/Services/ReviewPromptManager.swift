import Foundation
import StoreKit
import SwiftUI
import UIKit

@MainActor
final class ReviewPromptManager: ObservableObject {
    static let throttleInterval: TimeInterval = 90 * 24 * 3600 // Max 1x per 90 days
    static let classifiedDriveTriggerThreshold = 5
    static let feedbackEmailURL = URL(string: "mailto:a3152557994@gmail.com?subject=MileDeck%20Feedback")!

    @Published var showHappinessPrompt: Bool = false

    private let defaults: UserDefaults
    private let lastPromptKey = "miledeck.review.lastPromptTimestamp"
    private let reportPreviewSeenKey = "miledeck.review.reportPreviewSeen"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var isDemoLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui_demo_screen")
    }

    func canPrompt(now: Date = Date()) -> Bool {
        if isDemoLaunch { return false }
        let last = defaults.double(forKey: lastPromptKey)
        if last <= 0 { return true }
        return now.timeIntervalSince1970 - last >= Self.throttleInterval
    }

    func recordClassifiedDrive(totalClassified: Int, now: Date = Date()) {
        guard totalClassified >= Self.classifiedDriveTriggerThreshold else { return }
        guard totalClassified == Self.classifiedDriveTriggerThreshold || totalClassified % 25 == 0 else { return }
        triggerIfAllowed(now: now)
    }

    func recordFirstReportPreview(now: Date = Date()) {
        guard !defaults.bool(forKey: reportPreviewSeenKey) else { return }
        defaults.set(true, forKey: reportPreviewSeenKey)
        triggerIfAllowed(now: now)
    }

    @discardableResult
    func triggerIfAllowed(now: Date = Date()) -> Bool {
        guard canPrompt(now: now) else { return false }
        defaults.set(now.timeIntervalSince1970, forKey: lastPromptKey)
        showHappinessPrompt = true
        return true
    }

    func handleLoveIt(now: Date = Date()) {
        showHappinessPrompt = false
        defaults.set(now.timeIntervalSince1970, forKey: lastPromptKey)
        FunnelMetrics.record(.reviewYes, defaults: defaults)
        requestAppStoreReview()
    }

    func handleSendFeedback(now: Date = Date()) {
        showHappinessPrompt = false
        defaults.set(now.timeIntervalSince1970, forKey: lastPromptKey)
        FunnelMetrics.record(.reviewNo, defaults: defaults)
        UIApplication.shared.open(Self.feedbackEmailURL)
    }

    func handleDismiss(now: Date = Date()) {
        showHappinessPrompt = false
        defaults.set(now.timeIntervalSince1970, forKey: lastPromptKey)
    }

    private func requestAppStoreReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }
        AppStore.requestReview(in: scene)
    }
}
