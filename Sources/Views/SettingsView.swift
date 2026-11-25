import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var ledger: MileageStore
    @EnvironmentObject private var tracker: DriveTrackingService
    @EnvironmentObject private var store: StoreManager

    @Binding var showPaywall: Bool

    @State private var showJSONExporter: Bool = false
    @State private var showJSONImporter: Bool = false
    @State private var backupDoc: JSONBackupDocument? = nil
    @State private var backupNotice: String? = nil
    @State private var customRateText: String = ""

    private let privacyURL = URL(string: "https://a3152557994-ship-it.github.io/miledeck/privacy.html")!
    private let termsURL = URL(string: "https://a3152557994-ship-it.github.io/miledeck/terms.html")!
    private let supportURL = URL(string: "https://a3152557994-ship-it.github.io/miledeck/support.html")!

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
                            Text(store.isPro ? L10n.t("MileDeck Pro Active", "MileDeck Pro 已激活") : L10n.t("Free Tier (\(store.remainingFreeDrivesThisMonth)/20 left)", "免费版（本月剩 \(store.remainingFreeDrivesThisMonth)/20 趟）"))
                                .font(.subheadline.weight(.heavy))
                                .foregroundStyle(MileTheme.ink)
                            Text(
                                store.isPro
                                    ? L10n.t("Unlimited drives, swipes & IRS reports unlocked.", "已解锁无限行程分类、报税 PDF 与 CSV 导出。")
                                    : L10n.t("Pay \(store.displayPrice(for: MileDeckProductID.lifetime)) once — own forever.", "一次买断 \(store.displayPrice(for: MileDeckProductID.lifetime))，终身告别高价年卡。")
                            )
                            .font(.caption)
                            .foregroundStyle(MileTheme.muted)
                        }
                        Spacer()
                        if !store.isPro {
                            Button(L10n.t("Upgrade", "解锁")) {
                                showPaywall = true
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
                            Label(L10n.t("Restore Purchases", "恢复已购项目"), systemImage: "arrow.clockwise.circle")
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
                Section(L10n.t("Automatic Drive Detection", "自动识车记录")) {
                    Toggle(isOn: $ledger.settings.autoDriveEnabled) {
                        Label(L10n.t("Auto-Detect Drives", "后台自动识别行车"), systemImage: "location.fill.viewfinder")
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

                    Picker(L10n.t("Trigger Sensitivity", "触发灵敏度"), selection: $ledger.settings.autoDriveSensitivity) {
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
                            Label(L10n.t("Grant 'Always' Location for Hands-Free Tracking", "授权“始终”定位以启用后台自动记录"), systemImage: "hand.raised.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(MileTheme.emerald)
                        }
                    }
                }

                // 2026 IRS Rates & Units
                Section(L10n.t("2026 IRS Rates & Distance Units", "2026 IRS 分段费率与单位")) {
                    Picker(L10n.t("Distance Unit", "距离单位"), selection: $ledger.settings.distanceUnit) {
                        ForEach(DistanceUnit.allCases) { u in
                            Text(u.fullLabel).tag(u)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        rateRow(L10n.t("Business (Jan 1 – Jun 30, 2026)", "商务（2026 上半年）"), "$0.725 / mi")
                        rateRow(L10n.t("Business (Jul 1 – Dec 31, 2026)", "商务（2026 下半年）"), "$0.760 / mi", highlight: true)
                        rateRow(L10n.t("Medical / Moving", "医疗 / 搬迁"), "$0.210 / mi")
                        rateRow(L10n.t("Charity", "公益慈善"), "$0.140 / mi")
                    }
                    .padding(.vertical, 4)

                    Toggle(L10n.t("Use Custom Business Rate Override", "启用自定义费率覆盖"), isOn: $ledger.settings.useCustomRate)
                        .tint(MileTheme.emerald)

                    if ledger.settings.useCustomRate {
                        HStack {
                            Text(L10n.t("Custom Rate (per \(ledger.settings.distanceUnit.shortLabel))", "自定义单价（每 \(ledger.settings.distanceUnit.shortLabel)）"))
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
                Section(L10n.t("IRS Logbook Header", "报税总账抬头")) {
                    HStack {
                        Text(L10n.t("Driver / Business", "姓名 / 商号"))
                        Spacer()
                        TextField(L10n.t("Your Name", "您的姓名"), text: $ledger.settings.driverName)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // Offline Local Backup & Restore
                Section(L10n.t("100% Offline Data & Backup", "100% 本地备份与恢复")) {
                    Button {
                        do {
                            let data = try ledger.exportJSONBackupData()
                            backupDoc = JSONBackupDocument(data: data)
                            showJSONExporter = true
                        } catch {
                            backupNotice = error.localizedDescription
                        }
                    } label: {
                        Label(L10n.t("Export Local JSON Backup", "导出本地 JSON 全量备份"), systemImage: "externaldrive.badge.checkmark")
                            .foregroundStyle(MileTheme.ink)
                    }

                    Button {
                        showJSONImporter = true
                    } label: {
                        Label(L10n.t("Restore from JSON Backup", "从 JSON 备份恢复数据"), systemImage: "square.and.arrow.down")
                            .foregroundStyle(MileTheme.ink)
                    }

                    if let backupNotice {
                        Text(backupNotice)
                            .font(.caption)
                            .foregroundStyle(MileTheme.emerald)
                    }
                }

                // Legal & Support
                Section(L10n.t("Legal & Support", "隐私条款与技术支持")) {
                    Link(destination: privacyURL) {
                        Label(L10n.t("Privacy Policy (Zero Cloud Tracking)", "隐私政策（零云端追踪）"), systemImage: "lock.shield")
                    }
                    Link(destination: termsURL) {
                        Label(L10n.t("Terms of Use (EULA)", "使用条款 (EULA)"), systemImage: "doc.plaintext")
                    }
                    Link(destination: supportURL) {
                        Label(L10n.t("Support & FAQ", "帮助与技术支持"), systemImage: "envelope.open")
                    }
                    HStack {
                        Text(L10n.t("Version", "版本"))
                        Spacer()
                        Text("1.0.0 (Offline Engine)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(MileTheme.muted)
                    }
                }
            }
            .navigationTitle(L10n.t("Settings", "设置"))
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
                    backupNotice = L10n.t("Local JSON backup saved successfully!", "本地 JSON 备份已保存！")
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
                        backupNotice = L10n.t("Restored \(ledger.drives.count) drives & \(ledger.vehicles.count) vehicles!", "已恢复 \(ledger.drives.count) 趟行程与 \(ledger.vehicles.count) 辆车！")
                    } catch {
                        backupNotice = L10n.t("Invalid backup file: \(error.localizedDescription)", "备份文件无效：\(error.localizedDescription)")
                    }
                case .failure(let err):
                    backupNotice = err.localizedDescription
                }
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
