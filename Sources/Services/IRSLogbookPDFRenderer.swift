import Foundation
import UIKit

enum IRSLogbookPDFRenderer {
    static func renderPDFData(
        drives: [DriveRecord],
        vehicles: [Vehicle],
        settings: DriverSettings,
        includeBrandingFooter: Bool
    ) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let margin: CGFloat = 36
        let contentW = pageRect.width - margin * 2

        let asphalt = UIColor(red: 0.067, green: 0.094, blue: 0.153, alpha: 1)
        let emerald = UIColor(red: 0.020, green: 0.588, blue: 0.412, alpha: 1)
        let amber = UIColor(red: 0.851, green: 0.467, blue: 0.024, alpha: 1)
        let muted = UIColor(red: 0.39, green: 0.45, blue: 0.54, alpha: 1)
        let zebra = UIColor(red: 0.965, green: 0.975, blue: 0.985, alpha: 1)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "MileDeck \(settings.taxYear) IRS Schedule C Mileage Logbook",
            kCGPDFContextCreator as String: "MileDeck",
        ]

        let deductible = drives.filter { $0.classification.isDeductible }.sorted { $0.startDate < $1.startDate }
        let totalMiles = deductible.reduce(0.0) { $0 + $1.distanceMiles }
        let totalDed = IRSRateEngine.roundCents(deductible.reduce(0.0) { $0 + IRSRateEngine.deduction(for: $1, settings: settings) })

        let h1Drives = deductible.filter { $0.classification == .business && IRSRateEngine.period(for: $0.startDate) == .h1_2026 }
        let h2Drives = deductible.filter { $0.classification == .business && IRSRateEngine.period(for: $0.startDate) == .h2_2026 }
        let h1Miles = h1Drives.reduce(0.0) { $0 + $1.distanceMiles }
        let h1Ded = IRSRateEngine.roundCents(h1Drives.reduce(0.0) { $0 + IRSRateEngine.deduction(for: $1, settings: settings) })
        let h2Miles = h2Drives.reduce(0.0) { $0 + $1.distanceMiles }
        let h2Ded = IRSRateEngine.roundCents(h2Drives.reduce(0.0) { $0 + IRSRateEngine.deduction(for: $1, settings: settings) })

        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.dateFormat = "MMM d, yyyy"

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        return renderer.pdfData { ctx in
            var pageNumber = 1

            func beginNewPage() {
                ctx.beginPage()
                UIColor.white.setFill()
                ctx.fill(pageRect)
            }

            func drawFooter(page: Int) {
                let fy = pageRect.height - 28
                let line = UIBezierPath()
                line.move(to: CGPoint(x: margin, y: fy - 6))
                line.addLine(to: CGPoint(x: pageRect.width - margin, y: fy - 6))
                UIColor(white: 0.87, alpha: 1).setStroke()
                line.lineWidth = 0.6
                line.stroke()

                let left = includeBrandingFooter
                    ? L10n.t("Generated 100% locally with MileDeck • IRS Pub 463 Audit-Ready Log", "由 MileDeck 本地离线生成 • IRS 报税留档日志")
                    : "\(settings.driverName) • \(settings.taxYear) IRS Schedule C Mileage Logbook"
                drawText(left, in: CGRect(x: margin, y: fy, width: contentW * 0.76, height: 14), font: .systemFont(ofSize: 8.2), color: muted)
                drawText(L10n.t("Page \(page)", "第 \(page) 页"), in: CGRect(x: margin + contentW * 0.76, y: fy, width: contentW * 0.24, height: 14), font: .systemFont(ofSize: 8.2), color: muted, alignment: .right)
            }

            func drawTableHeader(at topY: CGFloat) -> CGFloat {
                let h: CGFloat = 24
                let rect = CGRect(x: margin, y: topY, width: contentW, height: h)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 5)
                asphalt.setFill()
                path.fill()

                let f = UIFont.boldSystemFont(ofSize: 8.2)
                drawText(L10n.t("DATE", "日期"), in: CGRect(x: margin + 8, y: topY + 6, width: 62, height: 14), font: f, color: .white)
                drawText(L10n.t("ROUTE (START → END)", "行程路线"), in: CGRect(x: margin + 74, y: topY + 6, width: 186, height: 14), font: f, color: .white)
                drawText(L10n.t("PURPOSE", "用途"), in: CGRect(x: margin + 264, y: topY + 6, width: 88, height: 14), font: f, color: .white)
                drawText(L10n.t("DIST", "里程"), in: CGRect(x: margin + 356, y: topY + 6, width: 54, height: 14), font: f, color: .white, alignment: .right)
                drawText(L10n.t("RATE", "费率"), in: CGRect(x: margin + 414, y: topY + 6, width: 56, height: 14), font: f, color: .white, alignment: .right)
                drawText(L10n.t("DEDUCTION", "抵税额"), in: CGRect(x: margin + 474, y: topY + 6, width: contentW - 482, height: 14), font: f, color: .white, alignment: .right)
                return topY + h + 4
            }

            beginNewPage()

            // Header Banner
            let headerH: CGFloat = 104
            asphalt.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: pageRect.width, height: headerH))
            emerald.setFill()
            ctx.fill(CGRect(x: 0, y: headerH - 4, width: pageRect.width, height: 4))

            drawText(
                L10n.t("IRS SCHEDULE C MILEAGE LOGBOOK", "IRS SCHEDULE C 报税里程总账"),
                in: CGRect(x: margin, y: 20, width: 340, height: 22),
                font: .systemFont(ofSize: 16, weight: .heavy),
                color: .white
            )
            drawText(
                L10n.t("Taxpayer: \(settings.driverName)  •  Tax Year: \(settings.taxYear)  •  IRS Pub 463 Compliant", "纳税人：\(settings.driverName)  •  税年：\(settings.taxYear)"),
                in: CGRect(x: margin, y: 45, width: 350, height: 16),
                font: .systemFont(ofSize: 9.2),
                color: UIColor(white: 0.82, alpha: 1)
            )
            drawText(
                L10n.t("2026 Split-Period Standard Rates: Jan–Jun $0.725/mi  |  Jul–Dec $0.760/mi", "2026 分段标准费率：1–6月 $0.725/mi  |  7–12月 $0.760/mi"),
                in: CGRect(x: margin, y: 65, width: 360, height: 16),
                font: .boldSystemFont(ofSize: 8.8),
                color: UIColor(red: 0.43, green: 0.91, blue: 0.72, alpha: 1)
            )

            // Right Total Callout in Header
            drawText(
                L10n.t("TOTAL DEDUCTION", "累计抵税额"),
                in: CGRect(x: pageRect.width - margin - 180, y: 20, width: 180, height: 13),
                font: .boldSystemFont(ofSize: 8.2),
                color: UIColor(red: 0.43, green: 0.91, blue: 0.72, alpha: 1),
                alignment: .right
            )
            drawText(
                IRSRateEngine.formatMoney(totalDed, symbol: settings.currencySymbol),
                in: CGRect(x: pageRect.width - margin - 180, y: 35, width: 180, height: 30),
                font: .monospacedDigitSystemFont(ofSize: 24, weight: .heavy),
                color: .white,
                alignment: .right
            )
            drawText(
                "\(IRSRateEngine.formatDistance(totalMiles, unit: settings.distanceUnit)) • \(deductible.count) \(L10n.t("drives", "趟"))",
                in: CGRect(x: pageRect.width - margin - 180, y: 68, width: 180, height: 16),
                font: .monospacedDigitSystemFont(ofSize: 9.2, weight: .medium),
                color: UIColor(white: 0.82, alpha: 1),
                alignment: .right
            )

            var y: CGFloat = headerH + 16

            // Split-Period Summary Strip (2 boxes)
            let boxGap: CGFloat = 12
            let halfW = (contentW - boxGap) / 2

            func drawPeriodBox(x: CGFloat, title: String, rateStr: String, miles: Double, ded: Double, badgeColor: UIColor) {
                let rect = CGRect(x: x, y: y, width: halfW, height: 54)
                let p = UIBezierPath(roundedRect: rect, cornerRadius: 7)
                UIColor(red: 0.965, green: 0.972, blue: 0.980, alpha: 1).setFill()
                p.fill()
                UIColor(white: 0.86, alpha: 1).setStroke()
                p.lineWidth = 0.8
                p.stroke()

                drawText(title, in: CGRect(x: x + 10, y: y + 8, width: halfW - 95, height: 14), font: .boldSystemFont(ofSize: 8.5), color: asphalt)
                drawText(rateStr, in: CGRect(x: x + halfW - 84, y: y + 8, width: 74, height: 14), font: .monospacedDigitSystemFont(ofSize: 8.5, weight: .bold), color: badgeColor, alignment: .right)
                drawText(
                    IRSRateEngine.formatMoney(ded, symbol: settings.currencySymbol),
                    in: CGRect(x: x + 10, y: y + 25, width: 110, height: 22),
                    font: .monospacedDigitSystemFont(ofSize: 15, weight: .heavy),
                    color: emerald
                )
                drawText(
                    IRSRateEngine.formatDistance(miles, unit: settings.distanceUnit),
                    in: CGRect(x: x + 124, y: y + 29, width: halfW - 134, height: 16),
                    font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
                    color: muted,
                    alignment: .right
                )
            }

            drawPeriodBox(
                x: margin,
                title: L10n.t("2026 H1 (Jan 1 – Jun 30)", "2026 上半年 (1月–6月)"),
                rateStr: "$0.725/mi",
                miles: h1Miles,
                ded: h1Ded,
                badgeColor: muted
            )
            drawPeriodBox(
                x: margin + halfW + boxGap,
                title: L10n.t("2026 H2 (Jul 1 – Dec 31)", "2026 下半年 (7月–12月)"),
                rateStr: "$0.760/mi",
                miles: h2Miles,
                ded: h2Ded,
                badgeColor: amber
            )
            y += 66

            // Vehicle Odometer Summary (IRS Audit Requirement)
            if !vehicles.isEmpty {
                let vLines = vehicles.map { v in
                    "\(v.displayName) (\(v.licensePlate)) — \(L10n.t("Start Odo", "年初表显")): \(IRSRateEngine.formatOdometer(v.startOdometerMiles, unit: settings.distanceUnit))  →  \(L10n.t("Current Odo", "当前表显")): \(IRSRateEngine.formatOdometer(v.currentOdometerMiles, unit: settings.distanceUnit))"
                }.joined(separator: "\n")
                let vh = max(32, CGFloat(vehicles.count) * 14 + 22)
                let vRect = CGRect(x: margin, y: y, width: contentW, height: vh)
                let vp = UIBezierPath(roundedRect: vRect, cornerRadius: 6)
                UIColor(red: 0.94, green: 0.99, blue: 0.96, alpha: 1).setFill()
                vp.fill()
                emerald.withAlphaComponent(0.35).setStroke()
                vp.lineWidth = 0.8
                vp.stroke()

                drawText(L10n.t("VEHICLES & ODOMETER LOG (IRS PUB 463)", "登记车辆与里程表读数"), in: CGRect(x: margin + 10, y: y + 6, width: contentW - 20, height: 13), font: .boldSystemFont(ofSize: 8.0), color: emerald)
                drawText(vLines, in: CGRect(x: margin + 10, y: y + 20, width: contentW - 20, height: vh - 22), font: .monospacedDigitSystemFont(ofSize: 8.5, weight: .medium), color: asphalt, lineSpacing: 2.0)
                y += vh + 12
            }

            // Trips Table
            y = drawTableHeader(at: y)

            if deductible.isEmpty {
                drawText(
                    L10n.t("No deductible drives classified yet. Swipe right on any trip in Drives to classify as Business.", "暂未有已分类的抵税行程，请在行程页右滑分类。"),
                    in: CGRect(x: margin + 10, y: y + 12, width: contentW - 20, height: 32),
                    font: .systemFont(ofSize: 10),
                    color: muted
                )
            } else {
                for (idx, d) in deductible.enumerated() {
                    let routeText = "\(d.startAddress) → \(d.endAddress)"
                    let routeH = measureHeight(routeText, width: 186, font: .boldSystemFont(ofSize: 8.8))
                    let noteH = d.notes.isEmpty ? 0 : measureHeight(d.notes, width: 186, font: .systemFont(ofSize: 7.8)) + 2
                    let rowH = max(26, routeH + noteH + 10)

                    if y + rowH > pageRect.height - 62 {
                        drawFooter(page: pageNumber)
                        pageNumber += 1
                        beginNewPage()
                        y = 36
                        y = drawTableHeader(at: y)
                    }

                    if idx % 2 == 1 {
                        zebra.setFill()
                        ctx.fill(CGRect(x: margin, y: y, width: contentW, height: rowH))
                    }

                    drawText(df.string(from: d.startDate), in: CGRect(x: margin + 8, y: y + 6, width: 62, height: 16), font: .monospacedDigitSystemFont(ofSize: 8.4, weight: .medium), color: asphalt)
                    drawText(routeText, in: CGRect(x: margin + 74, y: y + 5, width: 186, height: routeH + 2), font: .boldSystemFont(ofSize: 8.8), color: asphalt)
                    if !d.notes.isEmpty {
                        drawText(d.notes, in: CGRect(x: margin + 74, y: y + 5 + routeH + 2, width: 186, height: noteH), font: .systemFont(ofSize: 7.8), color: muted)
                    }
                    drawText("\(d.classification.shortTag)\n\(d.purpose.title)", in: CGRect(x: margin + 264, y: y + 5, width: 88, height: 22), font: .systemFont(ofSize: 8.0), color: muted, lineSpacing: 1.2)
                    drawText(IRSRateEngine.formatDistance(d.distanceMiles, unit: settings.distanceUnit), in: CGRect(x: margin + 356, y: y + 6, width: 54, height: 16), font: .monospacedDigitSystemFont(ofSize: 8.6, weight: .medium), color: asphalt, alignment: .right)
                    drawText(IRSRateEngine.effectiveRateLabel(for: d, settings: settings), in: CGRect(x: margin + 414, y: y + 6, width: 56, height: 16), font: .monospacedDigitSystemFont(ofSize: 8.4, weight: .regular), color: muted, alignment: .right)
                    let ded = IRSRateEngine.deduction(for: d, settings: settings)
                    drawText(IRSRateEngine.formatMoney(ded, symbol: settings.currencySymbol), in: CGRect(x: margin + 474, y: y + 6, width: contentW - 482, height: 16), font: .monospacedDigitSystemFont(ofSize: 9.0, weight: .bold), color: emerald, alignment: .right)

                    let sep = UIBezierPath()
                    sep.move(to: CGPoint(x: margin, y: y + rowH))
                    sep.addLine(to: CGPoint(x: margin + contentW, y: y + rowH))
                    UIColor(white: 0.90, alpha: 1).setStroke()
                    sep.lineWidth = 0.5
                    sep.stroke()

                    y += rowH
                }
            }

            // Grand Total Row
            y += 10
            if y > pageRect.height - 72 {
                drawFooter(page: pageNumber)
                pageNumber += 1
                beginNewPage()
                y = 40
            }
            let totRect = CGRect(x: margin, y: y, width: contentW, height: 30)
            let tp = UIBezierPath(roundedRect: totRect, cornerRadius: 6)
            asphalt.setFill()
            tp.fill()
            drawText(
                L10n.t("TOTAL DEDUCTIBLE MILEAGE (\(settings.taxYear))", "\(settings.taxYear) 年度可抵扣总计"),
                in: CGRect(x: margin + 12, y: y + 8, width: 290, height: 16),
                font: .boldSystemFont(ofSize: 9.5),
                color: .white
            )
            drawText(
                IRSRateEngine.formatDistance(totalMiles, unit: settings.distanceUnit),
                in: CGRect(x: margin + 320, y: y + 8, width: 90, height: 16),
                font: .monospacedDigitSystemFont(ofSize: 10, weight: .bold),
                color: UIColor(white: 0.88, alpha: 1),
                alignment: .right
            )
            drawText(
                IRSRateEngine.formatMoney(totalDed, symbol: settings.currencySymbol),
                in: CGRect(x: margin + 420, y: y + 7, width: contentW - 432, height: 18),
                font: .monospacedDigitSystemFont(ofSize: 12, weight: .heavy),
                color: UIColor(red: 0.43, green: 0.91, blue: 0.72, alpha: 1),
                alignment: .right
            )

            drawFooter(page: pageNumber)
        }
    }

    private static func measureHeight(_ text: String, width: CGFloat, font: UIFont, lineSpacing: CGFloat = 1.5) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: style],
            context: nil
        )
        return ceil(rect.height)
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left,
        lineSpacing: CGFloat = 1.5
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineSpacing = lineSpacing
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
    }
}
