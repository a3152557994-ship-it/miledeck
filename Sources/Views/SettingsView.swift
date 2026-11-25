import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var ledger: MileageStore
    @EnvironmentObject private var tracker: DriveTrackingService
    @EnvironmentObject private var store: StoreManager

    @Binding var showPaywall: Bool
    var onRequestPaywall: ((_ triggerMessage: String?, _ lockedDeductionText: String?) -> Void)? = nil

    @State private var showJSONExporter: Bool = false
    @State private var showJSONImporter: Bool = false
    @State private var backupDoc: JSONBackupDocument? = nil
    @State private var backupNotice: String? = nil
    @State private var customRateText: String = ""

    private let privacyURL = URL(string: "https://a3152557994-ship-it.github.io/miledeck/privacy.html")!
    private let termsURL = URL(string: "https://a3152557994-ship-it.github.io/miledeck/terms.html")!
    private let supportURL = URL(string: "https://a3152557994-ship-it.github.io/miledeck/support.html")!

    private let flatBillURL = URL(string: "https://apps.apple.com/app/id6839021639")!
    private let flatShiftURL = URL(string: "https://apps.apple.com/app/id6839022439")!
    private let pureScanURL = URL(string: "https://apps.apple.com/app/id6837347918")!
    private let cleanShieldURL = URL(string: "https://apps.apple.com/app/id6836843272")!

    var body: some View {
        NavigationStack {
            Form {
                // Pro Lifetime Status Card
                Section {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(store.isPro ? MileTheme.emeraldSoft : MileTheme.asphalt)
                                .frame(width: 46, height: 46)
                            Image(systemName: store.isPro ? "checkmark.seal.fill" : "crown.fill")
                                .font(.title3)
                                .foregroundStyle(store.isPro ? MileTheme.emerald : Color(red: 0.43, green: 0.94, blue: 0.74))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(
                                store.isPro
                                    ? L10n.t("MileDeck Pro Active", "MileDeck Pro 已激活", "MileDeck Pro 已啟用")
                                    : L10n.t(
                                        "Free Tier (\(store.remainingFreeDrivesThisMonth)/20 left)",
                                        "免费版（本月剩 \(store.remainingFreeDrivesThisMonth)/20 趟）",
                                        "免費版（本月剩 \(store.remainingFreeDrivesThisMonth)/20 趟）"
                                    )
                            )
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(MileTheme.ink)
                            Text(
                                store.isPro
                                    ? L10n.t("Unlimited drives, swipes & audit-ready tax exports unlocked.", "已解锁无限行程分类、报税 PDF 与 CSV 导出。", "已解鎖無限行車紀錄分類、里程報稅 PDF 與 CSV 匯出。")
                                    : L10n.t(
                                        "Pay \(store.displayPrice(for: MileDeckProductID.lifetime)) once or start a 7-day free trial.",
                                        "一次买断 \(store.displayPrice(for: MileDeckProductID.lifetime))，或开启 7 天免费试用。",
                                        "一次買斷 \(store.displayPrice(for: MileDeckProductID.lifetime))，或開啟 7 天免費試用。"
                                    )
                            )
                            .font(.caption)
                            .foregroundStyle(MileTheme.muted)
                        }
                        Spacer()
                        if !store.isPro {
                            Button(L10n.t("Upgrade", "解锁", "升級")) {
                                if let onRequestPaywall {
                                    onRequestPaywall(nil, nil)
                                } else {
                                    showPaywall = true
                                }
                            }
                            .font(.caption.weight(.heavy))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(MileTheme.emerald)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 4)

                    Button {
                        Task { await store.restorePurchases() }
                    } label: {
                        HStack {
                            Label(L10n.t("Restore Purchases", "恢复已购项目", "回復已購項目"), systemImage: "arrow.clockwise.circle")
                            Spacer()
                            if store.isPurchasing {
                                ProgressView()
                            }
                        }
                    }

                    if let msg = store.statusMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(MileTheme.emerald)
                    }
                }

                // Auto-Drive Detection
                Section(L10n.t("Automatic Drive Detection", "自动识车记录", "自動偵測行車紀錄")) {
                    Toggle(isOn: $ledger.settings.autoDriveEnabled) {
                        Label(L10n.t("Auto-Detect Drives", "后台自动识别行车", "背景自動偵測開車"), systemImage: "location.fill.viewfinder")
                    }
                    .tint(MileTheme.emerald)
                    .onChange(of: ledger.settings.autoDriveEnabled) { _, newVal in
                        tracker.configureAutoDetection(
                            enabled: newVal,
                            sensitivity: ledger.settings.autoDriveSensitivity
                        ) { completed in
                            ledger.addDrive(completed)
                        }
                    }

                    Picker(L10n.t("Trigger Sensitivity", "触发灵敏度", "觸發靈敏度"), selection: $ledger.settings.autoDriveSensitivity) {
                        ForEach(AutoDriveSensitivity.allCases) { sens in
                            Text(sens.title).tag(sens)
                        }
                    }
                    .onChange(of: ledger.settings.autoDriveSensitivity) { _, newVal in
                        tracker.configureAutoDetection(
                            enabled: ledger.settings.autoDriveEnabled,
                            sensitivity: newVal
                        ) { completed in
                            ledger.addDrive(completed)
                        }
                    }

                    if !tracker.isAuthorizedForAlways {
                        Button {
                            tracker.requestLocationPermission(always: true)
                        } label: {
                            Label(L10n.t("Grant 'Always' Location for Hands-Free Tracking", "授权“始终”定位以启用后台自动记录", "授權「永遠」定位以啟用背景自動記錄"), systemImage: "hand.raised.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(MileTheme.emerald)
                        }
                    }
                }

                // Multi-Country Tax Rate Preset Engine
                Section(L10n.t("Tax Region, Official Rates & Units", "国家/地区税率预设与单位", "國家／地區稅率預設與單位")) {
                    Picker(L10n.t("Tax Region Preset", "报税地区预设", "報稅地區預設"), selection: Binding(
                        get: { ledger.settings.taxRegion },
                        set: { newPreset in
                            ledger.settings.applyTaxRegion(newPreset)
                            customRateText = String(format: "%.3f", ledger.settings.customRatePerUnit)
                        }
                    )) {
                        ForEach(TaxRegionPreset.allCases) { preset in
                            Text("\(preset.flagEmoji) \(preset.displayName)").tag(preset)
                        }
                    }

                    Picker(L10n.t("Distance Unit", "距离单位", "距離單位"), selection: $ledger.settings.distanceUnit) {
                        ForEach(DistanceUnit.allCases) { u in
                            Text(u.fullLabel).tag(u)
                        }
                    }

                    regionRatesBreakdownView
                        .padding(.vertical, 4)

                    Toggle(L10n.t("Use Custom Business Rate Override", "启用自定义费率覆盖", "啟用自訂商務費率"), isOn: $ledger.settings.useCustomRate)
                        .tint(MileTheme.emerald)

                    if ledger.settings.useCustomRate {
                        HStack {
                            Text(L10n.t("Custom Rate (\(ledger.settings.currencySymbol)/\(ledger.settings.distanceUnit.shortLabel))", "自定义单价（\(ledger.settings.currencySymbol)/\(ledger.settings.distanceUnit.shortLabel)）", "自訂單價（\(ledger.settings.currencySymbol)/\(ledger.settings.distanceUnit.shortLabel)）"))
                            Spacer()
                            TextField("0.76", text: $customRateText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .frame(width: 90)
                                .onChange(of: customRateText) { _, val in
                                    if let num = Double(val.replacingOccurrences(of: ",", with: ".")), num >= 0 {
                                        ledger.settings.customRatePerUnit = num
                                    }
                                }
                        }
                    }
                }

                // Taxpayer Info for PDF Header
                Section(L10n.t("Tax Logbook Header", "报税总账抬头", "里程報稅總帳抬頭")) {
                    HStack {
                        Text(L10n.t("Driver / Business", "姓名 / 商号", "姓名／商號"))
                        Spacer()
                        TextField(L10n.t("Your Name", "您的姓名", "您的姓名"), text: $ledger.settings.driverName)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // Offline Local Backup & Restore
                Section(L10n.t("100% Offline Data & Backup", "100% 本地备份与恢复", "100% 本機備份與還原")) {
                    Button {
                        do {
                            let data = try ledger.exportJSONBackupData()
                            backupDoc = JSONBackupDocument(data: data)
                            showJSONExporter = true
                        } catch {
                            backupNotice = error.localizedDescription
                        }
                    } label: {
                        Label(L10n.t("Export Local JSON Backup", "导出本地 JSON 全量备份", "匯出本機 JSON 完整備份"), systemImage: "externaldrive.badge.checkmark")
                            .foregroundStyle(MileTheme.ink)
                    }

                    Button {
                        showJSONImporter = true
                    } label: {
                        Label(L10n.t("Restore from JSON Backup", "从 JSON 备份恢复数据", "從 JSON 備份還原資料"), systemImage: "square.and.arrow.down")
                            .foregroundStyle(MileTheme.ink)
                    }

                    if let backupNotice {
                        Text(backupNotice)
                            .font(.caption)
                            .foregroundStyle(MileTheme.emerald)
                    }
                }

                // Cross-Promotion: More Zero-Subscription Offline Tools
                Section(L10n.t("More Zero-Subscription Offline Tools", "更多零订阅离线效率工具", "更多零訂閱離線效率工具")) {
                    crossPromoLink(
                        title: "FlatBill",
                        subtitle: L10n.t("Offline Invoice & Quote Maker", "离线发票与报价单生成工具", "離線發票與報價單工具"),
                        icon: "doc.text.fill",
                        url: flatBillURL
                    )
                    crossPromoLink(
                        title: "FlatShift",
                        subtitle: L10n.t("Offline Shift & Paycheck Tracker", "离线排班工时与薪资统计", "離線排班工時與薪資統計"),
                        icon: "clock.badge.checkmark.fill",
                        url: flatShiftURL
                    )
                    crossPromoLink(
                        title: "PureScan",
                        subtitle: L10n.t("Offline Document Scanner & PDF", "纯本地离线文档扫描与 PDF", "純本機離線文件掃描與 PDF"),
                        icon: "doc.viewfinder.fill",
                        url: pureScanURL
                    )
                    crossPromoLink(
                        title: "CleanShield",
                        subtitle: L10n.t("Private Photo & Storage Cleaner", "零上传隐私相册瘦身清理", "零上傳隱私相簿瘦身清理"),
                        icon: "shield.lefthalf.filled",
                        url: cleanShieldURL
                    )
                }

                // Legal & Support
                Section(L10n.t("Legal & Support", "隐私条款与技术支持", "隱私條款與技術支援")) {
                    Link(destination: privacyURL) {
                        Label(L10n.t("Privacy Policy (Zero Cloud Tracking)", "隐私政策（零云端追踪）", "隱私權政策（零雲端追蹤）"), systemImage: "lock.shield")
                    }
                    Link(destination: termsURL) {
                        Label(L10n.t("Terms of Use (EULA)", "使用条款 (EULA)", "使用條款 (EULA)"), systemImage: "doc.plaintext")
                    }
                    Link(destination: supportURL) {
                        Label(L10n.t("Support & FAQ", "帮助与技术支持", "常見問題與技術支援"), systemImage: "envelope.open")
                    }
                    HStack {
                        Text(L10n.t("Version", "版本", "版本"))
                        Spacer()
                        Text("1.0.1 (Offline Engine)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(MileTheme.muted)
                    }
                }
            }
            .navigationTitle(L10n.t("Settings", "设置", "設定"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                customRateText = String(format: "%.3f", ledger.settings.customRatePerUnit)
            }
            .fileExporter(
                isPresented: $showJSONExporter,
                document: backupDoc,
                contentType: .json,
                defaultFilename: "MileDeck_Backup_2026"
            ) { result in
                switch result {
                case .success:
                    backupNotice = L10n.t("Local JSON backup saved successfully!", "本地 JSON 备份已保存！", "本機 JSON 備份已儲存！")
                case .failure(let err):
                    backupNotice = err.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $showJSONImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        try ledger.restoreJSONBackupData(data)
                        backupNotice = L10n.t(
                            "Restored \(ledger.drives.count) drives & \(ledger.vehicles.count) vehicles!",
                            "已恢复 \(ledger.drives.count) 趟行程与 \(ledger.vehicles.count) 辆车！",
                            "已還原 \(ledger.drives.count) 趟行車紀錄與 \(ledger.vehicles.count) 輛車！"
                        )
                    } catch {
                        backupNotice = L10n.t("Invalid backup file: \(error.localizedDescription)", "备份文件无效：\(error.localizedDescription)", "備份檔案無效：\(error.localizedDescription)")
                    }
                case .failure(let err):
                    backupNotice = err.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private var regionRatesBreakdownView: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch ledger.settings.taxRegion {
            case .usIRS2026:
                rateRow(L10n.t("Business (Jan 1 – Jun 30, 2026)", "商务（2026 上半年）", "商務（2026 上半年）"), "$0.725 / mi")
                rateRow(L10n.t("Business (Jul 1 – Dec 31, 2026)", "商务（2026 下半年）", "商務（2026 下半年）"), "$0.760 / mi", highlight: true)
                rateRow(L10n.t("Medical / Moving", "医疗 / 搬迁", "醫療／搬遷"), "$0.210 / mi")
                rateRow(L10n.t("Charity", "公益慈善", "公益慈善"), "$0.140 / mi")
            case .ukHMRC:
                rateRow(L10n.t("First 10,000 business miles", "首 10,000 英里", "前 10,000 英里"), "£0.45 / mi", highlight: true)
                rateRow(L10n.t("Miles over 10,000", "超出 10,000 英里", "超過 10,000 英里"), "£0.25 / mi")
            case .auATO:
                rateRow(L10n.t("ATO Cents-per-km standard rate", "ATO 标准公里抵税率", "ATO 標準公里抵稅率"), "A$0.88 / km", highlight: true)
            case .caCRA:
                rateRow(L10n.t("First 5,000 business km", "前 5,000 公里", "前 5,000 公里"), "CA$0.72 / km", highlight: true)
                rateRow(L10n.t("Kilometres over 5,000", "超出 5,000 公里", "超過 5,000 公里"), "CA$0.66 / km")
            case .euStandard:
                rateRow(L10n.t("EU Standard business allowance", "欧盟标准商务里程费率", "歐盟標準商務里程費率"), "€0.30 / km", highlight: true)
            }
        }
    }

    private func crossPromoLink(title: String, subtitle: String, icon: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(MileTheme.emerald)
                    .frame(width: 28, height: 28)
                    .background(MileTheme.emeraldSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(MileTheme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(MileTheme.muted)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(MileTheme.muted)
            }
        }
    }

    private func rateRow(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(highlight ? MileTheme.ink : MileTheme.muted)
            Spacer()
            Text(value)
                .font(.caption.weight(.heavy).monospacedDigit())
                .foregroundStyle(highlight ? MileTheme.emerald : MileTheme.ink)
        }
    }
}

struct JSONBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
