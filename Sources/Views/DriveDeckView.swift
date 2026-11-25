import SwiftUI

struct DriveDeckView: View {
    @EnvironmentObject private var ledger: MileageStore
    @EnvironmentObject private var store: StoreManager
    @Environment(\.dismiss) private var dismiss

    var isModalSheet: Bool = true
    var onEditDrive: ((DriveRecord) -> Void)? = nil
    var onRequestPaywall: (() -> Void)? = nil

    @State private var dragOffset: CGSize = .zero
    @State private var selectedPurposeOverride: PurposeTag? = nil

    private var queue: [DriveRecord] {
        ledger.unclassifiedDrives
    }

    private var topDrive: DriveRecord? {
        queue.first
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Top Telemetry Strip
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.stack.fill")
                            .foregroundStyle(MileTheme.amber)
                        Text(
                            queue.isEmpty
                                ? L10n.t("All Caught Up!", "全部行程已分类！")
                                : L10n.t("\(queue.count) Unsorted Drives", "\(queue.count) 趟行程待分类")
                        )
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(MileTheme.ink)
                    }

                    Spacer()

                    if !queue.isEmpty {
                        Text(
                            L10n.t(
                                "+\(IRSRateEngine.formatMoney(ledger.pendingPotentialDeduction, symbol: ledger.settings.currencySymbol)) potential",
                                "潜在抵税 +\(IRSRateEngine.formatMoney(ledger.pendingPotentialDeduction, symbol: ledger.settings.currencySymbol))"
                            )
                        )
                        .font(.caption.weight(.heavy).monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(MileTheme.emeraldSoft)
                        .foregroundStyle(MileTheme.emerald)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)

                // Swipe Instruction Hint
                if !queue.isEmpty {
                    HStack {
                        Label(L10n.t("← Swipe Left: Personal", "← 左滑：私人行程"), systemImage: "house.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MileTheme.personalSlate)
                        Spacer()
                        Label(L10n.t("Swipe Right: Business →", "右滑：商务抵税 →"), systemImage: "briefcase.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MileTheme.emerald)
                    }
                    .padding(.horizontal, 18)
                }

                // Card Stack
                ZStack {
                    if queue.isEmpty {
                        emptyDeckCard
                    } else {
                        // Show up to 3 stacked cards (back-to-front)
                        let visible = Array(queue.prefix(3))
                        ForEach(Array(visible.enumerated().reversed()), id: \.element.id) { index, drive in
                            let isTop = index == 0
                            swipeCard(for: drive, isTop: isTop)
                                .scaleEffect(isTop ? 1.0 : max(0.90, 1.0 - CGFloat(index) * 0.045))
                                .offset(y: CGFloat(index) * 18)
                                .offset(x: isTop ? dragOffset.width : 0, y: isTop ? dragOffset.height * 0.18 : 0)
                                .rotationEffect(.degrees(isTop ? Double(dragOffset.width / 18.0) : 0))
                                .opacity(isTop ? 1.0 : (index == 1 ? 0.92 : 0.78))
                                .zIndex(Double(visible.count - index))
                                .gesture(
                                    isTop ? DragGesture()
                                        .onChanged { value in
                                            dragOffset = value.translation
                                        }
                                        .onEnded { value in
                                            if value.translation.width > 95 {
                                                performSwipe(.business, drive: drive)
                                            } else if value.translation.width < -95 {
                                                performSwipe(.personal, drive: drive)
                                            } else {
                                                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                                                    dragOffset = .zero
                                                }
                                            }
                                        } : nil
                                )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity)

                // Tactile Bottom Action Bar
                if let drive = topDrive {
                    HStack(spacing: 14) {
                        Button {
                            performSwipe(.personal, drive: drive)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.left.circle.fill")
                                    .font(.title3)
                                Text(L10n.t("Personal", "私人"))
                                    .font(.headline.weight(.bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(MileTheme.personalSoft)
                            .foregroundStyle(MileTheme.personalSlate)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(MileTheme.border, lineWidth: 1.2)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        if let onEditDrive {
                            Button {
                                onEditDrive(drive)
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.headline.weight(.bold))
                                    .frame(width: 50, height: 52)
                                    .background(MileTheme.card)
                                    .foregroundStyle(MileTheme.ink)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(MileTheme.border, lineWidth: 1.2)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }

                        Button {
                            performSwipe(.business, drive: drive)
                        } label: {
                            HStack(spacing: 8) {
                                Text(L10n.t("Business", "商务抵税"))
                                    .font(.headline.weight(.bold))
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.title3)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(MileTheme.emerald)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: MileTheme.emerald.opacity(0.28), radius: 8, y: 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
            .background(MileTheme.roadWhite.ignoresSafeArea())
            .navigationTitle(L10n.t("Drive Swipe Deck", "滑动分类行程"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if ledger.lastSwipedSnapshot != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                ledger.undoLastSwipe()
                            }
                        } label: {
                            Label(L10n.t("Undo", "撤回"), systemImage: "arrow.uturn.backward")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                if isModalSheet {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.t("Done", "完成")) { dismiss() }
                            .font(.subheadline.weight(.bold))
                    }
                }
            }
        }
    }

    private func swipeCard(for drive: DriveRecord, isTop: Bool) -> some View {
        let potentialDed = IRSRateEngine.deduction(for: drive, settings: ledger.settings, includePotentialForUnclassified: true)
        let periodBadge = IRSRateEngine.period(for: drive.startDate).shortBadge
        let activePurpose = (isTop ? selectedPurposeOverride : nil) ?? drive.purpose
        let durationMins = max(1, Int(drive.endDate.timeIntervalSince(drive.startDate) / 60))

        let businessOpacity = isTop ? min(1.0, max(0.0, Double(dragOffset.width - 20) / 90.0)) : 0.0
        let personalOpacity = isTop ? min(1.0, max(0.0, Double(-dragOffset.width - 20) / 90.0)) : 0.0

        return VStack(spacing: 0) {
            // Asphalt Dark Header Band
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(drive.isAutoDetected ? MileTheme.emeraldBright : MileTheme.amber)
                            .frame(width: 7, height: 7)
                        Text(drive.isAutoDetected ? L10n.t("AUTO-DETECTED", "自动识别") : L10n.t("LOGGED DRIVE", "手动记录"))
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.6)
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.11))
                    .clipShape(Capsule())

                    Spacer()

                    Text(periodBadge)
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(MileTheme.emerald.opacity(0.28))
                        .foregroundStyle(Color(red: 0.43, green: 0.94, blue: 0.74))
                        .clipShape(Capsule())
                }

                // Giant Deduction + Distance Metrics
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("IRS TAX VALUE", "预计可抵税"))
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(Color.white.opacity(0.60))
                        Text("+" + IRSRateEngine.formatMoney(potentialDed, symbol: ledger.settings.currencySymbol))
                            .font(.system(size: 36, weight: .heavy).monospacedDigit())
                            .foregroundStyle(Color(red: 0.25, green: 0.92, blue: 0.68))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(IRSRateEngine.formatDistance(drive.distanceMiles, unit: ledger.settings.distanceUnit))
                            .font(.system(size: 24, weight: .heavy).monospacedDigit())
                            .foregroundStyle(.white)
                        Text("\(Self.cardDateFormatter.string(from: drive.startDate)) • \(durationMins) \(L10n.t("min", "分钟"))")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.70))
                    }
                }
            }
            .padding(18)
            .background(MileTheme.asphalt)

            // Crisp White Card Body: Route Timeline + Purpose Tags
            VStack(alignment: .leading, spacing: 14) {
                // Route A -> B visual timeline
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 3) {
                        Circle()
                            .fill(MileTheme.emerald)
                            .frame(width: 11, height: 11)
                            .padding(.top, 4)
                        Rectangle()
                            .fill(MileTheme.border)
                            .frame(width: 2, height: 28)
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(MileTheme.amber)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("DEPARTED", "出发地"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(MileTheme.muted)
                            Text(drive.startAddress)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(MileTheme.ink)
                                .lineLimit(2)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("ARRIVED", "目的地"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(MileTheme.muted)
                            Text(drive.endAddress)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(MileTheme.ink)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(MileTheme.roadWhite)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Vehicle + Notes info row
                HStack(spacing: 8) {
                    Label(ledger.vehicleName(for: drive.vehicleId), systemImage: "car.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MileTheme.ink)
                        .lineLimit(1)
                    Spacer()
                    if let startOdo = drive.odometerStartMiles, let endOdo = drive.odometerEndMiles {
                        Text("\(Int(ledger.settings.distanceUnit.fromMiles(startOdo))) → \(Int(ledger.settings.distanceUnit.fromMiles(endOdo))) \(ledger.settings.distanceUnit.shortLabel)")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(MileTheme.muted)
                    }
                }

                // Quick Purpose Tag Selector
                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.t("QUICK PURPOSE TAG", "快捷用途标签"))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(MileTheme.muted)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(PurposeTag.allCases) { tag in
                                let selected = activePurpose == tag
                                Button {
                                    selectedPurposeOverride = tag
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: tag.icon)
                                            .font(.caption2)
                                        Text(tag.title)
                                            .font(.caption.weight(.semibold))
                                    }
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(selected ? MileTheme.asphalt : MileTheme.roadWhite)
                                    .foregroundStyle(selected ? .white : MileTheme.ink)
                                    .overlay(
                                        Capsule().stroke(selected ? MileTheme.asphalt : MileTheme.border, lineWidth: 1)
                                    )
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !drive.notes.isEmpty {
                    Text(drive.notes)
                        .font(.caption)
                        .foregroundStyle(MileTheme.muted)
                        .lineLimit(2)
                }
            }
            .padding(18)
            .background(MileTheme.card)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    businessOpacity > 0.15 ? MileTheme.emerald :
                        (personalOpacity > 0.15 ? MileTheme.personalSlate : MileTheme.border),
                    lineWidth: (businessOpacity > 0.15 || personalOpacity > 0.15) ? 2.5 : 1.2
                )
        )
        .shadow(color: MileTheme.asphalt.opacity(0.10), radius: 14, y: 8)
        .overlay(alignment: .topLeading) {
            if businessOpacity > 0.05 {
                Text(L10n.t("BUSINESS", "商务抵税"))
                    .font(.title3.weight(.black))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(MileTheme.emerald)
                    .background(Color.white.opacity(0.95))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(MileTheme.emerald, lineWidth: 3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .rotationEffect(.degrees(-14))
                    .padding(24)
                    .opacity(businessOpacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if personalOpacity > 0.05 {
                Text(L10n.t("PERSONAL", "私人行程"))
                    .font(.title3.weight(.black))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(MileTheme.personalSlate)
                    .background(Color.white.opacity(0.95))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(MileTheme.personalSlate, lineWidth: 3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .rotationEffect(.degrees(14))
                    .padding(24)
                    .opacity(personalOpacity)
            }
        }
    }

    private var emptyDeckCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(MileTheme.emerald)
            Text(L10n.t("Deck Cleared!", "全部行程已分类完成！"))
                .font(.title2.weight(.heavy))
                .foregroundStyle(MileTheme.ink)
            Text(L10n.t(
                "Your 2026 YTD IRS deduction is now \(IRSRateEngine.formatMoney(ledger.ytdTaxDeduction, symbol: ledger.settings.currencySymbol)) across \(IRSRateEngine.formatDistance(ledger.ytdDeductibleMiles, unit: ledger.settings.distanceUnit)).",
                "您 2026 年累计可抵税额已更新为 \(IRSRateEngine.formatMoney(ledger.ytdTaxDeduction, symbol: ledger.settings.currencySymbol))。"
            ))
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundStyle(MileTheme.muted)
            .padding(.horizontal, 16)

            if isModalSheet {
                Button {
                    dismiss()
                } label: {
                    Text(L10n.t("Back to Drives", "返回行程总览"))
                        .font(.headline.weight(.bold))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 13)
                        .background(MileTheme.asphalt)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.top, 6)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .mileCard(padding: 24)
    }

    private func performSwipe(_ classification: DriveClassification, drive: DriveRecord) {
        if !store.canClassifyOrExportFree {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                dragOffset = .zero
            }
            onRequestPaywall?()
            return
        }

        let targetX: CGFloat = classification == .business ? 440 : -440
        let chosenPurpose = selectedPurposeOverride ?? drive.purpose

        withAnimation(.easeOut(duration: 0.22)) {
            dragOffset = CGSize(width: targetX, height: 18)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.21) {
            ledger.classifyDrive(drive.id, as: classification, purpose: chosenPurpose)
            store.recordClassifiedOrExportedDrive()
            dragOffset = .zero
            selectedPurposeOverride = nil
        }
    }

    private static let cardDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM d · h:mm a"
        return df
    }()
}
