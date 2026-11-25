import Foundation
import StoreKit
import SwiftUI
import UserNotifications

enum MileDeckProductID {
    static let lifetime = "com.yanghe.miledeck.pro.lifetime"
    static let yearly = "com.yanghe.miledeck.pro.yearly"
    static let monthly = "com.yanghe.miledeck.pro.monthly"
    static let all: [String] = [lifetime, yearly, monthly]
}

@MainActor
final class StoreManager: ObservableObject {
    static let freeMonthlyDriveLimit = 20
    static let trialDurationDays = 7
    /// Day 5 reminder = 48 hours before 7-day free trial ends.
    static let trialReminderDelaySeconds: TimeInterval = 5 * 24 * 3600

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro: Bool = false
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var isPurchasing: Bool = false
    @Published var statusMessage: String?

    @Published private(set) var drivesProcessedThisMonth: Int = 0
    @Published private(set) var totalClassifiedDrives: Int = 0

    private let defaults: UserDefaults
    private let monthKey = "miledeck.quota.month"
    private let countKey = "miledeck.quota.count"
    private let totalKey = "miledeck.total.classified"
    private let proCacheKey = "miledeck.pro.cached"

    private var updatesTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        isProOverride: Bool? = nil,
        autoLoadStoreKit: Bool = true
    ) {
        self.defaults = defaults
        isPro = isProOverride ?? defaults.bool(forKey: proCacheKey)
        totalClassifiedDrives = defaults.integer(forKey: totalKey)
        syncMonthlyQuotaIfNeeded()

        if autoLoadStoreKit {
            updatesTask = Task {
                await listenForTransactions()
            }
            Task {
                await loadProducts()
                await refreshEntitlements()
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    var remainingFreeDrivesThisMonth: Int {
        max(0, Self.freeMonthlyDriveLimit - drivesProcessedThisMonth)
    }

    /// Free tier includes auto-drive logging & swipe classification up to 20 drives/month.
    var canClassifyFreeDrive: Bool {
        isPro || remainingFreeDrivesThisMonth > 0
    }

    /// Audit-ready PDF & CSV Tax Logbook exports are strictly gated behind Pro.
    var canExportTaxReport: Bool {
        isPro
    }

    /// Backward-compatible alias for drive classification quota check.
    var canClassifyOrExportFree: Bool {
        canClassifyFreeDrive
    }

    func recordClassifiedOrExportedDrive(count: Int = 1) {
        syncMonthlyQuotaIfNeeded()
        drivesProcessedThisMonth += count
        totalClassifiedDrives += count
        defaults.set(drivesProcessedThisMonth, forKey: countKey)
        defaults.set(totalClassifiedDrives, forKey: totalKey)
    }

    func syncMonthlyQuotaIfNeeded() {
        let stamp = Self.monthStamp()
        let saved = defaults.string(forKey: monthKey)
        if saved != stamp {
            defaults.set(stamp, forKey: monthKey)
            defaults.set(0, forKey: countKey)
            drivesProcessedThisMonth = 0
        } else {
            drivesProcessedThisMonth = defaults.integer(forKey: countKey)
        }
    }

    private static func monthStamp() -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.dateFormat = "yyyy-MM"
        return fmt.string(from: Date())
    }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    func displayPrice(for id: String) -> String {
        if let p = product(for: id) {
            return p.displayPrice
        }
        switch id {
        case MileDeckProductID.lifetime:
            return L10n.t("$24.99", "¥78", "HK$118")
        case MileDeckProductID.yearly:
            return L10n.t("$14.99", "¥48", "HK$68")
        case MileDeckProductID.monthly:
            return L10n.t("$4.99", "¥15", "HK$22")
        default:
            return ""
        }
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: MileDeckProductID.all)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            // Fallback display prices remain visible offline
        }
    }

    func purchase(_ productId: String) async -> Bool {
        isPurchasing = true
        statusMessage = nil
        defer { isPurchasing = false }

        if products.isEmpty {
            await loadProducts()
        }
        guard let target = product(for: productId) else {
            statusMessage = L10n.t(
                "App Store products are syncing. Please check your connection and try again.",
                "苹果商店内购信息正在同步，请检查网络后重试。",
                "App Store 內購資訊正在同步，請檢查網路後重試。"
            )
            return false
        }

        do {
            let result = try await target.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlements()
                    if productId == MileDeckProductID.yearly {
                        scheduleTrialReminder()
                    }
                    statusMessage = L10n.t(
                        "MileDeck Pro unlocked! Unlimited drives & audit-ready tax reports enabled.",
                        "已解锁 MileDeck Pro！无限行程与报税导出已全部开启。",
                        "已解鎖 MileDeck Pro！無限行車紀錄與里程報稅匯出已全部開啟。"
                    )
                    return true
                case .unverified:
                    statusMessage = L10n.t(
                        "Purchase verification failed. Please retry.",
                        "交易校验未通过，请重试。",
                        "交易驗證未通過，請重試。"
                    )
                    return false
                }
            case .userCancelled:
                return false
            case .pending:
                statusMessage = L10n.t(
                    "Purchase is pending approval.",
                    "交易等待审批中。",
                    "交易等待核准中。"
                )
                return false
            @unknown default:
                return false
            }
        } catch {
            statusMessage = L10n.t(
                "Purchase failed: \(error.localizedDescription)",
                "购买未完成：\(error.localizedDescription)",
                "購買未完成：\(error.localizedDescription)"
            )
            return false
        }
    }

    func restorePurchases() async {
        isPurchasing = true
        statusMessage = nil
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            statusMessage = isPro
                ? L10n.t("MileDeck Pro restored successfully!", "已成功恢复 MileDeck Pro 权益！", "已成功回復 MileDeck Pro 權益！")
                : L10n.t("No active purchases found on this Apple Account.", "当前苹果账号下未找到已购记录。", "目前 Apple 帳號下未找到已購項目。")
        } catch {
            statusMessage = L10n.t("Restore failed. Please try again shortly.", "恢复购买失败，请稍后再试。", "回復購買失敗，請稍後再試。")
        }
    }

    func refreshEntitlements() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               MileDeckProductID.all.contains(tx.productID),
               tx.revocationDate == nil {
                unlocked = true
                break
            }
        }
        isPro = unlocked
        defaults.set(unlocked, forKey: proCacheKey)
    }

    private func listenForTransactions() async {
        for await update in Transaction.updates {
            if case .verified(let tx) = update {
                await tx.finish()
                await refreshEntitlements()
            }
        }
    }

    private func scheduleTrialReminder() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = L10n.t(
                "MileDeck · Free Trial Ends in 48 Hours",
                "MileDeck · 免费试用还剩 48 小时",
                "MileDeck · 免費試用還剩 48 小時"
            )
            content.body = L10n.t(
                "Your 7-day free trial ends in 48 hours (Day 7). Cancel anytime in iOS Settings > Subscriptions if you don't wish to renew.",
                "您的 7 天免费试用将于 48 小时后结束，如暂不需要可在系统“订阅”中一键取消。",
                "您的 7 天免費試用將於 48 小時後結束，若暫不需要可在系統「訂閱項目」中一鍵取消。"
            )
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Self.trialReminderDelaySeconds, repeats: false)
            let req = UNNotificationRequest(identifier: "miledeck.trial.reminder", content: content, trigger: trigger)
            center.add(req)
        }
    }
}
