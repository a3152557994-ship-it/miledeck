import SwiftUI

struct TripEditorSheet: View {
    @EnvironmentObject private var ledger: MileageStore
    @Environment(\.dismiss) private var dismiss

    let existingDrive: DriveRecord?

    @State private var startDate: Date
    @State private var durationMinutes: Int
    @State private var startAddress: String
    @State private var endAddress: String
    @State private var distanceInput: String
    @State private var classification: DriveClassification
    @State private var purpose: PurposeTag
    @State private var selectedVehicleId: UUID?
    @State private var notes: String

    init(drive: DriveRecord?, defaultVehicleId: UUID?, unit: DistanceUnit) {
        self.existingDrive = drive
        let now = Date()
        _startDate = State(initialValue: drive?.startDate ?? now.addingTimeInterval(-25 * 60))
        let mins = drive.map { max(1, Int($0.endDate.timeIntervalSince($0.startDate) / 60)) } ?? 25
        _durationMinutes = State(initialValue: mins)
        _startAddress = State(initialValue: drive?.startAddress ?? "")
        _endAddress = State(initialValue: drive?.endAddress ?? "")
        let initialDist = unit.fromMiles(drive?.distanceMiles ?? 12.5)
        _distanceInput = State(initialValue: String(format: "%.1f", initialDist))
        _classification = State(initialValue: drive?.classification ?? .business)
        _purpose = State(initialValue: drive?.purpose ?? .deliveryGig)
        _selectedVehicleId = State(initialValue: drive?.vehicleId ?? defaultVehicleId)
        _notes = State(initialValue: drive?.notes ?? "")
    }

    private var parsedMiles: Double {
        let raw = Double(distanceInput.replacingOccurrences(of: ",", with: ".")) ?? 0
        return max(0, ledger.settings.distanceUnit.toMiles(raw))
    }

    private var previewDrive: DriveRecord {
        DriveRecord(
            id: existingDrive?.id ?? UUID(),
            startDate: startDate,
            endDate: startDate.addingTimeInterval(Double(durationMinutes) * 60),
            startAddress: startAddress.isEmpty ? L10n.t("Start Location", "出发地点", "出發地點") : startAddress,
            endAddress: endAddress.isEmpty ? L10n.t("Destination", "目的地", "目的地") : endAddress,
            distanceMiles: parsedMiles,
            classification: classification,
            purpose: purpose,
            vehicleId: selectedVehicleId,
            odometerStartMiles: existingDrive?.odometerStartMiles,
            odometerEndMiles: existingDrive?.odometerEndMiles,
            isAutoDetected: existingDrive?.isAutoDetected ?? false,
            notes: notes
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                // Live Tax Rate & Deduction Banner
                Section {
                    let ded = IRSRateEngine.deduction(for: previewDrive, settings: ledger.settings, includePotentialForUnclassified: true)
                    let rateLabel = IRSRateEngine.effectiveRateLabel(for: previewDrive, settings: ledger.settings)
                    let periodBadge = IRSRateEngine.periodBadge(for: startDate, settings: ledger.settings)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(periodBadge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(MileTheme.emerald)
                            Text(L10n.t("Applied Rate: \(rateLabel)", "当前适用费率：\(rateLabel)", "目前適用費率：\(rateLabel)"))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(MileTheme.muted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(L10n.t("DEDUCTION", "抵税价值", "抵稅金額"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(MileTheme.muted)
                            Text(IRSRateEngine.formatMoney(ded, symbol: ledger.settings.currencySymbol))
                                .font(.title2.weight(.heavy).monospacedDigit())
                                .foregroundStyle(classification == .personal ? MileTheme.muted : MileTheme.emerald)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(L10n.t("Route & Distance", "路线与里程", "路線與里程")) {
                    TextField(L10n.t("Start address (e.g. Home Office)", "起点地址（如：工作室）", "起點地址（如：工作室）"), text: $startAddress)
                    TextField(L10n.t("Destination (e.g. Client Site)", "终点地址（如：客户现场）", "終點地址（如：客戶現場）"), text: $endAddress)
                    HStack {
                        Text(L10n.t("Distance (\(ledger.settings.distanceUnit.shortLabel))", "行驶距离 (\(ledger.settings.distanceUnit.shortLabel))", "行駛距離 (\(ledger.settings.distanceUnit.shortLabel))"))
                        Spacer()
                        TextField("0.0", text: $distanceInput)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.headline.monospacedDigit())
                            .frame(width: 100)
                    }
                    DatePicker(L10n.t("Trip Date & Time", "出发日期与时间", "出發日期與時間"), selection: $startDate)
                    Stepper(value: $durationMinutes, in: 1...720, step: 5) {
                        HStack {
                            Text(L10n.t("Duration", "行车时长", "行車時長"))
                            Spacer()
                            Text("\(durationMinutes) \(L10n.t("min", "分钟", "分鐘"))")
                                .foregroundStyle(MileTheme.muted)
                                .monospacedDigit()
                        }
                    }
                }

                Section(L10n.t("Tax Classification & Purpose", "税务分类与用途", "稅務分類與用途")) {
                    Picker(L10n.t("Classification", "分类", "分類"), selection: $classification) {
                        ForEach(DriveClassification.allCases) { cls in
                            Label(cls.title, systemImage: cls.icon).tag(cls)
                        }
                    }

                    Picker(L10n.t("Purpose", "行程用途", "行程用途"), selection: $purpose) {
                        ForEach(PurposeTag.allCases) { p in
                            Label(p.title, systemImage: p.icon).tag(p)
                        }
                    }

                    if !ledger.vehicles.isEmpty {
                        Picker(L10n.t("Vehicle", "使用车辆", "使用車輛"), selection: $selectedVehicleId) {
                            ForEach(ledger.vehicles) { v in
                                Text(v.displayName).tag(Optional(v.id))
                            }
                        }
                    }
                }

                Section(L10n.t("Audit Notes (\(ledger.settings.taxRegion.pdfComplianceLabel))", "报税备注（留档说明）", "報稅備註（留檔說明）")) {
                    TextField(L10n.t("Optional client, job, or shift note", "选填：客户名称、订单或班次说明", "選填：客戶名稱、案件或班次說明"), text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let existing = existingDrive {
                    Section {
                        Button(role: .destructive) {
                            ledger.deleteDrive(existing.id)
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text(L10n.t("Delete Drive", "删除此行程", "刪除此行車紀錄"))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(existingDrive == nil ? L10n.t("Log Manual Drive", "手动记一笔里程", "手動記一筆里程") : L10n.t("Edit Drive", "编辑行程", "編輯行車紀錄"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("Cancel", "取消", "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("Save", "保存", "儲存")) {
                        let rec = previewDrive
                        if existingDrive != nil {
                            ledger.updateDrive(rec)
                        } else {
                            ledger.addDrive(rec)
                        }
                        dismiss()
                    }
                    .font(.subheadline.weight(.bold))
                    .disabled(parsedMiles <= 0)
                }
            }
        }
    }
}
