import SwiftUI

struct DrivesHomeView: View {
    @EnvironmentObject private var ledger: MileageStore
    @EnvironmentObject private var tracker: DriveTrackingService
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var reviewManager: ReviewPromptManager

    @Binding var showSwipeDeck: Bool
    @Binding var editingDrive: DriveEditTarget?
    @Binding var showPaywall: Bool
    var onRequestPaywall: ((_ triggerMessage: String?, _ lockedDeductionText: String?) -> Void)? = nil

    enum LogFilter: String, CaseIterable, Identifiable {
        case all, business, personal, unsorted
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return L10n.t("All", "全部", "全部")
            case .business: return L10n.t("Business", "商务", "商務")
            case .personal: return L10n.t("Personal", "私人", "私人")
            case .unsorted: return L10n.t("Unsorted", "待分类", "待分類")
            }
        }
    }

    @State private var selectedFilter: LogFilter = .all

    private var filteredDrives: [DriveRecord] {
        switch selectedFilter {
        case .all: return ledger.drives
        case .business: return ledger.drives.filter { $0.classification == .business || $0.classification == .medical || $0.classification == .charity }
        case .personal: return ledger.drives.filter { $0.classification == .personal }
        case .unsorted: return ledger.unclassifiedDrives
        }
    }

    private var region: TaxRegionPreset {
        ledger.settings.taxRegion
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroYTDCard
                    liveTrackerCard

                    if !ledger.unclassifiedDrives.isEmpty {
                        unclassifiedDeckPreviewCard
                    }

                    tripLogSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(MileTheme.roadWhite.ignoresSafeArea())
            .navigationTitle("MileDeck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if let onRequestPaywall {
                            onRequestPaywall(nil, nil)
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: store.isPro ? "checkmark.seal.fill" : "sparkles")
                                .font(.caption.weight(.bold))
                            Text(
                                store.isPro
                                    ? L10n.t("Pro Active", "专业版已解锁", "專業版已解鎖")
                                    : L10n.t(
                                        "Pro · \(store.displayPrice(for: MileDeckProductID.lifetime))",
                                        "买断 \(store.displayPrice(for: MileDeckProductID.lifetime))",
                                        "買斷 \(store.displayPrice(for: MileDeckProductID.lifetime))"
                                    )
                            )
                            .font(.caption.weight(.heavy).monospacedDigit())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(store.isPro ? MileTheme.emeraldSoft : MileTheme.asphalt)
                        .foregroundStyle(store.isPro ? MileTheme.emerald : Color(red: 0.43, green: 0.94, blue: 0.74))
                        .clipShape(Capsule())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingDrive = DriveEditTarget(drive: nil)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(MileTheme.emerald)
                    }
                    .accessibilityLabel(L10n.t("Log Manual Drive", "手动记里程", "手動記里程"))
                }
            }
        }
    }

    // MARK: - Hero YTD Asphalt Card
    private var heroYTDCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "road.lanes")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MileTheme.emeraldBright)
                    Text(region.heroTitle)
                        .font(.caption.weight(.heavy))
                        .tracking(0.6)
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                Spacer()
                Text(region.rateSummaryBadge)
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(MileTheme.emerald.opacity(0.26))
                    .foregroundStyle(Color(red: 0.43, green: 0.94, blue: 0.74))
                    .clipShape(Capsule())
            }

            HStack(alignment: .firstTextBaseline) {
                Text(IRSRateEngine.formatMoney(ledger.ytdTaxDeduction, symbol: ledger.settings.currencySymbol))
                    .font(.system(size: 40, weight: .heavy).monospacedDigit())
                    .foregroundStyle(.white)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(IRSRateEngine.formatDistance(ledger.ytdDeductibleMiles, unit: ledger.settings.distanceUnit))
                        .font(.headline.weight(.heavy).monospacedDigit())
                        .foregroundStyle(Color(red: 0.43, green: 0.94, blue: 0.74))
                    Text(L10n.t(
                        "\(ledger.deductibleDrives.count) deductible trips",
                        "\(ledger.deductibleDrives.count) 趟已分类抵税",
                        "\(ledger.deductibleDrives.count) 趟已分類抵稅"
                    ))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.68))
                }
            }

            // Region-Aware Split / Tier Telemetry Bar
            if region == .usIRS2026 {
                HStack(spacing: 10) {
                    telemetryPill(
                        label: L10n.t("Jan–Jun ($0.725/mi)", "1–6月 ($0.725/mi)", "1–6月 ($0.725/mi)"),
                        labelColor: Color.white.opacity(0.60),
                        amount: IRSRateEngine.formatMoney(ledger.h1BusinessDeduction, symbol: ledger.settings.currencySymbol),
                        distance: IRSRateEngine.formatDistance(ledger.h1BusinessMiles, unit: ledger.settings.distanceUnit),
                        highlighted: false
                    )
                    telemetryPill(
                        label: L10n.t("Jul–Dec ($0.760/mi)", "7–12月 ($0.760/mi)", "7–12月 ($0.760/mi)"),
                        labelColor: Color(red: 0.98, green: 0.78, blue: 0.42),
                        amount: IRSRateEngine.formatMoney(ledger.h2BusinessDeduction, symbol: ledger.settings.currencySymbol),
                        distance: IRSRateEngine.formatDistance(ledger.h2BusinessMiles, unit: ledger.settings.distanceUnit),
                        highlighted: true
                    )
                }
            } else if region == .ukHMRC {
                let tier1Miles = min(ledger.ytdDeductibleMiles, IRSRateEngine.ukHMRCThresholdMiles)
                let tier2Miles = max(0, ledger.ytdDeductibleMiles - IRSRateEngine.ukHMRCThresholdMiles)
                HStack(spacing: 10) {
                    telemetryPill(
                        label: L10n.t("First 10k mi (45p)", "前 10k 英里 (45p)", "前 10k 英里 (45p)"),
                        labelColor: Color(red: 0.98, green: 0.78, blue: 0.42),
                        amount: IRSRateEngine.formatMoney(IRSRateEngine.roundCents(tier1Miles * IRSRateEngine.ukHMRCTier1), symbol: "£"),
                        distance: IRSRateEngine.formatDistance(tier1Miles, unit: .miles),
                        highlighted: true
                    )
                    telemetryPill(
                        label: L10n.t("Over 10k mi (25p)", "超出 10k (25p)", "超出 10k (25p)"),
                        labelColor: Color.white.opacity(0.60),
                        amount: IRSRateEngine.formatMoney(IRSRateEngine.roundCents(tier2Miles * IRSRateEngine.ukHMRCTier2), symbol: "£"),
                        distance: IRSRateEngine.formatDistance(tier2Miles, unit: .miles),
                        highlighted: false
                    )
                }
            } else if region == .caCRA {
                let totalKm = ledger.ytdDeductibleMiles * DistanceUnit.kmPerMile
                let tier1Km = min(totalKm, IRSRateEngine.caCRAThresholdKm)
                let tier2Km = max(0, totalKm - IRSRateEngine.caCRAThresholdKm)
                HStack(spacing: 10) {
                    telemetryPill(
                        label: L10n.t("First 5k km (72¢)", "前 5k 公里 (72¢)", "前 5k 公里 (72¢)"),
                        labelColor: Color(red: 0.98, green: 0.78, blue: 0.42),
                        amount: IRSRateEngine.formatMoney(IRSRateEngine.roundCents(tier1Km * IRSRateEngine.caCRATier1PerKm), symbol: "CA$"),
                        distance: String(format: "%.1f km", tier1Km),
                        highlighted: true
                    )
                    telemetryPill(
                        label: L10n.t("Over 5k km (66¢)", "超出 5k (66¢)", "超出 5k (66¢)"),
                        labelColor: Color.white.opacity(0.60),
                        amount: IRSRateEngine.formatMoney(IRSRateEngine.roundCents(tier2Km * IRSRateEngine.caCRATier2PerKm), symbol: "CA$"),
                        distance: String(format: "%.1f km", tier2Km),
                        highlighted: false
                    )
                }
            } else {
                HStack(spacing: 10) {
                    telemetryPill(
                        label: "\(region.flagEmoji) \(region.shortName)",
                        labelColor: Color(red: 0.98, green: 0.78, blue: 0.42),
                        amount: IRSRateEngine.formatMoney(ledger.ytdTaxDeduction, symbol: ledger.settings.currencySymbol),
                        distance: IRSRateEngine.formatDistance(ledger.ytdDeductibleMiles, unit: ledger.settings.distanceUnit),
                        highlighted: true
                    )
                    telemetryPill(
                        label: L10n.t("Pending Unsorted", "待滑卡潜在抵税", "待滑卡潛在抵稅"),
                        labelColor: Color.white.opacity(0.60),
                        amount: "+\(IRSRateEngine.formatMoney(ledger.pendingPotentialDeduction, symbol: ledger.settings.currencySymbol))",
                        distance: "\(ledger.unclassifiedDrives.count) \(L10n.t("trips", "趟", "趟"))",
                        highlighted: false
                    )
                }
            }
        }
        .padding(18)
        .background(MileTheme.asphalt)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: MileTheme.asphalt.opacity(0.16), radius: 12, y: 6)
    }

    private func telemetryPill(label: String, labelColor: Color, amount: String, distance: String, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(labelColor)
            HStack(spacing: 6) {
                Text(amount)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(distance)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.65))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(highlighted ? MileTheme.emerald.opacity(0.18) : Color.white.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(highlighted ? MileTheme.emerald.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Live GPS Drive Tracker Card
    private var liveTrackerCard: some View {
        VStack(spacing: 12) {
            if tracker.isRecording {
                let estVal = IRSRateEngine.roundCents(tracker.liveDistanceMiles * IRSRateEngine.liveBusinessRatePerMile(settings: ledger.settings))
                HStack(spacing: 12) {
                    Circle()
                        .fill(MileTheme.amber)
                        .frame(width: 11, height: 11)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("LIVE DRIVE RECORDING", "实时行车记录中", "即時行車紀錄中"))
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(MileTheme.amber)
                        Text("\(tracker.formattedElapsed())  •  \(IRSRateEngine.formatDistance(tracker.liveDistanceMiles, unit: ledger.settings.distanceUnit))  •  +\(IRSRateEngine.formatMoney(estVal, symbol: ledger.settings.currencySymbol))")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(MileTheme.ink)
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    Button {
                        tracker.addSimulatedDistance(miles: 2.4)
                    } label: {
                        Label(L10n.t("+2.4 mi Test", "+2.4 英里实测", "+2.4 英里實測"), systemImage: "location.north.line.fill")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(MileTheme.roadWhite)
                            .foregroundStyle(MileTheme.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    Button {
                        if let logged = tracker.stopAndCreateDrive(vehicleId: ledger.defaultVehicle?.id) {
                            ledger.addDrive(logged)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.circle.fill")
                            Text(L10n.t("Stop & Log Drive", "结束并保存行程", "結束並儲存紀錄"))
                                .font(.subheadline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(MileTheme.dangerRed)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Button {
                        tracker.startLiveDrive()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "location.circle.fill")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(L10n.t("Start Live Drive", "开始实时记里程", "開始即時記錄里程"))
                                    .font(.subheadline.weight(.bold))
                                Text(
                                    ledger.settings.autoDriveEnabled
                                        ? L10n.t("Auto-Detect ON • Offline GPS", "自动识车已开启 • 离线 GPS", "自動偵測已開啟 • 離線 GPS")
                                        : L10n.t("Manual 1-Tap GPS Tracker", "一键 GPS 离线记录", "一鍵 GPS 離線記錄")
                                )
                                .font(.caption2)
                                .foregroundStyle(Color.white.opacity(0.85))
                            }
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.subheadline.weight(.bold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(MileTheme.emerald)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        editingDrive = DriveEditTarget(drive: nil)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "square.and.pencil")
                                .font(.headline)
                            Text(L10n.t("Manual", "手录", "手錄"))
                                .font(.caption2.weight(.bold))
                        }
                        .frame(width: 68, height: 56)
                        .background(MileTheme.card)
                        .foregroundStyle(MileTheme.ink)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(MileTheme.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if let banner = tracker.statusBanner, !banner.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(MileTheme.amber)
                        Text(banner)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MileTheme.muted)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(MileTheme.amberSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
        .mileCard(padding: 12)
        .task {
            await tracker.backfillUnresolvedAddresses(in: ledger)
        }
    }

    // MARK: - Unclassified Swipe Deck Spotlight Card
    private var unclassifiedDeckPreviewCard: some View {
        let count = ledger.unclassifiedDrives.count
        let top = ledger.unclassifiedDrives[0]
        let pot = IRSRateEngine.deduction(
            for: top,
            settings: ledger.settings,
            includePotentialForUnclassified: true,
            priorDeductibleMilesInYear: ledger.ytdDeductibleMiles
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack.badge.play.fill")
                        .foregroundStyle(MileTheme.amber)
                    Text(L10n.t("\(count) Drives Ready to Swipe", "\(count) 趟行程待左滑/右滑分类", "\(count) 趟行車紀錄待滑卡分類"))
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(MileTheme.ink)
                }
                Spacer()
                Button {
                    showSwipeDeck = true
                } label: {
                    HStack(spacing: 4) {
                        Text(L10n.t("Open Deck", "打开滑卡", "開啟滑卡"))
                            .font(.caption.weight(.bold))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(MileTheme.amberSoft)
                    .foregroundStyle(MileTheme.amber)
                    .clipShape(Capsule())
                }
            }

            // Compact top card preview
            Button {
                showSwipeDeck = true
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(top.startAddress)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(MileTheme.ink)
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(MileTheme.muted)
                        Text(top.endAddress)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(MileTheme.ink)
                            .lineLimit(1)
                    }
                    HStack {
                        Label(top.purpose.title, systemImage: top.purpose.icon)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(MileTheme.muted)
                        Spacer()
                        Text(IRSRateEngine.formatDistance(top.distanceMiles, unit: ledger.settings.distanceUnit))
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(MileTheme.ink)
                        Text("+" + IRSRateEngine.formatMoney(pot, symbol: ledger.settings.currencySymbol))
                            .font(.caption.weight(.heavy).monospacedDigit())
                            .foregroundStyle(MileTheme.emerald)
                    }
                }
                .padding(12)
                .background(MileTheme.roadWhite)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            // Quick inline classify buttons
            HStack(spacing: 10) {
                Button {
                    quickClassify(top, as: .personal)
                } label: {
                    Label(L10n.t("Personal", "私人", "私人"), systemImage: "house.fill")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(MileTheme.personalSoft)
                        .foregroundStyle(MileTheme.personalSlate)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Button {
                    quickClassify(top, as: .business)
                } label: {
                    Label(
                        L10n.t(
                            "Business +\(IRSRateEngine.formatMoney(pot, symbol: ledger.settings.currencySymbol))",
                            "商务 +\(IRSRateEngine.formatMoney(pot, symbol: ledger.settings.currencySymbol))",
                            "商務 +\(IRSRateEngine.formatMoney(pot, symbol: ledger.settings.currencySymbol))"
                        ),
                        systemImage: "briefcase.fill"
                    )
                    .font(.caption.weight(.bold).monospacedDigit())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(MileTheme.emerald)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .mileCard(padding: 14)
    }

    // MARK: - Filterable Trip Log
    private var tripLogSection: some View {
        let dedMap = ledger.deductionsByDriveID
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.t("Trip Log", "行车日志", "行車紀錄"))
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(MileTheme.ink)
                Spacer()
                if !store.isPro {
                    Text(L10n.t("\(store.remainingFreeDrivesThisMonth)/20 free/mo", "本月剩余 \(store.remainingFreeDrivesThisMonth)/20 免费", "本月剩餘 \(store.remainingFreeDrivesThisMonth)/20 免費"))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(MileTheme.muted)
                }
            }

            // Filter Pills
            HStack(spacing: 8) {
                ForEach(LogFilter.allCases) { f in
                    let active = selectedFilter == f
                    Button {
                        selectedFilter = f
                    } label: {
                        Text(f.title)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(active ? MileTheme.asphalt : MileTheme.card)
                            .foregroundStyle(active ? .white : MileTheme.muted)
                            .overlay(
                                Capsule().stroke(active ? MileTheme.asphalt : MileTheme.border, lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            if filteredDrives.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "car.2.fill")
                        .font(.title2)
                        .foregroundStyle(MileTheme.muted)
                    Text(L10n.t("No drives in this filter yet.", "该分类下暂无行程记录。", "此分類下暫無行車紀錄。"))
                        .font(.subheadline)
                        .foregroundStyle(MileTheme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .mileCard()
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredDrives) { drive in
                        driveRow(drive, computedDeduction: dedMap[drive.id])
                    }
                }
            }
        }
    }

    private func driveRow(_ drive: DriveRecord, computedDeduction: Double?) -> some View {
        let ded: Double = {
            if drive.classification == .unclassified {
                return IRSRateEngine.deduction(
                    for: drive,
                    settings: ledger.settings,
                    includePotentialForUnclassified: true,
                    priorDeductibleMilesInYear: ledger.ytdDeductibleMiles
                )
            }
            return computedDeduction ?? IRSRateEngine.deduction(for: drive, settings: ledger.settings)
        }()
        let rateStr = IRSRateEngine.effectiveRateLabel(for: drive, settings: ledger.settings)

        return Button {
            editingDrive = DriveEditTarget(drive: drive)
        } label: {
            HStack(spacing: 12) {
                // Classification Icon Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(drive.classification.softBackground)
                        .frame(width: 44, height: 44)
                    Image(systemName: drive.classification.icon)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(drive.classification.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(drive.classification.shortTag)
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(drive.classification.softBackground)
                            .foregroundStyle(drive.classification.color)
                            .clipShape(Capsule())

                        Text(Self.rowDateFormatter.string(from: drive.startDate))
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(MileTheme.muted)
                    }

                    Text("\(drive.startAddress) → \(drive.endAddress)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(MileTheme.ink)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Label(drive.purpose.title, systemImage: drive.purpose.icon)
                            .font(.caption2)
                            .foregroundStyle(MileTheme.muted)
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(MileTheme.border)
                        Text(rateStr)
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(MileTheme.muted)
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(
                        drive.classification == .personal
                            ? IRSRateEngine.formatMoney(0, symbol: ledger.settings.currencySymbol)
                            : (drive.classification == .unclassified ? "~\(IRSRateEngine.formatMoney(ded, symbol: ledger.settings.currencySymbol))" : IRSRateEngine.formatMoney(ded, symbol: ledger.settings.currencySymbol))
                    )
                    .font(.subheadline.weight(.heavy).monospacedDigit())
                    .foregroundStyle(
                        drive.classification == .personal ? MileTheme.muted :
                            (drive.classification == .unclassified ? MileTheme.amber : MileTheme.emerald)
                    )

                    Text(IRSRateEngine.formatDistance(drive.distanceMiles, unit: ledger.settings.distanceUnit))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(MileTheme.muted)
                }
            }
            .mileCard(padding: 13)
        }
        .buttonStyle(.plain)
    }

    private func quickClassify(_ drive: DriveRecord, as classification: DriveClassification) {
        if !store.canClassifyFreeDrive {
            let msg = L10n.t(
                "You've used all 20 free drive classifications this month. Unlock Pro for unlimited sorting & exports.",
                "本月 20 次免费分类额度已用完，解锁 Pro 即可无限分类并导出报税报表。",
                "本月 20 次免費分類額度已用完，解鎖 Pro 即可無限分類並匯出里程報稅總帳。"
            )
            if let onRequestPaywall {
                onRequestPaywall(msg, ledger.formattedYTDDeduction)
            } else {
                showPaywall = true
            }
            return
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            ledger.classifyDrive(drive.id, as: classification)
            store.recordClassifiedOrExportedDrive()
            FunnelMetrics.record(.driveClassified)
            reviewManager.recordClassifiedDrive(totalClassified: store.totalClassifiedDrives)
        }
    }

    private static let rowDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        return df
    }()
}
