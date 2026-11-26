import CoreLocation
import CoreMotion
import PDFKit
import XCTest
@testable import MileDeck

private struct MockReverseGeocoder: ReverseGeocodingHandling {
    var shouldFailOffline: Bool = false
    var mapping: [String: String] = [:]

    func reverseGeocode(_ location: CLLocation) async throws -> String? {
        if shouldFailOffline {
            throw URLError(.notConnectedToInternet)
        }
        let key = DriveTrackingService.formatCoordinateFallback(location.coordinate)
        return mapping[key] ?? "120 Market St, San Francisco"
    }
}

@MainActor
final class MileDeckTests: XCTestCase {
    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        return comps.date!
    }

    private func tempStoreURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("miledeck_test_\(name)_\(UUID().uuidString).json")
    }

    private func makeDrive(
        date: Date,
        miles: Double,
        classification: DriveClassification = .business,
        purpose: PurposeTag = .clientSite
    ) -> DriveRecord {
        DriveRecord(
            startDate: date,
            endDate: date.addingTimeInterval(1800),
            startAddress: "Origin",
            endAddress: "Destination",
            distanceMiles: miles,
            classification: classification,
            purpose: purpose,
            vehicleId: nil,
            odometerStartMiles: nil,
            odometerEndMiles: nil,
            isAutoDetected: true,
            notes: ""
        )
    }

    // MARK: - 1. 2026 US IRS Split-Period Rates (100% Preserved)
    func test2026IRSSplitPeriodRatesH1vsH2() {
        let settings = DriverSettings.defaultSettings(for: "US")
        XCTAssertEqual(settings.taxRegion, .usIRS2026)

        // Jan 1 – Jun 30, 2026 => $0.725/mi
        let h1Start = makeDate(2026, 1, 15)
        let h1End = makeDate(2026, 6, 30)
        XCTAssertEqual(IRSRateEngine.period(for: h1Start), .h1_2026)
        XCTAssertEqual(IRSRateEngine.period(for: h1End), .h1_2026)
        XCTAssertEqual(IRSRateEngine.irsRatePerMile(for: .business, on: h1End), 0.725, accuracy: 0.0001)

        // Jul 1 – Dec 31, 2026 => $0.76/mi
        let h2Start = makeDate(2026, 7, 1)
        let h2End = makeDate(2026, 11, 25)
        XCTAssertEqual(IRSRateEngine.period(for: h2Start), .h2_2026)
        XCTAssertEqual(IRSRateEngine.period(for: h2End), .h2_2026)
        XCTAssertEqual(IRSRateEngine.irsRatePerMile(for: .business, on: h2Start), 0.76, accuracy: 0.0001)

        let h1Drive = makeDrive(date: h1End, miles: 100.0)
        let h2Drive = makeDrive(date: h2Start, miles: 100.0, purpose: .deliveryGig)

        XCTAssertEqual(IRSRateEngine.deduction(for: h1Drive, settings: settings), 72.50, accuracy: 0.01)
        XCTAssertEqual(IRSRateEngine.deduction(for: h2Drive, settings: settings), 76.00, accuracy: 0.01)

        // Medical ($0.21/mi), Charity ($0.14/mi), Personal ($0.00)
        var med = h2Drive; med.classification = .medical
        var chr = h2Drive; chr.classification = .charity
        var per = h2Drive; per.classification = .personal
        XCTAssertEqual(IRSRateEngine.deduction(for: med, settings: settings), 21.00, accuracy: 0.01)
        XCTAssertEqual(IRSRateEngine.deduction(for: chr, settings: settings), 14.00, accuracy: 0.01)
        XCTAssertEqual(IRSRateEngine.deduction(for: per, settings: settings), 0.00, accuracy: 0.01)
    }

    // MARK: - 2. Multi-Country Tax Presets (US / UK / AU / CA / EU + Locale Auto-Default)
    func testMultiCountryTaxPresetsAndAutoDefault() {
        // Locale auto-defaulting
        XCTAssertEqual(TaxRegionPreset.defaultForRegion("GB"), .ukHMRC)
        XCTAssertEqual(TaxRegionPreset.defaultForRegion("AU"), .auATO)
        XCTAssertEqual(TaxRegionPreset.defaultForRegion("CA"), .caCRA)
        for euCode in ["DE", "FR", "NL", "AT", "CH", "ES", "IT"] {
            XCTAssertEqual(TaxRegionPreset.defaultForRegion(euCode), .euStandard, "Expected euStandard for \(euCode)")
        }
        XCTAssertEqual(TaxRegionPreset.defaultForRegion("US"), .usIRS2026)
        XCTAssertEqual(TaxRegionPreset.defaultForRegion("JP"), .usIRS2026)

        let date = makeDate(2026, 9, 10)

        // UK HMRC: 45p first 10,000 mi, 25p after (GBP)
        let ukSettings = DriverSettings.defaultSettings(for: "GB")
        XCTAssertEqual(ukSettings.taxRegion, .ukHMRC)
        XCTAssertEqual(ukSettings.currencySymbol, "£")
        XCTAssertEqual(ukSettings.distanceUnit, .miles)
        let ukTier1 = makeDrive(date: date, miles: 100.0)
        XCTAssertEqual(IRSRateEngine.deduction(for: ukTier1, settings: ukSettings), 45.00, accuracy: 0.01)
        // Straddling 10,000 mi threshold: 9,800 prior + 500 mi = 200*0.45 + 300*0.25 = 90 + 75 = 165.00
        let ukStraddle = makeDrive(date: date, miles: 500.0)
        XCTAssertEqual(
            IRSRateEngine.deduction(for: ukStraddle, settings: ukSettings, priorDeductibleMilesInYear: 9800.0),
            165.00,
            accuracy: 0.01
        )
        // Over 10,000 mi: 25p/mi
        XCTAssertEqual(
            IRSRateEngine.deduction(for: ukTier1, settings: ukSettings, priorDeductibleMilesInYear: 10_000.0),
            25.00,
            accuracy: 0.01
        )

        // Australia ATO: 88¢/km (AUD)
        let auSettings = DriverSettings.defaultSettings(for: "AU")
        XCTAssertEqual(auSettings.taxRegion, .auATO)
        XCTAssertEqual(auSettings.currencySymbol, "A$")
        XCTAssertEqual(auSettings.distanceUnit, .kilometers)
        let au100Km = makeDrive(date: date, miles: DistanceUnit.kilometers.toMiles(100.0))
        XCTAssertEqual(IRSRateEngine.deduction(for: au100Km, settings: auSettings), 88.00, accuracy: 0.01)

        // Canada CRA: 72¢ first 5,000 km, 66¢ after (CAD)
        let caSettings = DriverSettings.defaultSettings(for: "CA")
        XCTAssertEqual(caSettings.taxRegion, .caCRA)
        XCTAssertEqual(caSettings.currencySymbol, "CA$")
        XCTAssertEqual(caSettings.distanceUnit, .kilometers)
        let ca100Km = makeDrive(date: date, miles: DistanceUnit.kilometers.toMiles(100.0))
        XCTAssertEqual(IRSRateEngine.deduction(for: ca100Km, settings: caSettings), 72.00, accuracy: 0.01)
        // Straddling 5,000 km: 4,800 km prior + 400 km = 200*0.72 + 200*0.66 = 144 + 132 = 276.00
        let ca400Km = makeDrive(date: date, miles: DistanceUnit.kilometers.toMiles(400.0))
        let prior4800KmInMiles = DistanceUnit.kilometers.toMiles(4800.0)
        XCTAssertEqual(
            IRSRateEngine.deduction(for: ca400Km, settings: caSettings, priorDeductibleMilesInYear: prior4800KmInMiles),
            276.00,
            accuracy: 0.01
        )
        // Over 5,000 km: 66¢/km
        let prior5000KmInMiles = DistanceUnit.kilometers.toMiles(5000.0)
        XCTAssertEqual(
            IRSRateEngine.deduction(for: ca100Km, settings: caSettings, priorDeductibleMilesInYear: prior5000KmInMiles),
            66.00,
            accuracy: 0.01
        )

        // EU Standard: €0.30/km (EUR)
        let euSettings = DriverSettings.defaultSettings(for: "DE")
        XCTAssertEqual(euSettings.taxRegion, .euStandard)
        XCTAssertEqual(euSettings.currencySymbol, "€")
        XCTAssertEqual(euSettings.distanceUnit, .kilometers)
        let eu100Km = makeDrive(date: date, miles: DistanceUnit.kilometers.toMiles(100.0))
        XCTAssertEqual(IRSRateEngine.deduction(for: eu100Km, settings: euSettings), 30.00, accuracy: 0.01)

        // Chronological multi-drive tiered aggregation for UK HMRC
        let ukTripA = makeDrive(date: makeDate(2026, 2, 1), miles: 9500.0)
        let ukTripB = makeDrive(date: makeDate(2026, 8, 1), miles: 1000.0) // 500 @ 0.45 + 500 @ 0.25 = 350
        let dedMap = IRSRateEngine.deductionsByDriveID(for: [ukTripB, ukTripA], settings: ukSettings)
        XCTAssertEqual(dedMap[ukTripA.id] ?? 0, 4275.00, accuracy: 0.01)
        XCTAssertEqual(dedMap[ukTripB.id] ?? 0, 350.00, accuracy: 0.01)
    }

    func testRegionalPDFHeadersRenderAccurately() {
        let drive = makeDrive(date: makeDate(2026, 8, 15), miles: 50.0)

        let ukSettings = DriverSettings.defaultSettings(for: "GB")
        let ukPDF = PDFDocument(data: IRSLogbookPDFRenderer.renderPDFData(drives: [drive], vehicles: [], settings: ukSettings, includeBrandingFooter: false))
        let ukText = ukPDF?.string ?? ""
        XCTAssertTrue(ukText.contains("HMRC"))
        XCTAssertTrue(ukText.contains("£"))

        let euSettings = DriverSettings.defaultSettings(for: "DE")
        let euPDF = PDFDocument(data: IRSLogbookPDFRenderer.renderPDFData(drives: [drive], vehicles: [], settings: euSettings, includeBrandingFooter: false))
        let euText = euPDF?.string ?? ""
        XCTAssertTrue(euText.contains("€0.30/km"))
    }

    // MARK: - 3. Regional Paywall Style Routing
    func testRegionalPaywallStyleRouting() {
        for code in ["US", "CA", "AU", "NZ", "BR", "MX"] {
            XCTAssertEqual(PaywallRegionStyle.resolve(for: code), .angloROI, "Expected angloROI for \(code)")
        }
        XCTAssertEqual(PaywallRegionStyle.resolve(for: nil), .angloROI)

        for code in ["DE", "CH", "AT", "GB", "FR", "NL", "SE", "NO", "DK", "FI", "IE", "IT", "ES"] {
            XCTAssertEqual(PaywallRegionStyle.resolve(for: code), .euPrivacyLifetime, "Expected euPrivacyLifetime for \(code)")
        }
        // EU pre-selects Lifetime FIRST
        XCTAssertEqual(PaywallRegionStyle.euPrivacyLifetime.defaultSelectedProductID, MileDeckProductID.lifetime)
        XCTAssertEqual(PaywallRegionStyle.angloROI.defaultSelectedProductID, MileDeckProductID.yearly)

        for code in ["JP", "KR", "TW", "HK", "MO", "SG"] {
            XCTAssertEqual(PaywallRegionStyle.resolve(for: code), .eastAsiaDetail, "Expected eastAsiaDetail for \(code)")
        }
    }

    // MARK: - 4. Free-Tier Export Gating & Pricing
    func testFreeTierExportGatingAndQuota() {
        let suiteName = "miledeck.tests.store.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let freeStore = StoreManager(defaults: defaults, isProOverride: false, autoLoadStoreKit: false)
        // Free user CAN classify drives up to 20/month, but CANNOT export audit PDF/CSV
        XCTAssertTrue(freeStore.canClassifyFreeDrive)
        XCTAssertFalse(freeStore.canExportTaxReport, "Free tier must NOT allow PDF/CSV export")
        XCTAssertEqual(freeStore.remainingFreeDrivesThisMonth, 20)

        // Classify 19 drives -> still allowed
        freeStore.recordClassifiedOrExportedDrive(count: 19)
        XCTAssertTrue(freeStore.canClassifyFreeDrive)
        XCTAssertEqual(freeStore.remainingFreeDrivesThisMonth, 1)
        XCTAssertFalse(freeStore.canExportTaxReport)

        // 20th drive hits monthly cap -> >20 drives/month gated behind Pro
        freeStore.recordClassifiedOrExportedDrive(count: 1)
        XCTAssertFalse(freeStore.canClassifyFreeDrive)
        XCTAssertEqual(freeStore.remainingFreeDrivesThisMonth, 0)
        XCTAssertFalse(freeStore.canExportTaxReport)

        // Pro user has both unlimited classification and export unlocked
        let proStore = StoreManager(defaults: defaults, isProOverride: true, autoLoadStoreKit: false)
        XCTAssertTrue(proStore.canClassifyFreeDrive)
        XCTAssertTrue(proStore.canExportTaxReport)

        // Verify Day 5 trial reminder delay (120 hours = 5 days)
        XCTAssertEqual(StoreManager.trialReminderDelaySeconds, 5 * 24 * 3600)

        // Verify fallback display prices across EN / zh-Hans / zh-Hant
        let savedLang = L10n.forcedLanguage
        defer { L10n.forcedLanguage = savedLang }

        L10n.forcedLanguage = "en"
        XCTAssertEqual(freeStore.displayPrice(for: MileDeckProductID.lifetime), "$24.99")
        XCTAssertEqual(freeStore.displayPrice(for: MileDeckProductID.yearly), "$14.99")
        XCTAssertEqual(freeStore.displayPrice(for: MileDeckProductID.monthly), "$4.99")

        L10n.forcedLanguage = "zh-Hans"
        XCTAssertEqual(freeStore.displayPrice(for: MileDeckProductID.lifetime), "¥78")
        XCTAssertEqual(freeStore.displayPrice(for: MileDeckProductID.yearly), "¥48")
        XCTAssertEqual(freeStore.displayPrice(for: MileDeckProductID.monthly), "¥15")

        L10n.forcedLanguage = "zh-HK"
        XCTAssertEqual(freeStore.displayPrice(for: MileDeckProductID.lifetime), "HK$118")
        XCTAssertEqual(freeStore.displayPrice(for: MileDeckProductID.yearly), "HK$68")
        XCTAssertEqual(freeStore.displayPrice(for: MileDeckProductID.monthly), "HK$22")
    }

    // MARK: - 5. Traditional Chinese (`zh-Hant`) Detection & L10n
    func testTraditionalChineseLocalizationDetection() {
        let savedLang = L10n.forcedLanguage
        defer { L10n.forcedLanguage = savedLang }

        for code in ["zh-Hant", "zh-Hant-TW", "zh-HK", "zh-TW", "zh-MO"] {
            L10n.forcedLanguage = code
            XCTAssertTrue(L10n.isChinese, "Expected isChinese for \(code)")
            XCTAssertTrue(L10n.isTraditionalChinese, "Expected isTraditionalChinese for \(code)")
            XCTAssertEqual(L10n.t("Mileage Tax", "里程报税", "里程報稅"), "里程報稅")
            XCTAssertEqual(L10n.t("Lifetime", "买断"), "买断") // 2-arg backward compatibility
        }

        L10n.forcedLanguage = "zh-Hans"
        XCTAssertTrue(L10n.isChinese)
        XCTAssertFalse(L10n.isTraditionalChinese)
        XCTAssertEqual(L10n.t("Mileage Tax", "里程报税", "里程報稅"), "里程报税")

        L10n.forcedLanguage = "en-US"
        XCTAssertFalse(L10n.isChinese)
        XCTAssertFalse(L10n.isTraditionalChinese)
        XCTAssertEqual(L10n.t("Mileage Tax", "里程报税", "里程報稅"), "Mileage Tax")
    }

    // MARK: - 6. Funnel Metrics & Happy-Path Review Gate Throttle
    func testLocalFunnelMetricsAndReviewThrottle() {
        let suiteName = "miledeck.tests.funnel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        FunnelMetrics.record(.onboardingCompleted, defaults: defaults)
        FunnelMetrics.record(.driveClassified, by: 5, defaults: defaults)
        FunnelMetrics.record(.paywallViewed, defaults: defaults)
        XCTAssertEqual(FunnelMetrics.count(for: .onboardingCompleted, defaults: defaults), 1)
        XCTAssertEqual(FunnelMetrics.count(for: .driveClassified, defaults: defaults), 5)
        XCTAssertEqual(FunnelMetrics.count(for: .paywallViewed, defaults: defaults), 1)
        XCTAssertEqual(FunnelMetrics.count(for: .abandonOfferShown, defaults: defaults), 0)

        let reviewMgr = ReviewPromptManager(defaults: defaults)
        let t0 = makeDate(2026, 1, 10)
        // Below 5 classified drives -> should not prompt
        reviewMgr.recordClassifiedDrive(totalClassified: 4, now: t0)
        XCTAssertFalse(reviewMgr.showHappinessPrompt)

        // 5th classified drive -> prompts gently
        reviewMgr.recordClassifiedDrive(totalClassified: 5, now: t0)
        XCTAssertTrue(reviewMgr.showHappinessPrompt)
        reviewMgr.handleDismiss(now: t0)

        // Within 90 days -> throttled
        let day30 = t0.addingTimeInterval(30 * 24 * 3600)
        XCTAssertFalse(reviewMgr.canPrompt(now: day30))
        XCTAssertFalse(reviewMgr.triggerIfAllowed(now: day30))

        // After 91 days -> allowed again
        let day91 = t0.addingTimeInterval(91 * 24 * 3600)
        XCTAssertTrue(reviewMgr.canPrompt(now: day91))
    }

    // MARK: - 7. Preserved Core Suite (Custom Rate, Swipe/Undo, PDF, CSV, JSON Backup)
    func testCustomPerKmRateAndDistanceConversion() {
        var settings = DriverSettings.defaultSettings(for: "US")
        settings.distanceUnit = .kilometers
        settings.useCustomRate = true
        settings.customRatePerUnit = 0.50 // $0.50 per km

        let drive = makeDrive(date: makeDate(2026, 8, 10), miles: 10.0) // 16.09344 km -> * 0.50 = 8.05
        XCTAssertEqual(IRSRateEngine.deduction(for: drive, settings: settings), 8.05, accuracy: 0.01)
        XCTAssertEqual(DistanceUnit.kilometers.fromMiles(10.0), 16.09344, accuracy: 0.001)
        XCTAssertEqual(DistanceUnit.kilometers.toMiles(16.09344), 10.0, accuracy: 0.001)
    }

    func testSwipeClassificationAndUndo() {
        let store = MileageStore(storageURL: tempStoreURL("swipe"), seedIfEmpty: true)
        XCTAssertEqual(store.unclassifiedDrives.count, 3)
        let initialYTD = store.ytdTaxDeduction

        let top = store.unclassifiedDrives[0]
        let expectedGain = IRSRateEngine.deduction(
            for: top,
            settings: store.settings,
            includePotentialForUnclassified: true,
            priorDeductibleMilesInYear: store.ytdDeductibleMiles
        )
        XCTAssertGreaterThan(expectedGain, 0)

        // Swipe Right -> Business
        store.classifyDrive(top.id, as: .business, purpose: .clientSite)
        XCTAssertEqual(store.unclassifiedDrives.count, 2)
        XCTAssertEqual(store.ytdTaxDeduction, IRSRateEngine.roundCents(initialYTD + expectedGain), accuracy: 0.01)

        // Undo last swipe -> restores exact previous state
        store.undoLastSwipe()
        XCTAssertEqual(store.unclassifiedDrives.count, 3)
        XCTAssertEqual(store.ytdTaxDeduction, initialYTD, accuracy: 0.01)

        // Swipe Left -> Personal (no deduction increase)
        store.classifyDrive(top.id, as: .personal)
        XCTAssertEqual(store.unclassifiedDrives.count, 2)
        XCTAssertEqual(store.ytdTaxDeduction, initialYTD, accuracy: 0.01)
    }

    func testPDFKitIRSLogbookGeneration() {
        let store = MileageStore(storageURL: tempStoreURL("pdf"), seedIfEmpty: true)
        store.settings.applyTaxRegion(.usIRS2026)
        let data = IRSLogbookPDFRenderer.renderPDFData(
            drives: store.drives,
            vehicles: store.vehicles,
            settings: store.settings,
            includeBrandingFooter: false
        )
        XCTAssertGreaterThan(data.count, 4000, "Generated IRS PDF must contain substantial vector data")
        let pdfDoc = PDFDocument(data: data)
        XCTAssertNotNil(pdfDoc, "PDFKit must parse generated IRS logbook PDF cleanly")
        XCTAssertGreaterThanOrEqual(pdfDoc?.pageCount ?? 0, 1)
        let extractedText = pdfDoc?.string ?? ""
        XCTAssertTrue(extractedText.contains("0.725") || extractedText.contains("72.5"))
        XCTAssertTrue(extractedText.contains("0.760") || extractedText.contains("0.76"))
    }

    func testCSVExportFormatAndColumns() {
        let store = MileageStore(storageURL: tempStoreURL("csv"), seedIfEmpty: true)
        store.settings.applyTaxRegion(.usIRS2026)
        let csv = store.exportIRSCSV()
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 1 + store.drives.count)
        XCTAssertTrue(lines[0].contains("Period,Classification,Purpose"))
        XCTAssertTrue(csv.contains("2026-H1 (Jan-Jun)"))
        XCTAssertTrue(csv.contains("2026-H2 (Jul-Dec)"))
    }

    func testJSONBackupAndRestoreRoundTripIncludingLegacyV100() throws {
        let url1 = tempStoreURL("backup1")
        let url2 = tempStoreURL("backup2")
        let source = MileageStore(storageURL: url1, seedIfEmpty: true)
        source.settings.driverName = "Taylor Morgan"
        source.settings.applyTaxRegion(.caCRA)
        source.classifyDrive(source.unclassifiedDrives[0].id, as: .business)

        let jsonData = try source.exportJSONBackupData()
        XCTAssertGreaterThan(jsonData.count, 500)

        let target = MileageStore(storageURL: url2, seedIfEmpty: false)
        XCTAssertTrue(target.drives.isEmpty)

        try target.restoreJSONBackupData(jsonData)
        XCTAssertEqual(target.settings.driverName, "Taylor Morgan")
        XCTAssertEqual(target.settings.taxRegion, .caCRA)
        XCTAssertEqual(target.drives.count, source.drives.count)
        XCTAssertEqual(target.vehicles.count, source.vehicles.count)
        XCTAssertEqual(target.ytdTaxDeduction, source.ytdTaxDeduction, accuracy: 0.01)

        // Legacy v1.0.0 DriverSettings JSON without `taxRegion` must decode cleanly to `.usIRS2026`
        let legacyJSON = """
        {
          "driverName": "Legacy Driver",
          "taxYear": 2026,
          "distanceUnit": "miles",
          "autoDriveEnabled": true,
          "autoDriveSensitivity": "balanced",
          "useCustomRate": false,
          "customRatePerUnit": 0.76,
          "currencySymbol": "$"
        }
        """.data(using: .utf8)!
        let decodedLegacy = try JSONDecoder.mileDeck.decode(DriverSettings.self, from: legacyJSON)
        XCTAssertEqual(decodedLegacy.driverName, "Legacy Driver")
        XCTAssertEqual(decodedLegacy.taxRegion, .usIRS2026)
    }

    // MARK: - 8. Auto-Stop Stationary Detection, Anti-Fake-Mileage & Geocoding Compliance
    func testAutoDriveStationaryThresholdStopsGPSAndSavesCompletedDrive() async {
        let store = MileageStore(storageURL: tempStoreURL("autostop"), seedIfEmpty: false)
        let mockGeo = MockReverseGeocoder(
            shouldFailOffline: false,
            mapping: [
                "37.7749, -122.4194": "120 Market St, San Francisco",
                "37.7897, -122.4014": "450 Sutter St, San Francisco",
            ]
        )
        let tracker = DriveTrackingService(geocoder: mockGeo, enableNetworkMonitor: false)
        tracker.bindLedger(store)
        tracker.autoStopStationaryThresholdSeconds = 180.0
        tracker.autoTriggerRequiredConsecutiveFixes = 2
        tracker.autoRestartCooldownSeconds = 60.0

        var autoCompletedDrives: [DriveRecord] = []
        tracker.configureAutoDetection(enabled: true, sensitivity: .balanced) { completed in
            autoCompletedDrives.append(completed)
            store.addDrive(completed)
        }

        let t0 = Date(timeIntervalSince1970: 1_795_000_000)

        // Two consecutive driving GPS fixes (~25 mph = 11.2 m/s) trigger automatic recording
        let loc1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 10,
            horizontalAccuracy: 8,
            verticalAccuracy: 8,
            course: 45,
            speed: 11.2,
            timestamp: t0
        )
        let loc2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7765, longitude: -122.4175),
            altitude: 10,
            horizontalAccuracy: 8,
            verticalAccuracy: 8,
            course: 45,
            speed: 12.5,
            timestamp: t0.addingTimeInterval(15)
        )
        tracker.processLocationUpdate(loc1)
        XCTAssertFalse(tracker.isRecording, "Single GPS spike must not prematurely start auto-recording")
        tracker.processLocationUpdate(loc2)
        XCTAssertTrue(tracker.isRecording, "Two qualifying automotive fixes must start auto-recording")
        XCTAssertTrue(tracker.isCurrentDriveAutoDetected)

        // Drive ~1.4 miles to destination
        let loc3 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7897, longitude: -122.4014),
            altitude: 12,
            horizontalAccuracy: 8,
            verticalAccuracy: 8,
            course: 45,
            speed: 13.0,
            timestamp: t0.addingTimeInterval(140)
        )
        tracker.processLocationUpdate(loc3)
        XCTAssertGreaterThan(tracker.liveDistanceMiles, 1.0)

        // Allow async start geocoding task to settle
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Vehicle parks (speed = 0.0 m/s < 0.8 m/s) for 120s -> still recording (< 180s threshold)
        let parked120 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7897, longitude: -122.4014),
            altitude: 12,
            horizontalAccuracy: 8,
            verticalAccuracy: 8,
            course: 0,
            speed: 0.2,
            timestamp: t0.addingTimeInterval(260)
        )
        tracker.processLocationUpdate(parked120)
        XCTAssertTrue(tracker.isRecording)
        XCTAssertEqual(autoCompletedDrives.count, 0)

        // Driver exits car / stationary reaches 185s (>= 180s threshold) -> auto-stops & saves!
        tracker.processMotionState(
            automotive: false,
            stationary: true,
            walkingOrRunning: true,
            confidence: .high,
            now: t0.addingTimeInterval(325)
        )
        XCTAssertFalse(tracker.isRecording, "Tracker must automatically stop recording after stationary threshold")
        XCTAssertEqual(autoCompletedDrives.count, 1, "Auto-completed drive must be emitted once")
        XCTAssertEqual(store.drives.count, 1, "Completed auto-drive must be persisted to MileageStore")

        // Allow async end geocoding callback to update ledger
        try? await Task.sleep(nanoseconds: 60_000_000)

        let saved = store.drives[0]
        XCTAssertTrue(saved.isAutoDetected)
        XCTAssertGreaterThan(saved.distanceMiles, 1.0)
        XCTAssertEqual(saved.startAddress, "120 Market St, San Francisco")
        XCTAssertEqual(saved.endAddress, "450 Sutter St, San Francisco")
        XCTAssertFalse(saved.startAddress.contains("Auto-Detected Departure"))
        XCTAssertFalse(saved.endAddress.contains("Destination (Logged Live)"))

        // Cooldown guard: noisy indoor motion bounce 10s later must NOT restart an infinite loop
        tracker.processMotionState(
            automotive: true,
            stationary: false,
            walkingOrRunning: false,
            confidence: .medium,
            now: t0.addingTimeInterval(335)
        )
        XCTAssertFalse(tracker.isRecording, "Cooldown must prevent immediate indoor false-trigger loop")
    }

    func testShortDistanceUnder015MilesDiscardedWithoutFabricatingFake12Miles() {
        let store = MileageStore(storageURL: tempStoreURL("shortdiscard"), seedIfEmpty: false)
        let tracker = DriveTrackingService(geocoder: MockReverseGeocoder(shouldFailOffline: true), enableNetworkMonitor: false)
        tracker.bindLedger(store)
        tracker.autoStopStationaryThresholdSeconds = 30.0

        // 1. Manual start & immediate stop (0.0 mi) -> must return nil, NEVER fabricate 1.2 mi!
        tracker.startLiveDrive()
        XCTAssertTrue(tracker.isRecording)
        let zeroResult = tracker.stopAndCreateDrive(vehicleId: nil)
        XCTAssertNil(zeroResult, "0.0 mi accidental tap must return nil instead of fabricating 1.2 mi")
        XCTAssertNotNil(tracker.statusBanner, "UI must inform user that short trip was discarded")
        XCTAssertTrue(store.drives.isEmpty)

        // 2. Auto-detected micro movement (0.09 mi < 0.15 mi) -> auto-stop discards cleanly without saving
        var completedCount = 0
        tracker.configureAutoDetection(enabled: true, sensitivity: .high) { _ in
            completedCount += 1
        }
        let t0 = Date(timeIntervalSince1970: 1_795_100_000)
        let p1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 30.2672, longitude: -97.7431),
            altitude: 150,
            horizontalAccuracy: 6,
            verticalAccuracy: 6,
            course: 90,
            speed: 5.0,
            timestamp: t0
        )
        // ~120 meters (~0.075 mi < 0.15 mi)
        let p2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 30.2672, longitude: -97.7418),
            altitude: 150,
            horizontalAccuracy: 6,
            verticalAccuracy: 6,
            course: 90,
            speed: 5.0,
            timestamp: t0.addingTimeInterval(20)
        )
        tracker.startLiveDrive(autoDetected: true, initialLocation: p1, startDate: t0)
        tracker.processLocationUpdate(p2)
        XCTAssertLessThan(tracker.liveDistanceMiles, 0.15)

        // Stationary for 35s -> triggers auto-stop, discards micro-trip
        let p3 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 30.2672, longitude: -97.7418),
            altitude: 150,
            horizontalAccuracy: 6,
            verticalAccuracy: 6,
            course: 0,
            speed: 0.0,
            timestamp: t0.addingTimeInterval(60)
        )
        tracker.processLocationUpdate(p3)
        XCTAssertFalse(tracker.isRecording)
        XCTAssertEqual(completedCount, 0, "Micro-trip under 0.15 mi must be discarded and never logged")
    }

    func testReverseGeocodingOfflineCoordinateFallbackAndOnlineBackfill() async {
        let store = MileageStore(storageURL: tempStoreURL("geobackfill"), seedIfEmpty: false)
        let offlineGeo = MockReverseGeocoder(shouldFailOffline: true)
        let tracker = DriveTrackingService(geocoder: offlineGeo, enableNetworkMonitor: false)
        tracker.bindLedger(store)

        let t0 = Date(timeIntervalSince1970: 1_795_200_000)
        let startLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 10,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 10.0,
            timestamp: t0
        )
        let endLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7897, longitude: -122.4014),
            altitude: 10,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 90,
            speed: 12.0,
            timestamp: t0.addingTimeInterval(300)
        )

        tracker.startLiveDrive(autoDetected: false, initialLocation: startLoc, startDate: t0)
        tracker.processLocationUpdate(endLoc)
        guard let offlineDrive = tracker.stopAndCreateDrive(vehicleId: nil, endDate: t0.addingTimeInterval(305)) else {
            XCTFail("Expected valid drive record (> 0.15 mi)")
            return
        }
        store.addDrive(offlineDrive)

        // Offline fallback must store exact 4-decimal coordinates, never fake placeholder text
        XCTAssertEqual(store.drives[0].startAddress, "37.7749, -122.4194")
        XCTAssertEqual(store.drives[0].endAddress, "37.7897, -122.4014")
        XCTAssertTrue(DriveTrackingService.isCoordinatePlaceholder(store.drives[0].startAddress))

        // Verify street formatting helper directly
        let formatted = DriveTrackingService.formatAddressParts(
            GeocodeAddressParts(
                subThoroughfare: "120",
                thoroughfare: "Market St",
                subLocality: nil,
                locality: "San Francisco",
                administrativeArea: "CA",
                name: nil
            )
        )
        XCTAssertEqual(formatted, "120 Market St, San Francisco")

        // Simulate network restored -> backfill upgrades coordinate placeholders to real street addresses
        let onlineGeo = MockReverseGeocoder(
            shouldFailOffline: false,
            mapping: [
                "37.7749, -122.4194": "120 Market St, San Francisco",
                "37.7897, -122.4014": "450 Sutter St, San Francisco",
            ]
        )
        tracker.setGeocoderForTesting(onlineGeo)
        await tracker.backfillUnresolvedAddresses(in: store)

        XCTAssertEqual(store.drives[0].startAddress, "120 Market St, San Francisco")
        XCTAssertEqual(store.drives[0].endAddress, "450 Sutter St, San Francisco")
    }
}
