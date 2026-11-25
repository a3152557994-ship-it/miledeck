import PDFKit
import SwiftUI

struct ReportsView: View {
    @EnvironmentObject private var ledger: MileageStore
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var reviewManager: ReviewPromptManager
    @Environment(\.horizontalSizeClass) private var sizeClass

    @Binding var showPaywall: Bool
    var onRequestPaywall: ((_ triggerMessage: String?, _ lockedDeductionText: String?) -> Void)? = nil

    @State private var selectedMonth: Int? = nil
    @State private var showFullPDFSheet: Bool = false
    @State private var shareFileURL: URL? = nil
    @State private var showShareSheet: Bool = false
    @State private var exportStatusBanner: String? = nil

    private var stats: [MonthlyDeductionStat] {
        ledger.monthlyStats(for: ledger.settings.taxYear)
    }

    private var region: TaxRegionPreset {
        ledger.settings.taxRegion
    }

    private var pdfData: Data {
        IRSLogbookPDFRenderer.renderPDFData(
            drives: ledger.drives,
            vehicles: ledger.vehicles,
            settings: ledger.settings,
            includeBrandingFooter: !store.isPro
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Summary Strip
                    HStack(spacing: 10) {
                        metricCard(
                            title: L10n.t("\(ledger.settings.taxYear) DEDUCTION", "\(ledger.settings.taxYear) 抵税总额", "\(ledger.settings.taxYear) 抵稅金額"),
                            value: IRSRateEngine.formatMoney(ledger.ytdTaxDeduction, symbol: ledger.settings.currencySymbol),
                            sub: L10n.t("\(ledger.deductibleDrives.count) \(region.authorityShort) trips", "\(ledger.deductibleDrives.count) 趟可抵扣", "\(ledger.deductibleDrives.count) 趟可抵稅"),
                            valueColor: MileTheme.emerald
                        )
                        metricCard(
                            title: L10n.t("DEDUCTIBLE DIST", "累计抵税里程", "累計抵稅里程"),
                            value: IRSRateEngine.formatDistance(ledger.ytdDeductibleMiles, unit: ledger.settings.distanceUnit),
                            sub: region.rateSummaryBadge,
                            valueColor: MileTheme.ink
                        )
                    }

                    // Monthly Bar Chart Card
                    monthlyBreakdownCard

                    // Live PDFKit Tax Logbook Preview Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t("\(region.authorityShort) Tax PDF Logbook", "\(region.authorityShort) 报税 PDF 总账", "\(region.authorityShort) 里程報稅 PDF 總帳"))
                                    .font(.headline.weight(.heavy))
                                    .foregroundStyle(MileTheme.ink)
                                Text(L10n.t(
                                    "Live vector PDFKit preview • \(region.pdfComplianceLabel)",
                                    "实时矢量 PDF 预览 • 符合税务审计留档格式",
                                    "即時向量 PDF 預覽 • 符合稅務審計留檔格式"
                                ))
                                .font(.caption)
                                .foregroundStyle(MileTheme.muted)
                            }
                            Spacer()
                            Button {
                                showFullPDFSheet = true
                                reviewManager.recordFirstReportPreview()
                            } label: {
                                Label(L10n.t("Expand", "全屏", "全螢幕"), systemImage: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(MileTheme.roadWhite)
                                    .foregroundStyle(MileTheme.ink)
                                    .clipShape(Capsule())
                            }
                        }

                        PDFKitRepresentedView(data: pdfData)
                            .frame(height: sizeClass == .regular ? 380 : 255)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(MileTheme.border, lineWidth: 1)
                            )

                        // 1-Tap Share PDF + Share CSV Buttons (Pro-gated to protect audit export value)
                        HStack(spacing: 10) {
                            Button {
                                exportPDF()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: store.canExportTaxReport ? "doc.richtext.fill" : "lock.fill")
                                    Text(L10n.t("Share \(region.authorityShort) PDF", "导出报税 PDF", "匯出報稅 PDF"))
                                        .font(.subheadline.weight(.bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(MileTheme.emerald)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            Button {
                                exportCSV()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: store.canExportTaxReport ? "tablecells.fill" : "lock.fill")
                                    Text(L10n.t("Share CSV", "导出 CSV", "匯出 CSV"))
                                        .font(.subheadline.weight(.bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(MileTheme.asphalt)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }

                        if !store.canExportTaxReport {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(MileTheme.amber)
                                Text(L10n.t(
                                    "Preview is always free. Unlock Pro to export your \(lockedDeductionDisplay) audit-ready PDF & CSV.",
                                    "实时预览永久免费，解锁 Pro 即可一键导出 \(lockedDeductionDisplay) 审计级 PDF 与 CSV。",
                                    "即時預覽永久免費，解鎖 Pro 即可一鍵匯出 \(lockedDeductionDisplay) 審計級 PDF 與 CSV。"
                                ))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(MileTheme.muted)
                            }
                        }

                        if let banner = exportStatusBanner {
                            Text(banner)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MileTheme.emerald)
                        }
                    }
                    .mileCard(padding: 15)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(MileTheme.roadWhite.ignoresSafeArea())
            .navigationTitle(L10n.t("Tax Reports", "报税报告", "里程報稅"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !ledger.deductibleDrives.isEmpty {
                    reviewManager.recordFirstReportPreview()
                }
            }
            .sheet(isPresented: $showFullPDFSheet) {
                NavigationStack {
                    PDFKitRepresentedView(data: pdfData)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle(L10n.t("\(region.authorityShort) Logbook PDF", "报税 PDF 预览", "報稅 PDF 預覽"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L10n.t("Done", "完成", "完成")) { showFullPDFSheet = false }
                            }
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    showFullPDFSheet = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                        exportPDF()
                                    }
                                } label: {
                                    Label(L10n.t("Share", "分享", "分享"), systemImage: store.canExportTaxReport ? "square.and.arrow.up" : "lock.fill")
                                }
                            }
                        }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = shareFileURL {
                    ActivityShareSheet(items: [url])
                }
            }
        }
    }

    private var lockedDeductionDisplay: String {
        if ledger.ytdTaxDeduction > 0 {
            return ledger.formattedYTDDeduction
        }
        if ledger.pendingPotentialDeduction > 0 {
            return IRSRateEngine.formatMoney(ledger.pendingPotentialDeduction, symbol: ledger.settings.currencySymbol)
        }
        return IRSRateEngine.formatMoney(0, symbol: ledger.settings.currencySymbol)
    }

    private func openExportPaywall(formatLabel: String) {
        let amount = lockedDeductionDisplay
        let msg = L10n.t(
            "Your \(amount) \(region.authorityShort) \(formatLabel) logbook is ready. Unlock Pro (or start a 7-day free trial) to export and share.",
            "您的 \(amount) \(region.authorityShort) 报税 \(formatLabel) 已准备就绪。解锁 Pro（或开启 7 天免费试用）即可立即导出分享。",
            "您的 \(amount) \(region.authorityShort) 里程報稅 \(formatLabel) 已準備就緒。解鎖 Pro（或開啟 7 天免費試用）即可立即匯出分享。"
        )
        if let onRequestPaywall {
            onRequestPaywall(msg, amount)
        } else {
            showPaywall = true
        }
    }

    private var monthlyBreakdownCard: some View {
        let maxDed = max(10.0, stats.map(\.deduction).max() ?? 10.0)
        let activeStat = selectedMonth.flatMap { m in stats.first(where: { $0.month == m }) }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Month-by-Month \(ledger.settings.taxYear) Breakdown", "\(ledger.settings.taxYear) 月度抵税分布", "\(ledger.settings.taxYear) 月度抵稅分佈"))
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(MileTheme.ink)
                    Text(L10n.t("Tap any month to inspect miles & tax rate", "点按任意月份查看里程与抵税额", "點按任意月份檢視里程與抵稅金額"))
                        .font(.caption2)
                        .foregroundStyle(MileTheme.muted)
                }
                Spacer()
                if region == .usIRS2026 {
                    HStack(spacing: 8) {
                        legendDot(color: MileTheme.asphalt, text: "72.5¢")
                        legendDot(color: MileTheme.emerald, text: "76¢")
                    }
                } else {
                    Text(region.shortName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MileTheme.emerald)
                }
            }

            if let st = activeStat {
                HStack {
                    let rateSuffix = region == .usIRS2026
                        ? (st.isH2 ? " (H2 $0.76/mi)" : " (H1 $0.725/mi)")
                        : " (\(region.shortName))"
                    Text("\(st.shortName) \(ledger.settings.taxYear)\(rateSuffix)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MileTheme.ink)
                    Spacer()
                    Text("\(IRSRateEngine.formatDistance(st.businessMiles, unit: ledger.settings.distanceUnit))  •  \(IRSRateEngine.formatMoney(st.deduction, symbol: ledger.settings.currencySymbol))")
                        .font(.caption.weight(.heavy).monospacedDigit())
                        .foregroundStyle(MileTheme.emerald)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(MileTheme.emeraldSoft)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(stats) { st in
                    let barRatio = st.deduction > 0 ? max(0.10, st.deduction / maxDed) : 0.04
                    let isSelected = selectedMonth == st.month
                    let useEmerald = region == .usIRS2026 ? st.isH2 : true
                    Button {
                        selectedMonth = (selectedMonth == st.month) ? nil : st.month
                    } label: {
                        VStack(spacing: 5) {
                            Spacer(minLength: 0)
                            if st.deduction > 0 {
                                Text("\(ledger.settings.currencySymbol)\(Int(st.deduction.rounded()))")
                                    .font(.system(size: 8.5, weight: .bold).monospacedDigit())
                                    .foregroundStyle(useEmerald ? MileTheme.emerald : MileTheme.asphalt)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    st.deduction == 0
                                        ? MileTheme.border.opacity(0.65)
                                        : (useEmerald ? MileTheme.emerald : MileTheme.asphalt)
                                )
                                .frame(height: 92 * barRatio)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(isSelected ? MileTheme.amber : Color.clear, lineWidth: 2)
                                )
                            Text(st.shortName)
                                .font(.system(size: 9, weight: isSelected ? .heavy : .semibold))
                                .foregroundStyle(isSelected ? MileTheme.ink : MileTheme.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 126)
        }
        .mileCard(padding: 15)
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption2.weight(.bold).monospacedDigit()).foregroundStyle(MileTheme.muted)
        }
    }

    private func metricCard(title: String, value: String, sub: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(MileTheme.muted)
            Text(value)
                .font(.title2.weight(.heavy).monospacedDigit())
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text(sub)
                .font(.caption2.weight(.medium))
                .foregroundStyle(MileTheme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mileCard(padding: 14)
    }

    private func exportPDF() {
        guard store.canExportTaxReport else {
            openExportPaywall(formatLabel: "PDF")
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MileDeck_\(ledger.settings.taxYear)_\(region.fileToken)_Logbook.pdf")
        do {
            try pdfData.write(to: url, options: .atomic)
            shareFileURL = url
            showShareSheet = true
            exportStatusBanner = L10n.t("\(region.authorityShort) PDF logbook ready to share.", "报税 PDF 已生成，可直接分享保存。", "里程報稅 PDF 已產生，可直接分享儲存。")
        } catch {
            exportStatusBanner = error.localizedDescription
        }
    }

    private func exportCSV() {
        guard store.canExportTaxReport else {
            openExportPaywall(formatLabel: "CSV")
            return
        }
        let csv = ledger.exportIRSCSV()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MileDeck_\(ledger.settings.taxYear)_\(region.fileToken)_Mileage.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            shareFileURL = url
            showShareSheet = true
            exportStatusBanner = L10n.t("\(region.authorityShort) CSV spreadsheet ready to share.", "报税 CSV 表格已生成。", "里程報稅 CSV 表格已產生。")
        } catch {
            exportStatusBanner = error.localizedDescription
        }
    }
}

struct PDFKitRepresentedView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1)
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(data: data)
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
