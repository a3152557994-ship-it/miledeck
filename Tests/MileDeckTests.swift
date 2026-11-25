import PDFKit
import XCTest
@testable import MileDeck

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

    func test2026IRSSplitPeriodRatesH1vsH2() {
        let settings = DriverSettings.defaultSettings()

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

        let h1Drive = DriveRecord(
            startDate: h1End,
            endDate: h1End.addingTimeInterval(1800),
            startAddress: "A",
            endAddress: "B",
            distanceMiles: 100.0,
            classification: .business,
            purpose: .clientSite,
            vehicleId: nil,
            odometerStartMiles: nil,
            odometerEndMiles: nil,
            isAutoDetected: true,
            notes: ""
        )
        let h2Drive = DriveRecord(
            startDate: h2Start,
            endDate: h2Start.addingTimeInterval(1800),
            startAddress: "C",
            endAddress: "D",
            distanceMiles: 100.0,
            classification: .business,
            purpose: .deliveryGig,
            vehicleId: nil,
            odometerStartMiles: nil,
            odometerEndMiles: nil,
            isAutoDetected: true,
            notes: ""
        )

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

    func testCustomPerKmRateAndDistanceConversion() {
        var settings = DriverSettings.defaultSettings()
        settings.distanceUnit = .kilometers
        settings.useCustomRate = true
        settings.customRatePerUnit = 0.50 // $0.50 per km

        let drive = DriveRecord(
            startDate: makeDate(2026, 8, 10),
            endDate: makeDate(2026, 8, 10).addingTimeInterval(1200),
            startAddress: "Office",
            endAddress: "Airport",
            distanceMiles: 10.0, // 16.09344 km -> * 0.50 = 8.05
            classification: .business,
            purpose: .clientSite,
            vehicleId: nil,
            odometerStartMiles: nil,
            odometerEndMiles: nil,
            isAutoDetected: false,
            notes: ""
        )
        XCTAssertEqual(IRSRateEngine.deduction(for: drive, settings: settings), 8.05, accuracy: 0.01)
        XCTAssertEqual(DistanceUnit.kilometers.fromMiles(10.0), 16.09344, accuracy: 0.001)
        XCTAssertEqual(DistanceUnit.kilometers.toMiles(16.09344), 10.0, accuracy: 0.001)
    }

    func testSwipeClassificationAndUndo() {
        let store = MileageStore(storageURL: tempStoreURL("swipe"), seedIfEmpty: true)
        XCTAssertEqual(store.unclassifiedDrives.count, 3)
        let initialYTD = store.ytdTaxDeduction

        let top = store.unclassifiedDrives[0]
        let expectedGain = IRSRateEngine.deduction(for: top, settings: store.settings, includePotentialForUnclassified: true)
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
        let csv = store.exportIRSCSV()
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 1 + store.drives.count)
        XCTAssertTrue(lines[0].contains("Period,Classification,Purpose"))
        XCTAssertTrue(csv.contains("2026-H1 (Jan-Jun)"))
        XCTAssertTrue(csv.contains("2026-H2 (Jul-Dec)"))
    }

    func testJSONBackupAndRestoreRoundTrip() throws {
        let url1 = tempStoreURL("backup1")
        let url2 = tempStoreURL("backup2")
        let source = MileageStore(storageURL: url1, seedIfEmpty: true)
        source.settings.driverName = "Taylor Morgan"
        source.classifyDrive(source.unclassifiedDrives[0].id, as: .business)

        let jsonData = try source.exportJSONBackupData()
        XCTAssertGreaterThan(jsonData.count, 500)

        let target = MileageStore(storageURL: url2, seedIfEmpty: false)
        XCTAssertTrue(target.drives.isEmpty)

        try target.restoreJSONBackupData(jsonData)
        XCTAssertEqual(target.settings.driverName, "Taylor Morgan")
        XCTAssertEqual(target.drives.count, source.drives.count)
        XCTAssertEqual(target.vehicles.count, source.vehicles.count)
        XCTAssertEqual(target.ytdTaxDeduction, source.ytdTaxDeduction, accuracy: 0.01)
    }
}
