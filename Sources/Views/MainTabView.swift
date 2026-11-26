import SwiftUI

struct DriveEditTarget: Identifiable {
    let id = UUID()
    let drive: DriveRecord?
}

struct MainTabView: View {
    @EnvironmentObject private var ledger: MileageStore
    @EnvironmentObject private var tracker: DriveTrackingService
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var reviewManager: ReviewPromptManager

    @AppStorage("miledeck.onboarding.completed") private var hasCompletedOnboarding: Bool = false

    @State private var selectedTab: Int = 0
    @State private var showSwipeDeck: Bool = false
    @State private var editingDrive: DriveEditTarget? = nil
    @State private var showPaywall: Bool = false
    @State private var paywallTriggerMessage: String? = nil
    @State private var paywallLockedDeductionText: String? = nil
    @State private var showOnboarding: Bool = false
    @State private var didApplyLaunchDemo = false

    private var hasDemoScreenArg: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui_demo_screen")
    }

    private func openPaywall(triggerMessage: String? = nil, lockedDeductionText: String? = nil) {
        self.paywallTriggerMessage = triggerMessage
        if let explicit = lockedDeductionText, !explicit.isEmpty {
            self.paywallLockedDeductionText = explicit
        } else if ledger.ytdTaxDeduction > 0 {
            self.paywallLockedDeductionText = ledger.formattedYTDDeduction
        } else if ledger.pendingPotentialDeduction > 0 {
            self.paywallLockedDeductionText = IRSRateEngine.formatMoney(
                ledger.pendingPotentialDeduction,
                symbol: ledger.settings.currencySymbol
            )
        } else {
            self.paywallLockedDeductionText = nil
        }
        self.showPaywall = true
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DrivesHomeView(
                showSwipeDeck: $showSwipeDeck,
                editingDrive: $editingDrive,
                showPaywall: $showPaywall,
                onRequestPaywall: { msg, locked in
                    openPaywall(triggerMessage: msg, lockedDeductionText: locked)
                }
            )
            .tabItem {
                Label(L10n.t("Drives", "行程", "行車紀錄"), systemImage: "road.lanes")
            }
            .tag(0)

            ReportsView(
                showPaywall: $showPaywall,
                onRequestPaywall: { msg, locked in
                    openPaywall(triggerMessage: msg, lockedDeductionText: locked)
                }
            )
            .tabItem {
                Label(L10n.t("Reports", "报税", "里程報稅"), systemImage: "chart.bar.doc.horizontal.fill")
            }
            .tag(1)

            VehiclesView()
                .tabItem {
                    Label(L10n.t("Vehicles", "车辆", "車輛"), systemImage: "car.2.fill")
                }
                .tag(2)

            SettingsView(
                showPaywall: $showPaywall,
                onRequestPaywall: { msg, locked in
                    openPaywall(triggerMessage: msg, lockedDeductionText: locked)
                }
            )
            .tabItem {
                Label(L10n.t("Settings", "设置", "設定"), systemImage: "gearshape.fill")
            }
            .tag(3)
        }
        .tint(MileTheme.emerald)
        .sheet(isPresented: $showSwipeDeck) {
            DriveDeckView(
                isModalSheet: true,
                onEditDrive: { drive in
                    showSwipeDeck = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        editingDrive = DriveEditTarget(drive: drive)
                    }
                },
                onRequestPaywall: {
                    showSwipeDeck = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        openPaywall(
                            triggerMessage: L10n.t(
                                "You've reached 20 free classified drives this month. Unlock Pro for unlimited sorting & audit-ready exports.",
                                "本月 20 趟免费分类额度已用完，升级 Pro 即可无限分类并导出报税报表。",
                                "本月 20 趟免費分類額度已用完，升級 Pro 即可無限分類並匯出里程報稅總帳。"
                            )
                        )
                    }
                }
            )
        }
        .sheet(item: $editingDrive) { target in
            TripEditorSheet(
                drive: target.drive,
                defaultVehicleId: ledger.defaultVehicle?.id,
                unit: ledger.settings.distanceUnit
            )
        }
        .sheet(isPresented: $showPaywall, onDismiss: {
            paywallTriggerMessage = nil
            paywallLockedDeductionText = nil
        }) {
            PaywallView(
                triggerMessage: paywallTriggerMessage,
                lockedDeductionText: paywallLockedDeductionText
            )
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView { shouldOpenPaywall, estimatedText in
                hasCompletedOnboarding = true
                showOnboarding = false
                if shouldOpenPaywall && !store.isPro {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        openPaywall(
                            triggerMessage: L10n.t(
                                "Lock in your tax deduction tracking now — or start free with 20 drives/month.",
                                "立即解锁完整报税导出工具，或先免费体验每月 20 趟行程分类。",
                                "立即解鎖完整里程報稅工具，或先免費體驗每月 20 趟行車紀錄分類。"
                            ),
                            lockedDeductionText: estimatedText
                        )
                    }
                }
            }
        }
        .alert(
            L10n.t("Enjoying MileDeck?", "喜欢使用 MileDeck 吗？", "喜歡使用 MileDeck 嗎？"),
            isPresented: $reviewManager.showHappinessPrompt
        ) {
            Button(L10n.t("Yes, love it!", "很喜欢，去好评！", "很喜歡，去好評！")) {
                reviewManager.handleLoveIt()
            }
            Button(L10n.t("Send Feedback", "反馈建议", "回報建議")) {
                reviewManager.handleSendFeedback()
            }
            Button(L10n.t("Not Now", "暂不", "暫不"), role: .cancel) {
                reviewManager.handleDismiss()
            }
        } message: {
            Text(L10n.t(
                "Your feedback helps an indie developer keep MileDeck 100% offline and privacy-first.",
                "您的真实反馈能帮助独立开发者把 MileDeck 做得更好用、更省心。",
                "您的真實回饋能幫助獨立開發者把 MileDeck 做得更好用、更安心。"
            ))
        }
        .onAppear {
            tracker.bindLedger(ledger)
            tracker.configureAutoDetection(
                enabled: ledger.settings.autoDriveEnabled,
                sensitivity: ledger.settings.autoDriveSensitivity
            ) { completed in
                ledger.addDrive(completed)
            }
            Task {
                await tracker.backfillUnresolvedAddresses(in: ledger)
            }
            applyDemoScreenIfNeeded()
            if !hasCompletedOnboarding && !hasDemoScreenArg {
                showOnboarding = true
            }
        }
    }

    private func applyDemoScreenIfNeeded() {
        guard !didApplyLaunchDemo else { return }
        didApplyLaunchDemo = true
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-ui_demo_screen"), idx + 1 < args.count else { return }
        let screen = args[idx + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            switch screen {
            case "home":
                selectedTab = 0
            case "swipe":
                selectedTab = 0
                showSwipeDeck = true
            case "report":
                selectedTab = 1
            case "vehicles":
                selectedTab = 2
            case "settings":
                selectedTab = 3
            case "paywall":
                selectedTab = 0
                openPaywall()
            case "onboarding":
                showOnboarding = true
            default:
                break
            }
        }
    }
}
