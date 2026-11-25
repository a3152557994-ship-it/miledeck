import StoreKit
import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var store: StoreManager
    @Environment(\.dismiss) private var dismiss

    var triggerMessage: String? = nil

    @State private var selectedProductID: String = MileDeckProductID.lifetime

    private let privacyURL = URL(string: "https://a3152557994-ship-it.github.io/miledeck/privacy.html")!
    private let termsURL = URL(string: "https://a3152557994-ship-it.github.io/miledeck/terms.html")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 13) {
                    // Asphalt Dark Hero Banner
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "seal.fill")
                                .foregroundStyle(MileTheme.emeraldBright)
                            Text(L10n.t("PAY ONCE • OWN FOREVER", "买断用终身 • 告别高价年卡"))
                                .font(.caption.weight(.heavy))
                                .tracking(0.6)
                                .foregroundStyle(Color(red: 0.43, green: 0.94, blue: 0.74))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(MileTheme.emerald.opacity(0.22))
                        .clipShape(Capsule())

                        Text(L10n.t("Stop Paying $90–$140/yr\nJust to Track Your Miles", "别再为了记里程抵税\n每年交几百块订阅费"))
                            .font(.system(size: 23, weight: .heavy))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)

                        if let triggerMessage {
                            Text(triggerMessage)
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Color.white.opacity(0.84))
                        } else {
                            Text(L10n.t("Unlimited drives, swipe sorting, 2026 IRS split-rate PDFs & CSV exports — 100% offline.", "无限自动识车记里程、滑卡分类、2026 IRS 分段费率报税 PDF 与 CSV 导出，100% 本地离线。"))
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Color.white.opacity(0.82))
                        }

                        // Price Comparison Anchor (ZERO third-party trademarks!)
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t("Typical Mileage Apps", "常见订阅制里程软件"))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.white.opacity(0.65))
                                Text(L10n.t("$90–$140 / yr", "¥428–¥698 / 年"))
                                    .font(.callout.weight(.bold).monospacedDigit())
                                    .strikethrough(true, color: .red)
                                    .foregroundStyle(Color.white.opacity(0.75))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t("MileDeck Lifetime", "MileDeck 永久买断"))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color(red: 0.43, green: 0.94, blue: 0.74))
                                Text(store.displayPrice(for: MileDeckProductID.lifetime) + L10n.t(" once", " 一次付清"))
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

                    // Benefits Checklist
                    VStack(alignment: .leading, spacing: 8) {
                        benefitRow("infinity.circle.fill", L10n.t("Unlimited drive sorting & monthly exports", "无限次滑卡分类与每月报税导出（突破 20 次上限）"))
                        benefitRow("percent", L10n.t("Auto 2026 IRS split rates (72.5¢ H1 / 76¢ H2)", "自动匹配 2026 IRS 上下半年分段费率（72.5¢ / 76¢）"))
                        benefitRow("doc.richtext.fill", L10n.t("Audit-ready Schedule C PDF & CSV logbooks", "一键生成 IRS Schedule C 审计级 PDF 与 CSV 表格"))
                        benefitRow("lock.shield.fill", L10n.t("100% offline — routes never leave iPhone", "100% 本地离线，您的行车轨迹绝不上传云端"))
                    }
                    .mileCard(padding: 13)

                    // 3 Plan Options
                    VStack(spacing: 8) {
                        planCard(
                            id: MileDeckProductID.lifetime,
                            title: L10n.t("Lifetime Pro", "永久买断版"),
                            subtitle: L10n.t("Pay once • Own forever • Zero rent", "一次付清 • 终身拥有 • 永不续费"),
                            price: store.displayPrice(for: MileDeckProductID.lifetime),
                            period: L10n.t("one-time", "终身"),
                            badge: L10n.t("BEST VALUE", "首选买断")
                        )

                        planCard(
                            id: MileDeckProductID.yearly,
                            title: L10n.t("Annual Pro", "年度会员"),
                            subtitle: L10n.t("3-day free trial • Day-2 renewal reminder", "含 3 天免费试用 • 扣费前 24 小时提醒"),
                            price: store.displayPrice(for: MileDeckProductID.yearly),
                            period: L10n.t("/ year", "/ 年"),
                            badge: L10n.t("3-DAY TRIAL", "3天试用")
                        )

                        planCard(
                            id: MileDeckProductID.monthly,
                            title: L10n.t("Monthly Pro", "月度灵活版"),
                            subtitle: L10n.t("Flexible monthly • Cancel anytime", "按月付费 • 随时可在系统订阅中取消"),
                            price: store.displayPrice(for: MileDeckProductID.monthly),
                            period: L10n.t("/ month", "/ 月"),
                            badge: nil
                        )
                    }

                    // Primary CTA
                    Button {
                        Task {
                            let ok = await store.purchase(selectedProductID)
                            if ok { dismiss() }
                        }
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

                    if let status = store.statusMessage {
                        Text(status)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(MileTheme.emerald)
                            .multilineTextAlignment(.center)
                    }

                    // Non-hostile Free Exit
                    Button {
                        dismiss()
                    } label: {
                        Text(L10n.t("Continue with Free Tier (20 classified drives/month)", "暂不升级，继续使用免费版（每月 20 趟分类）"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(MileTheme.muted)
                    }
                    .padding(.top, 2)

                    // Apple 3.1.2 Compliance Disclosure + Restore + Privacy + Terms
                    VStack(spacing: 8) {
                        HStack(spacing: 18) {
                            Button(L10n.t("Restore Purchases", "恢复购买")) {
                                Task { await store.restorePurchases() }
                            }
                            Link(L10n.t("Privacy Policy", "隐私政策"), destination: privacyURL)
                            Link(L10n.t("Terms of Use", "使用条款"), destination: termsURL)
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(MileTheme.ink)

                        Text(L10n.t(
                            "Lifetime Pro is a one-time non-consumable purchase. Annual (\(store.displayPrice(for: MileDeckProductID.yearly))/year after 3-day free trial) and Monthly (\(store.displayPrice(for: MileDeckProductID.monthly))/month) subscriptions auto-renew unless canceled at least 24 hours before the end of the current period in iOS Settings > Apple Account > Subscriptions.",
                            "永久买断版为一次性买断内购。年度会员（含3天免费试用，到期按 \(store.displayPrice(for: MileDeckProductID.yearly))/年自动续订）与月度会员（\(store.displayPrice(for: MileDeckProductID.monthly))/月自动续订）可随时在 iPhone「设置 > Apple 账户 > 订阅」中提前 24 小时取消。"
                        ))
                        .font(.caption2)
                        .foregroundStyle(MileTheme.muted)
                        .multilineTextAlignment(.center)
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .background(MileTheme.roadWhite.ignoresSafeArea())
            .navigationTitle(L10n.t("MileDeck Pro", "升级 MileDeck Pro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("Close", "关闭")) { dismiss() }
                }
            }
        }
    }

    private var ctaLabel: String {
        switch selectedProductID {
        case MileDeckProductID.lifetime:
            return L10n.t(
                "Unlock Lifetime Pro — \(store.displayPrice(for: MileDeckProductID.lifetime)) Once",
                "一次买断永久版 — \(store.displayPrice(for: MileDeckProductID.lifetime))"
            )
        case MileDeckProductID.yearly:
            return L10n.t(
                "Start 3-Day Free Trial (Then \(store.displayPrice(for: MileDeckProductID.yearly))/yr)",
                "开启 3 天免费试用（随后 \(store.displayPrice(for: MileDeckProductID.yearly))/年）"
            )
        default:
            return L10n.t(
                "Subscribe Monthly — \(store.displayPrice(for: MileDeckProductID.monthly))/mo",
                "按月开通 — \(store.displayPrice(for: MileDeckProductID.monthly))/月"
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
        badge: String?
    ) -> some View {
        let selected = selectedProductID == id
        return Button {
            selectedProductID = id
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
                                .background(id == MileDeckProductID.lifetime ? MileTheme.emerald : MileTheme.amber)
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
