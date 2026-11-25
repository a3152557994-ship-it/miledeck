import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var ledger: MileageStore

    var onComplete: (_ openPaywall: Bool, _ estimatedDeductionText: String?) -> Void

    @State private var step: Int = 0
    @State private var selectedRegion: TaxRegionPreset = .usIRS2026
    @State private var weeklyDistance: Double = 150
    @State private var didInitialize = false

    private var sliderRange: ClosedRange<Double> {
        selectedRegion.defaultUnit == .miles ? 20...800 : 30...1200
    }

    private var sliderStep: Double {
        selectedRegion.defaultUnit == .miles ? 10 : 15
    }

    private var annualDistance: Double {
        weeklyDistance * 52.0
    }

    private var estimatedAnnualDeduction: Double {
        IRSRateEngine.estimatedAnnualDeduction(weeklyUnits: weeklyDistance, preset: selectedRegion)
    }

    private var formattedEstimatedDeduction: String {
        IRSRateEngine.formatWholeMoney(estimatedAnnualDeduction, symbol: selectedRegion.currencySymbol)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Step Progress Indicator
                HStack(spacing: 8) {
                    Capsule()
                        .fill(MileTheme.emerald)
                        .frame(height: 5)
                    Capsule()
                        .fill(step >= 1 ? MileTheme.emerald : MileTheme.border)
                        .frame(height: 5)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                ScrollView {
                    VStack(spacing: 18) {
                        if step == 0 {
                            regionSelectionStep
                        } else {
                            deductionCalculatorStep
                        }
                    }
                    .padding(20)
                }

                // Bottom Sticky CTA Bar
                VStack(spacing: 10) {
                    if step == 0 {
                        Button {
                            ledger.settings.applyTaxRegion(selectedRegion)
                            withAnimation(.easeInOut(duration: 0.22)) {
                                step = 1
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(L10n.t("Calculate My Tax Savings", "测算我的年度抵税额", "試算我的年度抵稅金額"))
                                    .font(.headline.weight(.bold))
                                Image(systemName: "arrow.right")
                                    .font(.subheadline.weight(.bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(MileTheme.emerald)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    } else {
                        Button {
                            finishOnboarding(openPaywall: true)
                        } label: {
                            HStack(spacing: 8) {
                                Text(L10n.t("Continue", "继续", "繼續"))
                                    .font(.headline.weight(.bold))
                                Image(systemName: "arrow.right")
                                    .font(.subheadline.weight(.bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(MileTheme.emerald)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        Button {
                            finishOnboarding(openPaywall: false)
                        } label: {
                            Text(L10n.t("Start Free (20 drives/mo)", "免费开始使用（每月 20 趟）", "免費開始使用（每月 20 趟）"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MileTheme.muted)
                                .padding(.vertical, 4)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(MileTheme.card.shadow(color: MileTheme.asphalt.opacity(0.06), radius: 8, y: -2))
            }
            .background(MileTheme.roadWhite.ignoresSafeArea())
            .toolbar {
                if step == 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { step = 0 }
                        } label: {
                            Label(L10n.t("Region", "地区", "地區"), systemImage: "chevron.left")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("Skip", "跳过", "略過")) {
                        finishOnboarding(openPaywall: false)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MileTheme.muted)
                }
            }
            .onAppear {
                guard !didInitialize else { return }
                didInitialize = true
                selectedRegion = ledger.settings.taxRegion
                weeklyDistance = selectedRegion.defaultUnit == .miles ? 150 : 240
            }
        }
    }

    // MARK: - Step 1: Pick Driving Region / Tax Preset
    private var regionSelectionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "road.lanes")
                        .foregroundStyle(MileTheme.emerald)
                    Text(L10n.t("STEP 1 OF 2 · 30-SECOND SETUP", "第 1/2 步 · 30 秒快速配置", "第 1/2 步 · 30 秒快速設定"))
                        .font(.caption.weight(.heavy))
                        .tracking(0.5)
                        .foregroundStyle(MileTheme.emerald)
                }

                Text(L10n.t(
                    "Where do you file mileage deductions?",
                    "您按哪个国家/地区标准报税？",
                    "您依哪個國家／地區標準申報里程報稅？"
                ))
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(MileTheme.ink)

                Text(L10n.t(
                    "MileDeck automatically applies official tax rates, currency, and distance units — 100% offline on your iPhone.",
                    "MileDeck 自动匹配官方抵税费率、货币与里程单位，所有行车数据 100% 留在本机。",
                    "MileDeck 自動套用官方抵稅費率、幣別與里程單位，所有行車紀錄 100% 留在本機。"
                ))
                .font(.subheadline)
                .foregroundStyle(MileTheme.muted)
            }

            VStack(spacing: 10) {
                ForEach(TaxRegionPreset.allCases) { preset in
                    let isSelected = selectedRegion == preset
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selectedRegion = preset
                            weeklyDistance = preset.defaultUnit == .miles ? 150 : 240
                            ledger.settings.applyTaxRegion(preset)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text(preset.flagEmoji)
                                .font(.title2)
                                .frame(width: 36, height: 36)
                                .background(isSelected ? MileTheme.emeraldSoft : MileTheme.roadWhite)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(preset.displayName)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(MileTheme.ink)
                                Text(preset.rateSummaryBadge)
                                    .font(.caption.weight(.medium).monospacedDigit())
                                    .foregroundStyle(MileTheme.muted)
                            }

                            Spacer()

                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isSelected ? MileTheme.emerald : MileTheme.border)
                        }
                        .padding(13)
                        .background(isSelected ? MileTheme.emeraldSoft : MileTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(isSelected ? MileTheme.emerald : MileTheme.border, lineWidth: isSelected ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Step 2: Live Weekly Distance -> Annual Deduction Calculator
    private var deductionCalculatorStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(MileTheme.emerald)
                    Text(L10n.t("STEP 2 OF 2 · DEDUCTION CALCULATOR", "第 2/2 步 · 年度抵税额估算", "第 2/2 步 · 年度抵稅金額試算"))
                        .font(.caption.weight(.heavy))
                        .tracking(0.5)
                        .foregroundStyle(MileTheme.emerald)
                }

                Text(L10n.t(
                    "How much do you drive for work each week?",
                    "您每周大概开多少商务里程？",
                    "您每週大約開多少商務里程？"
                ))
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(MileTheme.ink)
            }

            // Live Big-Number Asphalt Telemetry Card
            VStack(spacing: 12) {
                HStack {
                    Text("\(selectedRegion.flagEmoji) \(selectedRegion.shortName)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.82))
                    Spacer()
                    Text(selectedRegion.rateSummaryBadge)
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(MileTheme.emerald.opacity(0.28))
                        .foregroundStyle(Color(red: 0.43, green: 0.94, blue: 0.74))
                        .clipShape(Capsule())
                }

                VStack(spacing: 4) {
                    Text(L10n.t("ESTIMATED ANNUAL TAX DEDUCTION", "预计全年可合法抵税", "預估全年可申報抵稅金額"))
                        .font(.caption2.weight(.heavy))
                        .tracking(0.6)
                        .foregroundStyle(Color.white.opacity(0.68))

                    Text(formattedEstimatedDeduction)
                        .font(.system(size: 48, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Color(red: 0.30, green: 0.93, blue: 0.70))
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.15), value: weeklyDistance)

                    Text(L10n.t(
                        "based on \(Int(annualDistance.rounded())) \(selectedRegion.defaultUnit.shortLabel)/year",
                        "按全年 \(Int(annualDistance.rounded())) \(selectedRegion.defaultUnit.shortLabel) 自动折算",
                        "依全年 \(Int(annualDistance.rounded())) \(selectedRegion.defaultUnit.shortLabel) 自動試算"
                    ))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.75))
                }
                .padding(.vertical, 8)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(MileTheme.asphalt)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            // Interactive Slider Card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.t("Weekly Business Driving", "每周商务行驶距离", "每週商務行駛距離"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(MileTheme.ink)
                    Spacer()
                    Text("\(Int(weeklyDistance.rounded())) \(selectedRegion.defaultUnit.shortLabel) / \(L10n.t("wk", "周", "週"))")
                        .font(.headline.weight(.heavy).monospacedDigit())
                        .foregroundStyle(MileTheme.emerald)
                }

                Slider(value: $weeklyDistance, in: sliderRange, step: sliderStep)
                    .tint(MileTheme.emerald)

                HStack {
                    Text("\(Int(sliderRange.lowerBound)) \(selectedRegion.defaultUnit.shortLabel)")
                    Spacer()
                    Text("\(Int(sliderRange.upperBound)) \(selectedRegion.defaultUnit.shortLabel)")
                }
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(MileTheme.muted)
            }
            .mileCard(padding: 16)

            // Quick Trust Reassurance Strip
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(MileTheme.emerald)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("100% Offline • Zero Account Needed", "100% 本地离线 • 无需注册登录", "100% 本機離線 • 免註冊帳號"))
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(MileTheme.ink)
                    Text(L10n.t(
                        "Auto-log drives hands-free, swipe right for business, and export audit-ready tax PDFs anytime.",
                        "后台无感记录行程，右滑归为商务抵税，报税季一键导出审计级 PDF。",
                        "背景自動記錄行車紀錄，右滑歸類商務抵稅，報稅季一鍵匯出審計級 PDF。"
                    ))
                    .font(.caption2)
                    .foregroundStyle(MileTheme.muted)
                }
            }
            .mileCard(padding: 14)
        }
    }

    private func finishOnboarding(openPaywall: Bool) {
        ledger.settings.applyTaxRegion(selectedRegion)
        FunnelMetrics.record(.onboardingCompleted)
        onComplete(openPaywall, openPaywall ? formattedEstimatedDeduction : nil)
    }
}
