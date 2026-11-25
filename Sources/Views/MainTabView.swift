import SwiftUI

struct DriveEditTarget: Identifiable {
    let id = UUID()
    let drive: DriveRecord?
}

struct MainTabView: View {
    @EnvironmentObject private var ledger: MileageStore
    @EnvironmentObject private var tracker: DriveTrackingService
    @EnvironmentObject private var store: StoreManager

    @State private var selectedTab: Int = 0
    @State private var showSwipeDeck: Bool = false
    @State private var editingDrive: DriveEditTarget? = nil
    @State private var showPaywall: Bool = false
    @State private var didApplyLaunchDemo = false

    var body: some View {
        TabView(selection: $selectedTab) {
            DrivesHomeView(
                showSwipeDeck: $showSwipeDeck,
                editingDrive: $editingDrive,
                showPaywall: $showPaywall
            )
            .tabItem {
                Label(L10n.t("Drives", "行程"), systemImage: "road.lanes")
            }
            .tag(0)

            ReportsView(showPaywall: $showPaywall)
                .tabItem {
                    Label(L10n.t("Reports", "报税"), systemImage: "chart.bar.doc.horizontal.fill")
                }
                .tag(1)

            VehiclesView()
                .tabItem {
                    Label(L10n.t("Vehicles", "车辆"), systemImage: "car.2.fill")
                }
                .tag(2)

            SettingsView(showPaywall: $showPaywall)
                .tabItem {
                    Label(L10n.t("Settings", "设置"), systemImage: "gearshape.fill")
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
                        showPaywall = true
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
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .onAppear {
            tracker.configureAutoDetection(
                enabled: ledger.settings.autoDriveEnabled,
                sensitivity: ledger.settings.autoDriveSensitivity
            ) { completed in
                ledger.addDrive(completed)
            }
            applyDemoScreenIfNeeded()
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
                showPaywall = true
            default:
                break
            }
        }
    }
}
