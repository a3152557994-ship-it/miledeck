import PDFKit
import SwiftUI

struct ReportsView: View {
    @EnvironmentObject private var ledger: MileageStore
    @EnvironmentObject private var store: StoreManager
    @Environment(\.horizontalSizeClass) private var sizeClass

    @Binding var showPaywall: Bool

    @State private var selectedMonth: Int? = nil
    @State private var showFullPDFSheet: Bool = false
    @State private var shareFileURL: URL? = nil
    @State private var showShareSheet: Bool = false
    @State private var exportStatusBanner: String? = nil

    private var stats: [MonthlyDeductionStat] {
        ledger.monthlyStats(for: ledger.settings.taxYear)
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
                            title: L10n.t("2026 DEDUCTION", "2026 抵税总额"),
                            value: IRSRateEngine.formatMoney(ledger.ytdTaxDeduction, symbol: ledger.settings.currencySymbol),
                            sub: L10n.t("\(ledger.deductibleDrives.count) IRS trips", "\(ledger.deductibleDrives.count) 趟可抵扣"),
                            valueColor: MileTheme.emerald
                        )
                        metricCard(
                            title: L10n.t("DEDUCTIBLE DIST", "累计抵税里程"),
                            value: IRSRateEngine.formatDistance(ledger.ytdDeductibleMiles, unit: ledger.settings.distanceUnit),
                            sub: L10n.t("H1 72.5¢ • H2 76¢", "分段费率自动计算"),
                            valueColor: MileTheme.ink
                        )
                    }

                    // Monthly Bar Chart Card
                    monthlyBreakdownCard

                    // Live PDFKit IRS Schedule C Preview Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t("IRS Schedule C PDF Logbook", "IRS Schedule C 报税 PDF 总账"))
                                    .font(.headline.weight(.heavy))
                                    .foregroundStyle(MileTheme.ink)
                                Text(L10n.t("Live vector PDFKit preview • Audit-ready Pub 463 format", "实时矢量 PDF 预览 • 符合税务审计留档格式"))
                                    .font(.caption)
                                    .foregroundStyle(MileTheme.muted)
                            }
                            Spacer()
                            Button {
                                showFullPDFSheet = true
                            } label: {
                                Label(L10n.t("Expand", "全屏"), systemImage: "arrow.up.left.and.arrow.down.right")
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

                        // 1-Tap Share PDF + Share IRS CSV Buttons
                        HStack(spacing: 10) {
                            Button {
                                exportPDF()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.richtext.fill")
                                    Text(L10n.t("Share IRS PDF", "导出报税 PDF"))
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
                                    Image(systemName: "tablecells.fill")
                                    Text(L10n.t("Share CSV", "导出 CSV"))
                                        .font(.subheadline.weight(.bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(MileTheme.asphalt)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            .navigationTitle(L10n.t("Tax Reports", "报税报告"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showFullPDFSheet) {
                NavigationStack {
                    PDFKitRepresentedView(data: pdfData)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle(L10n.t("IRS Logbook PDF", "报税 PDF 预览"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L10n.t("Done", "完成")) { showFullPDFSheet = false }
                            }
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    showFullPDFSheet = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                        exportPDF()
                                    }
                                } label: {
                                    Label(L10n.t("Share", "分享"), systemImage: "square.and.arrow.up")
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

    private var monthlyBreakdownCard: some View {
        let maxDed = max(10.0, stats.map(\.deduction).max() ?? 10.0)
        let activeStat = selectedMonth.flatMap { m in stats.first(where: { $0.month == m }) }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Month-by-Month 2026 Breakdown", "2026 月度抵税分布"))
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(MileTheme.ink)
                    Text(L10n.t("Tap any month to inspect miles & IRS period rate", "点按任意月份查看里程与分段费率"))
                        .font(.caption2)
                        .foregroundStyle(MileTheme.muted)
                }
                Spacer()
                HStack(spacing: 8) {
                    legendDot(color: MileTheme.asphalt, text: "72.5¢")
                    legendDot(color: MileTheme.emerald, text: "76¢")
                }
            }

            if let st = activeStat {
                HStack {
                    Text("\(st.shortName) 2026 (\(st.isH2 ? "H2 $0.76/mi" : "H1 $0.725/mi"))")
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
                    Button {
                        selectedMonth = (selectedMonth == st.month) ? nil : st.month
                    } label: {
                        VStack(spacing: 5) {
                            Spacer(minLength: 0)
                            if st.deduction > 0 {
                                Text("$\(Int(st.deduction.rounded()))")
                                    .font(.system(size: 8.5, weight: .bold).monospacedDigit())
                                    .foregroundStyle(st.isH2 ? MileTheme.emerald : MileTheme.asphalt)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    st.deduction == 0
                                        ? MileTheme.border.opacity(0.65)
                                        : (st.isH2 ? MileTheme.emerald : MileTheme.asphalt)
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
        if !store.canClassifyOrExportFree {
            showPaywall = true
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MileDeck_\(ledger.settings.taxYear)_IRS_Logbook.pdf")
        do {
            try pdfData.write(to: url, options: .atomic)
            store.recordClassifiedOrExportedDrive()
            shareFileURL = url
            showShareSheet = true
            exportStatusBanner = L10n.t("IRS Schedule C PDF ready to share.", "报税 PDF 已生成，可直接分享保存。")
        } catch {
            exportStatusBanner = error.localizedDescription
        }
    }

    private func exportCSV() {
        if !store.canClassifyOrExportFree {
            showPaywall = true
            return
        }
        let csv = ledger.exportIRSCSV()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MileDeck_\(ledger.settings.taxYear)_IRS_Mileage.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            store.recordClassifiedOrExportedDrive()
            shareFileURL = url
            showShareSheet = true
            exportStatusBanner = L10n.t("IRS CSV spreadsheet ready to share.", "IRS 报税 CSV 表格已生成。")
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
