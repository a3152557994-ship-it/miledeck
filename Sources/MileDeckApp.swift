import SwiftUI

@main
struct MileDeckApp: App {
    @StateObject private var ledger = MileageStore()
    @StateObject private var tracker = DriveTrackingService()
    @StateObject private var store = StoreManager()
    @StateObject private var reviewManager = ReviewPromptManager()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(ledger)
                .environmentObject(tracker)
                .environmentObject(store)
                .environmentObject(reviewManager)
                .preferredColorScheme(.light)
        }
    }
}
