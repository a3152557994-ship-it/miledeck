import StoreKit
import SwiftUI

enum PaywallRegionStyle: String, CaseIterable, Equatable {
    case angloROI
    case euPrivacyLifetime
    case eastAsiaDetail

    static func resolve(for regionIdentifier: String? = Locale.current.region?.identifier) -> PaywallRegionStyle {
        let code = (regionIdentifier ?? "").uppercased()
        switch code {
        case "DE", "CH", "AT", "GB", "FR", "NL", "SE", "NO", "DK", "FI", "IE", "IT", "ES":
            return .euPrivacyLifetime
        case "JP", "KR", "TW", "HK", "MO", "SG":
            return .eastAsiaDetail
        case "US", "CA", "AU", "NZ":
            return .angloROI
        default:
            return .angloROI
        }
    }

    var defaultSelectedProductID: String {
        switch self {
        case .angloROI:
            return MileDeckProductID.yearly
        case .euPrivacyLifetime:
            return MileDeckProductID.lifetime
        case .eastAsiaDetail:
            return MileDeckProductID.lifetime
        }
    }
}

struct PaywallView: View {
    static let abandonOfferShownKey = "miledeck.paywall.abandonOfferShown"

    @EnvironmentObject private var store: StoreManager
    @Environment(\.dismiss) private var dismiss

    var triggerMessage: String? = nil
    var lockedDeductionText: String? = nil
    var regionStyleOverride: PaywallRegionStyle? = nil

    @State private var selectedProductID: String = MileDeckProductID.yearly
    @State private var didConfigureInitialSelection = false
    @State private var showAbandonOfferSheet = false

    private let privacyURL = URL(string: "https://a3152557994-ship-it.github.io/miledeck/privacy.html")!
    private let termsURL = URL(string: "https://a3152557994-ship-it.github.io/miledeck/terms.html")!
    private let supportEmailURL = URL(string: "mailto:a3152557994@gmail.com?subject=MileDeck%20Pro%20Support")!

    private var style: PaywallRegionStyle {
        if let override = regionStyleOverride { return override }
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-ui_paywall_style"), idx + 1 < args.count,
           let parsed = PaywallRegionStyle(rawValue: args[idx + 1]) {
            return parsed
        }
        return PaywallRegionStyle.resolve()
    }

    private var hasShownAbandonOfferBefore: Bool {
        UserDefaults.standard.bool(forKey: Self.abandonOfferShownKey)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    switch style {
                    case .angloROI:
                        angloHeroSection
                        angloPlanOptionsSection
                        if selectedProductID == MileDeckProductID.yearly {
                            blinkistTrialTimelineCard
                        }
                        coreBenefitsCard
                    case .euPrivacyLifetime:
                        euHeroSection
                        euPrivacyGuaranteeCard
                        euPlanOptionsSection
                        if selectedProductID == MileDeckProductID.yearly {
                            blinkistTrialTimelineCard
                        }
                    case .eastAsiaDetail:
                        eastAsiaHeroSection
                        eastAsiaComparisonGrid
                        eastAsiaPlanOptionsSection
                        if selectedProductID == MileDeckProductID.yearly {
                            blinkistTrialTimelineCard
                        }
                        eastAsiaTrustAndSupportCard
                    }

                    primaryCTAButton

                    if let status = store.statusMessage {
                        Text(status)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(MileTheme.emerald)
                            .multilineTextAlignment(.center)
                    }

                    // Non-hostile Free Exit
                    Button {
                        attemptClose()
                    } label: {
                        Text(L10n.t(
                            "Start Free (20 classified drives/month)",
                            "暂不升级，使用免费版（每月 20 趟分类）",
                            "暫不升級，使用免費版（每月 20 趟分類）"
                        ))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MileTheme.muted)
                    }
                    .padding(.top, 2)

                    appleComplianceFooter
                }
                .padding(16)
            }
            .background(MileTheme.roadWhite.ignoresSafeArea())
            .navigationTitle(L10n.t("MileDeck Pro", "升级 MileDeck Pro", "升級 MileDeck Pro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("Close", "关闭", "關閉")) {
                        attemptClose()
                    }
                }
            }
            .onAppear {
                if !didConfigureInitialSelection {
                    didConfigureInitialSelection = true
                    selectedProductID = style.defaultSelectedProductID
                }
                FunnelMetrics.record(.paywallViewed)
            }
            .sheet(isPresented: $showAbandonOfferSheet) {
                abandonOfferSheet
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - 1. Anglo ROI Hero & Plans (US/CA/AU/NZ/default)
    private var angloHeroSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(MileTheme.emeraldBright)
                Text(L10n.t("AUDIT-READY TAX DEDUCTION ENGINE", "审计级里程抵税工具", "審計級里程報稅工具"))
                    .font(.caption.weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color(red: 0.43, green: 0.94, blue: 0.74))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(MileTheme.emerald.opacity(0.22))
            .clipShape(Capsule())

            if let locked = lockedDeductionText, !locked.isEmpty {
                Text(L10n.t(
                    "Unlock Your \(locked)\nTax Deduction Logbook",
                    "立即解锁 \(locked)\n完整报税里程总账",
                    "立即解鎖 \(locked)\n完整里程報稅總帳"
                ))
                .font(.system(size: 24, weight: .heavy))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            } else {
                Text(L10n.t(
                    "Stop losing $300+/yr\nin missed miles",
                    "别再每年白白损失\n数千块合法里程抵税",
                    "別再每年白白損失\n數千塊合法里程抵稅金額"
                ))
                .font(.system(size: 24, weight: .heavy))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            }

            if let triggerMessage {
                Text(triggerMessage)
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(red: 0.98, green: 0.85, blue: 0.56))
                    .padding(.horizontal, 8)
            } else {
                Text(L10n.t(
                    "Export audit-ready PDF & CSV logbooks, sort unlimited drives, and keep every GPS route 100% offline.",
                    "一键导出审计级报税 PDF 与 CSV、无限次滑卡分类，GPS 轨迹 100% 留在本机。",
                    "一鍵匯出審計級里程報稅 PDF 與 CSV、無限次滑卡分類，GPS 軌跡 100% 留在本機。"
                ))
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white.opacity(0.84))
            }

            // Clean ROI Strip (zero third-party trademarks)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Monthly Anchor", "月度方案基准", "月度方案基準"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.65))
                    Text("\(store.displayPrice(for: MileDeckProductID.monthly))\(L10n.t("/mo", "/月", "/月"))")
                        .font(.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.82))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Annual Plan · SAVE 75%", "年度方案 · 省 75%", "年度方案 · 省 75%"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(red: 0.43, green: 0.94, blue: 0.74))
                    Text("\(store.displayPrice(for: MileDeckProductID.yearly))\(L10n.t("/yr · 7-Day Trial", "/年 · 7天试用", "/年 · 7天試用"))")
                        .font(.callout.weight(.heavy).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(MileTheme.emerald.opacity(0.26))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(MileTheme.emeraldBright, lineWidth: 1.3)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(MileTheme.asphalt)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var angloPlanOptionsSection: some View {
        VStack(spacing: 8) {
            planCard(
                id: MileDeckProductID.yearly,
                title: L10n.t("Annual Pro", "年度会员", "年度會員"),
                subtitle: L10n.t("7-day free trial • Day-5 reminder • Cancel anytime", "7 天免费试用 • 第 5 天提醒 • 随时可取消", "7 天免費試用 • 第 5 天提醒 • 隨時可取消"),
                price: store.displayPrice(for: MileDeckProductID.yearly),
                period: L10n.t("/ year", "/ 年", "/ 年"),
                badge: L10n.t("SAVE 75%", "省 75%", "省 75%"),
                badgeColor: MileTheme.emerald
            )

            planCard(
                id: MileDeckProductID.lifetime,
                title: L10n.t("Lifetime Pro", "永久买断版", "永久買斷版"),
                subtitle: L10n.t("Pay once • Own forever • Zero recurring bills", "一次买断 • 终身使用 • 永不续费", "一次買斷 • 終身使用 • 永不續費"),
                price: store.displayPrice(for: MileDeckProductID.lifetime),
                period: L10n.t("one-time", "买断", "買斷"),
                badge: L10n.t("ONLY +$10 MORE • PAY ONCE", "仅多加一点 • 永久买断", "僅多加一點 • 永久買斷"),
                badgeColor: MileTheme.amber
            )

            planCard(
                id: MileDeckProductID.monthly,
                title: L10n.t("Monthly Pro", "月度灵活版", "月度彈性版"),
                subtitle: L10n.t("Flexible monthly • Cancel anytime", "按月计费 • 随时取消", "按月計費 • 隨時取消"),
                price: store.displayPrice(for: MileDeckProductID.monthly),
                period: L10n.t("/ month", "/ 月", "/ 月"),
                badge: nil,
                badgeColor: MileTheme.muted
            )
        }
    }

    // MARK: - 2. EU Privacy & Lifetime-First Layout (DE/CH/AT/GB/FR/NL/SE/NO/DK/FI/IE/IT/ES)
    private var euHeroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(MileTheme.emerald)
                Text(L10n.t("PRIVACY-FIRST • GDPR BY DESIGN", "隐私优先 • 本地零追踪", "隱私優先 • 本機零追蹤"))
                    .font(.caption.weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(MileTheme.emerald)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(MileTheme.emeraldSoft)
            .clipShape(Capsule())

            Text(L10n.t(
                "100% Offline • Zero Cloud GPS Tracking (GDPR) • Pay Once • Zero Ads",
                "100% 本地离线 • 零云端 GPS 追踪 • 一次买断 • 零广告",
                "100% 本機離線 • 零雲端 GPS 追蹤 • 一次買斷 • 零廣告"
            ))
            .font(.system(size: 20, weight: .heavy))
            .foregroundStyle(MileTheme.ink)
            .fixedSize(horizontal: false, vertical: true)

            if let locked = lockedDeductionText, !locked.isEmpty {
                Text(L10n.t(
                    "Ready to export your \(locked) mileage logbook directly from your device as PDF or CSV.",
                    "立即从本机直接导出您的 \(locked) 报税 PDF 或 CSV 表格。",
                    "立即從本機直接匯出您的 \(locked) 里程報稅 PDF 或 CSV 表格。"
                ))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MileTheme.emerald)
            } else if let triggerMessage {
                Text(triggerMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(MileTheme.muted)
            } else {
                Text(L10n.t(
                    "Built for independent drivers who prefer fair one-time software ownership without recurring subscriptions or cloud accounts.",
                    "为注重隐私的独立车主打造：无需注册账号，一次买断安心使用。",
                    "為注重隱私的獨立車主打造：無須註冊帳號，一次買斷安心使用。"
                ))
                .font(.footnote)
                .foregroundStyle(MileTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mileCard(padding: 16)
    }

    private var euPrivacyGuaranteeCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            benefitRow("iphone.gen3.radiowaves.left.and.right", L10n.t("GPS locations processed & stored strictly on-device (GDPR safe)", "GPS 定位与行车路线仅存于本机，绝不上传云端", "GPS 定位與行車紀錄僅存於本機，絕不上傳雲端"))
            benefitRow("doc.richtext.fill", L10n.t("Unlimited PDF & CSV mileage logbooks (HMRC, EU, IRS, ATO, CRA)", "无限导出审计级 PDF 与 CSV 总账（支持多国税率）", "無限匯出審計級 PDF 與 CSV 總帳（支援多國稅率）"))
            benefitRow("infinity.circle.fill", L10n.t("Unlimited drive sorting & multi-vehicle odometer tracking", "无限趟行程分类与多车辆里程表记录", "無限趟行車紀錄分類與多車輛里程錶管理"))
            benefitRow("externaldrive.fill.badge.checkmark", L10n.t("Full JSON data ownership — export or back up anytime", "数据完全归您所有，随时导出本地 JSON 备份", "資料完全歸您所有，隨時匯出本機 JSON 備份"))
        }
        .mileCard(padding: 14)
    }

    private var euPlanOptionsSection: some View {
        VStack(spacing: 8) {
            // Lifetime Pro FIRST & pre-selected
            planCard(
                id: MileDeckProductID.lifetime,
                title: L10n.t("Lifetime Pro (Recommended)", "永久买断版（推荐）", "永久買斷版（推薦）"),
                subtitle: L10n.t("Single one-time payment • Own forever • No subscription", "一次性买断 • 终身使用 • 无任何续费", "一次性買斷 • 終身使用 • 無任何續費"),
                price: store.displayPrice(for: MileDeckProductID.lifetime),
                period: L10n.t("pay once", "一次买断", "一次買斷"),
                badge: L10n.t("PAY ONCE", "买断推荐", "買斷推薦"),
                badgeColor: MileTheme.asphalt
            )

            planCard(
                id: MileDeckProductID.yearly,
                title: L10n.t("Annual Pro", "年度方案", "年度方案"),
                subtitle: L10n.t("7-day free trial • Day-5 reminder • Cancel anytime", "含 7 天免费试用 • 第 5 天提醒 • 随时可取消", "含 7 天免費試用 • 第 5 天提醒 • 隨時可取消"),
                price: store.displayPrice(for: MileDeckProductID.yearly),
                period: L10n.t("/ year", "/ 年", "/ 年"),
                badge: L10n.t("7-DAY TRIAL", "7天试用", "7天試用"),
                badgeColor: MileTheme.emerald
            )

            planCard(
                id: MileDeckProductID.monthly,
                title: L10n.t("Monthly Pro", "月度方案", "月度方案"),
                subtitle: L10n.t("Month-to-month flexibility • Cancel anytime", "按月灵活使用 • 随时取消", "按月彈性使用 • 隨時取消"),
                price: store.displayPrice(for: MileDeckProductID.monthly),
                period: L10n.t("/ month", "/ 月", "/ 月"),
                badge: nil,
                badgeColor: MileTheme.muted
            )
        }
    }

    // MARK: - 3. East Asia High-Information Trust Paywall (JP/KR/TW/HK/MO/SG)
    private var eastAsiaHeroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    L10n.t("TRANSPARENT PRICING & FULL FEATURE SPEC", "方案明细透明公开 • 绝无隐藏扣费", "方案明細透明公開 • 絕無隱藏扣款"),
                    systemImage: "checkmark.shield.fill"
                )
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color(red: 0.43, green: 0.94, blue: 0.74))
                Spacer()
            }

            if let locked = lockedDeductionText, !locked.isEmpty {
                Text(L10n.t(
                    "Export Your \(locked) Tax Logbook",
                    "完整导出您的 \(locked) 报税里程总账",
                    "完整匯出您的 \(locked) 里程報稅總帳"
                ))
                .font(.title3.weight(.heavy))
                .foregroundStyle(.white)
            } else {
                Text(L10n.t(
                    "MileDeck Pro · Offline Mileage & Tax Logbook",
                    "MileDeck Pro · 100% 离线里程报税工具",
                    "MileDeck Pro · 100% 離線里程報稅與行車紀錄"
                ))
                .font(.title3.weight(.heavy))
                .foregroundStyle(.white)
            }

            if let triggerMessage {
                Text(triggerMessage)
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.98, green: 0.85, blue: 0.56))
            } else {
                Text(L10n.t(
                    "Compare Free vs Pro below. Choose one-time Lifetime ownership or a 7-day risk-free trial.",
                    "下方清晰对比免费版与专业版权益，支持一次买断终身用或 7 天免费试用。",
                    "下方清晰對照免費版與專業版權益，支援一次買斷終身使用或 7 天免費試用。"
                ))
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.84))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MileTheme.asphalt)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var eastAsiaComparisonGrid: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("Feature Comparison", "功能权益对比", "功能權益對照"))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(MileTheme.ink)
                Spacer()
                Text(L10n.t("Free", "免费版", "免費版"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(MileTheme.muted)
                    .frame(width: 58, alignment: .center)
                Text("Pro")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(MileTheme.emerald)
                    .frame(width: 64, alignment: .center)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(MileTheme.roadWhite)

            Divider()
            comparisonRow(
                L10n.t("Auto GPS Drive Logging", "自动 GPS 行车记录", "自動 GPS 行車紀錄"),
                freeText: "✓",
                proText: "✓"
            )
            Divider()
            comparisonRow(
                L10n.t("Monthly Swipe Classifications", "每月滑卡分类次数", "每月滑卡分類次數"),
                freeText: L10n.t("20 / mo", "20 次/月", "20 次/月"),
                proText: L10n.t("Unlimited", "无限次", "無限次")
            )
            Divider()
            comparisonRow(
                L10n.t("Multi-Country Tax Rate Engine", "多国官方抵税费率引擎", "多國官方抵稅費率引擎"),
                freeText: "✓",
                proText: "✓"
            )
            Divider()
            comparisonRow(
                L10n.t("Audit-Ready PDF & CSV Export", "报税 PDF 盖章总账 & CSV 导出", "里程報稅 PDF 總帳 & CSV 匯出"),
                freeText: L10n.t("Preview", "仅预览", "僅預覽"),
                proText: L10n.t("Unlimited", "无限导出", "無限匯出")
            )
            Divider()
            comparisonRow(
                L10n.t("100% Offline & JSON Backup", "100% 本地离线与 JSON 备份", "100% 本機離線與 JSON 備份"),
                freeText: "✓",
                proText: "✓"
            )
        }
        .background(MileTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MileTheme.border, lineWidth: 1)
        )
    }

    private func comparisonRow(_ feature: String, freeText: String, proText: String) -> some View {
        HStack {
            Text(feature)
                .font(.caption.weight(.medium))
                .foregroundStyle(MileTheme.ink)
            Spacer()
            Text(freeText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MileTheme.muted)
                .frame(width: 58, alignment: .center)
            Text(proText)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(MileTheme.emerald)
                .frame(width: 64, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var eastAsiaPlanOptionsSection: some View {
        VStack(spacing: 8) {
            planCard(
                id: MileDeckProductID.lifetime,
                title: L10n.t("Lifetime Pro", "永久买断版", "永久買斷版"),
                subtitle: L10n.t("Pay once • No auto-renewal • Own forever", "一次买断 • 绝不自动续费 • 终身拥有", "一次買斷 • 絕不自動續訂 • 終身擁有"),
                price: store.displayPrice(for: MileDeckProductID.lifetime),
                period: L10n.t("one-time", "买断", "買斷"),
                badge: L10n.t("MOST POPULAR", "最多人买断", "最多人買斷"),
                badgeColor: MileTheme.emerald
            )

            planCard(
                id: MileDeckProductID.yearly,
                title: L10n.t("Annual Pro", "年度会员", "年度會員"),
                subtitle: L10n.t("7-day free trial ($0 today) • Day-5 reminder", "7 天免费试用（今日 $0）• 第 5 天提醒", "7 天免費試用（今日 $0）• 第 5 天提醒"),
                price: store.displayPrice(for: MileDeckProductID.yearly),
                period: L10n.t("/ year", "/ 年", "/ 年"),
                badge: L10n.t("7-DAY FREE TRIAL", "7天免费试用", "7天免費試用"),
                badgeColor: MileTheme.amber
            )

            planCard(
                id: MileDeckProductID.monthly,
                title: L10n.t("Monthly Pro", "月度会员", "月度會員"),
                subtitle: L10n.t("Billed monthly • Cancel in 10 seconds", "按月订阅 • 随时 10 秒取消", "按月訂閱 • 隨時 10 秒取消"),
                price: store.displayPrice(for: MileDeckProductID.monthly),
                period: L10n.t("/ month", "/ 月", "/ 月"),
                badge: nil,
                badgeColor: MileTheme.muted
            )
        }
    }

    private var eastAsiaTrustAndSupportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "gearshape.2.fill")
                    .foregroundStyle(MileTheme.asphalt)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Explicit 2-Tap Cancellation Path", "明确退订路径（绝不设障）", "明確取消訂閱路徑（絕不設障）"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MileTheme.ink)
                    Text(L10n.t(
                        "iPhone Settings > Apple Account > Subscriptions > MileDeck > Cancel Subscription. Trial ends automatically with $0 charged if canceled before Day 7.",
                        "打开 iPhone「设置 > Apple 账户 > 订阅 > MileDeck > 取消订阅」。试用第 7 天前取消完全不扣费。",
                        "開啟 iPhone「設定 > Apple 帳號 > 訂閱項目 > MileDeck > 取消訂閱」。試用第 7 天前取消完全不扣款。"
                    ))
                    .font(.caption2)
                    .foregroundStyle(MileTheme.muted)
                }
            }

            Divider()

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .foregroundStyle(MileTheme.emerald)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Direct Developer Email Guarantee", "独立开发者直邮支持保障", "獨立開發者直郵客服保障"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MileTheme.ink)
                    Text(L10n.t(
                        "Questions about tax rates, invoices, or restore? Email the developer directly:",
                        "遇到税率设置、导出或恢复购买问题，可直接发邮件联系开发者：",
                        "遇到稅率設定、匯出或回復購買問題，可直接寄信聯繫開發者："
                    ))
                    .font(.caption2)
                    .foregroundStyle(MileTheme.muted)
                    Link("a3152557994@gmail.com", destination: supportEmailURL)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MileTheme.emerald)
                }
            }
        }
        .mileCard(padding: 13)
    }

    // MARK: - Blinkist Honest 7-Day Trial Timeline
    private var blinkistTrialTimelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(MileTheme.emerald)
                Text(L10n.t("HOW YOUR 7-DAY FREE TRIAL WORKS", "7 天免费试用透明时间轴", "7 天免費試用透明時間軸"))
                    .font(.caption.weight(.heavy))
                    .tracking(0.4)
                    .foregroundStyle(MileTheme.ink)
            }

            VStack(alignment: .leading, spacing: 0) {
                timelineStep(
                    icon: "lock.open.fill",
                    iconColor: MileTheme.emerald,
                    title: L10n.t("Today · $0 Unlock All", "今日 · 0 元解锁全部功能", "今日 · $0 解鎖全部功能"),
                    subtitle: L10n.t("Export unlimited tax PDF & CSV logbooks and sort unlimited drives immediately.", "立刻导出报税 PDF 与 CSV 总账，畅享无限趟滑卡分类。", "立刻匯出里程報稅 PDF 與 CSV 總帳，無限趟滑卡分類。"),
                    showLineBelow: true
                )
                timelineStep(
                    icon: "bell.badge.fill",
                    iconColor: MileTheme.amber,
                    title: L10n.t("Day 5 · Reminder Before Billing", "第 5 天 · 扣费前 48 小时提醒", "第 5 天 · 扣款前 48 小時提醒"),
                    subtitle: L10n.t("We send a local iOS notification 48 hours before your trial ends — zero surprises.", "提前 48 小时通过本机通知提醒您，绝不偷偷扣费。", "提前 48 小時透過本機通知提醒您，絕不偷偷扣款。"),
                    showLineBelow: true
                )
                timelineStep(
                    icon: "checkmark.seal.fill",
                    iconColor: MileTheme.asphalt,
                    title: L10n.t("Day 7 · Annual Plan Starts, Cancel Anytime", "第 7 天 · 开启年度方案，随时可取消", "第 7 天 · 開啟年度方案，隨時可取消"),
                    subtitle: L10n.t(
                        "Billed \(store.displayPrice(for: MileDeckProductID.yearly))/yr unless canceled beforehand in iOS Settings.",
                        "如未取消将按 \(store.displayPrice(for: MileDeckProductID.yearly))/年续订，随时可在系统设置取消。",
                        "如未取消將按 \(store.displayPrice(for: MileDeckProductID.yearly))/年續訂，隨時可在系統設定取消。"
                    ),
                    showLineBelow: false
                )
            }
        }
        .mileCard(padding: 14)
    }

    private func timelineStep(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        showLineBelow: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.16))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(iconColor)
                }
                if showLineBelow {
                    Rectangle()
                        .fill(MileTheme.border)
                        .frame(width: 2, height: 26)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(MileTheme.ink)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(MileTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, showLineBelow ? 8 : 0)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Shared Components
    private var coreBenefitsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            benefitRow("doc.richtext.fill", L10n.t("Audit-ready PDF & CSV tax logbook exports", "一键导出审计级报税 PDF 与 CSV 表格", "一鍵匯出審計級里程報稅 PDF 與 CSV 表格"))
            benefitRow("infinity.circle.fill", L10n.t("Unlimited drive sorting (remove 20/month cap)", "无限次滑卡分类（突破每月 20 趟上限）", "無限次滑卡分類（突破每月 20 趟上限）"))
            benefitRow("globe", L10n.t("Auto US IRS 2026, UK HMRC, AU ATO, CA CRA & EU rates", "内置美/英/澳/加/欧官方抵税费率引擎", "內建美/英/澳/加/歐官方抵稅費率引擎"))
            benefitRow("lock.shield.fill", L10n.t("100% offline — routes never leave your iPhone", "100% 本地离线，您的行车轨迹绝不上传云端", "100% 本機離線，您的行車紀錄絕不上傳雲端"))
        }
        .mileCard(padding: 13)
    }

    private var primaryCTAButton: some View {
        Button {
            purchaseProduct(selectedProductID)
        } label: {
            HStack(spacing: 8) {
                if store.isPurchasing {
                    ProgressView().tint(.white)
                }
                Text(ctaLabel)
                    .font(.headline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(MileTheme.emerald)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(store.isPurchasing)
    }

    private var appleComplianceFooter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 18) {
                Button(L10n.t("Restore Purchases", "恢复购买", "回復購買")) {
                    Task { await store.restorePurchases() }
                }
                Link(L10n.t("Privacy Policy", "隐私政策", "隱私權政策"), destination: privacyURL)
                Link(L10n.t("Terms of Use", "使用条款", "使用條款"), destination: termsURL)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(MileTheme.ink)

            Text(L10n.t(
                "Lifetime Pro is a one-time non-consumable purchase (\(store.displayPrice(for: MileDeckProductID.lifetime))). Annual (\(store.displayPrice(for: MileDeckProductID.yearly))/year after 7-day free trial) and Monthly (\(store.displayPrice(for: MileDeckProductID.monthly))/month) subscriptions auto-renew unless canceled at least 24 hours before the end of the current period in iOS Settings > Apple Account > Subscriptions.",
                "永久买断版为一次性买断内购（\(store.displayPrice(for: MileDeckProductID.lifetime))）。年度会员（含 7 天免费试用，到期按 \(store.displayPrice(for: MileDeckProductID.yearly))/年自动续订）与月度会员（\(store.displayPrice(for: MileDeckProductID.monthly))/月自动续订）可随时在 iPhone「设置 > Apple 账户 > 订阅」中提前 24 小时取消。",
                "永久買斷版為一次性買斷內購（\(store.displayPrice(for: MileDeckProductID.lifetime))）。年度會員（含 7 天免費試用，期滿按 \(store.displayPrice(for: MileDeckProductID.yearly))/年自動續訂）與月度會員（\(store.displayPrice(for: MileDeckProductID.monthly))/月自動續訂）可隨時在 iPhone「設定 > Apple 帳號 > 訂閱項目」中提前 24 小時取消。"
            ))
            .font(.caption2)
            .foregroundStyle(MileTheme.muted)
            .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    // MARK: - 1-Time Non-Annoying Abandon Offer Sheet (NO fake countdown timers!)
    private var abandonOfferSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.thumbsup.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(MileTheme.emerald)
                .padding(.top, 8)

            Text(L10n.t(
                "Prefer zero risk?",
                "想先零风险免费体验？",
                "想先零風險免費體驗？"
            ))
            .font(.title2.weight(.heavy))
            .foregroundStyle(MileTheme.ink)

            Text(L10n.t(
                "Start a 7-Day Free Trial ($0 today) with an automatic Day-5 reminder — or choose Lifetime Pro once and never think about renewals.",
                "现在开启 7 天免费试用（今日 0 元，第 5 天自动提醒）——或一次买断永久版，终身免续费。",
                "現在開啟 7 天免費試用（今日 $0，第 5 天自動提醒）——或一次買斷永久版，終身免續訂。"
            ))
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundStyle(MileTheme.muted)
            .padding(.horizontal, 12)

            VStack(spacing: 10) {
                Button {
                    showAbandonOfferSheet = false
                    purchaseProduct(MileDeckProductID.yearly)
                } label: {
                    Text(L10n.t(
                        "Start 7-Day Free Trial ($0 Today)",
                        "开启 7 天免费试用（今日 ¥0）",
                        "開啟 7 天免費試用（今日 $0）"
                    ))
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(MileTheme.emerald)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(store.isPurchasing)

                Button {
                    showAbandonOfferSheet = false
                    purchaseProduct(MileDeckProductID.lifetime)
                } label: {
                    Text(L10n.t(
                        "Or Own Forever — \(store.displayPrice(for: MileDeckProductID.lifetime)) One-Time",
                        "或一次买断永久版 — \(store.displayPrice(for: MileDeckProductID.lifetime))",
                        "或一次買斷永久版 — \(store.displayPrice(for: MileDeckProductID.lifetime))"
                    ))
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(MileTheme.asphalt)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(store.isPurchasing)

                Button {
                    showAbandonOfferSheet = false
                    dismiss()
                } label: {
                    Text(L10n.t("No thanks, continue free", "不了，继续使用免费版", "不用了，繼續使用免費版"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MileTheme.muted)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 18)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .background(MileTheme.roadWhite.ignoresSafeArea())
    }

    private func attemptClose() {
        let isDemoLaunch = ProcessInfo.processInfo.arguments.contains("-ui_demo_screen")
        if !store.isPro && !hasShownAbandonOfferBefore && !isDemoLaunch {
            UserDefaults.standard.set(true, forKey: Self.abandonOfferShownKey)
            FunnelMetrics.record(.abandonOfferShown)
            showAbandonOfferSheet = true
        } else {
            dismiss()
        }
    }

    private func purchaseProduct(_ productID: String) {
        FunnelMetrics.record(.purchaseTapped)
        Task {
            let ok = await store.purchase(productID)
            if ok { dismiss() }
        }
    }

    private var ctaLabel: String {
        switch selectedProductID {
        case MileDeckProductID.lifetime:
            return L10n.t(
                "Unlock Lifetime Pro — \(store.displayPrice(for: MileDeckProductID.lifetime)) Once",
                "一次买断永久版 — \(store.displayPrice(for: MileDeckProductID.lifetime))",
                "一次買斷永久版 — \(store.displayPrice(for: MileDeckProductID.lifetime))"
            )
        case MileDeckProductID.yearly:
            return L10n.t(
                "Start 7-Day Free Trial (Then \(store.displayPrice(for: MileDeckProductID.yearly))/yr)",
                "开启 7 天免费试用（随后 \(store.displayPrice(for: MileDeckProductID.yearly))/年）",
                "開啟 7 天免費試用（隨後 \(store.displayPrice(for: MileDeckProductID.yearly))/年）"
            )
        default:
            return L10n.t(
                "Subscribe Monthly — \(store.displayPrice(for: MileDeckProductID.monthly))/mo",
                "按月开通 — \(store.displayPrice(for: MileDeckProductID.monthly))/月",
                "按月開通 — \(store.displayPrice(for: MileDeckProductID.monthly))/月"
            )
        }
    }

    private func benefitRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MileTheme.emerald)
                .frame(width: 22)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MileTheme.ink)
            Spacer()
        }
    }

    private func planCard(
        id: String,
        title: String,
        subtitle: String,
        price: String,
        period: String,
        badge: String?,
        badgeColor: Color
    ) -> some View {
        let selected = selectedProductID == id
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedProductID = id
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? MileTheme.emerald : MileTheme.border)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(MileTheme.ink)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .heavy))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(badgeColor)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(MileTheme.muted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(price)
                        .font(.headline.weight(.heavy).monospacedDigit())
                        .foregroundStyle(MileTheme.ink)
                    Text(period)
                        .font(.caption2)
                        .foregroundStyle(MileTheme.muted)
                }
            }
            .padding(11)
            .background(selected ? MileTheme.emeraldSoft : MileTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? MileTheme.emerald : MileTheme.border, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
