import Foundation
import SwiftUI

struct MonthlyDeductionStat: Identifiable, Equatable {
    let id: Int // month 1...12
    let month: Int
    let shortName: String
    let businessMiles: Double
    let deduction: Double
    let isH2: Bool
}

@MainActor
final class MileageStore: ObservableObject {
    @Published var settings: DriverSettings {
        didSet { save() }
    }
    @Published var vehicles: [Vehicle] {
        didSet { save() }
    }
    @Published var drives: [DriveRecord] {
        didSet { save() }
    }
    @Published var lastSwipedSnapshot: (driveId: UUID, previousClassification: DriveClassification, previousPurpose: PurposeTag)?

    private let fileURL: URL

    init(storageURL: URL? = nil, seedIfEmpty: Bool = true) {
        if let custom = storageURL {
            self.fileURL = custom
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = docs.appendingPathComponent("miledeck_ledger.json")
        }

        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder.mileDeck.decode(MileageBackupSnapshot.self, from: data) {
            self.settings = decoded.settings
            self.vehicles = decoded.vehicles
            self.drives = decoded.drives.sorted { $0.startDate > $1.startDate }
        } else {
            self.settings = DriverSettings.defaultSettings()
            if seedIfEmpty {
                let seeded = Self.makeStarterData()
                self.vehicles = seeded.vehicles
                self.drives = seeded.drives
                save()
            } else {
                self.vehicles = []
                self.drives = []
            }
        }
    }

    // MARK: - Aggregates
    var unclassifiedDrives: [DriveRecord] {
        drives.filter { $0.classification == .unclassified }.sorted { $0.startDate > $1.startDate }
    }

    var classifiedDrives: [DriveRecord] {
        drives.filter { $0.classification != .unclassified }.sorted { $0.startDate > $1.startDate }
    }

    var deductibleDrives: [DriveRecord] {
        drives.filter { $0.classification.isDeductible }.sorted { $0.startDate > $1.startDate }
    }

    var defaultVehicle: Vehicle? {
        vehicles.first(where: { $0.isDefault }) ?? vehicles.first
    }

    var ytdBusinessMiles: Double {
        drives.filter { $0.classification == .business }.reduce(0) { $0 + $1.distanceMiles }
    }

    var ytdDeductibleMiles: Double {
        deductibleDrives.reduce(0) { $0 + $1.distanceMiles }
    }

    var ytdTaxDeduction: Double {
        IRSRateEngine.roundCents(deductibleDrives.reduce(0) { $0 + IRSRateEngine.deduction(for: $1, settings: settings) })
    }

    var pendingPotentialDeduction: Double {
        IRSRateEngine.roundCents(unclassifiedDrives.reduce(0) {
            $0 + IRSRateEngine.deduction(for: $1, settings: settings, includePotentialForUnclassified: true)
        })
    }

    var h1BusinessMiles: Double {
        drives.filter {
            $0.classification == .business && IRSRateEngine.period(for: $0.startDate) == .h1_2026
        }.reduce(0) { $0 + $1.distanceMiles }
    }

    var h1BusinessDeduction: Double {
        IRSRateEngine.roundCents(drives.filter {
            $0.classification == .business && IRSRateEngine.period(for: $0.startDate) == .h1_2026
        }.reduce(0) { $0 + IRSRateEngine.deduction(for: $1, settings: settings) })
    }

    var h2BusinessMiles: Double {
        drives.filter {
            $0.classification == .business && IRSRateEngine.period(for: $0.startDate) == .h2_2026
        }.reduce(0) { $0 + $1.distanceMiles }
    }

    var h2BusinessDeduction: Double {
        IRSRateEngine.roundCents(drives.filter {
            $0.classification == .business && IRSRateEngine.period(for: $0.startDate) == .h2_2026
        }.reduce(0) { $0 + IRSRateEngine.deduction(for: $1, settings: settings) })
    }

    func monthlyStats(for year: Int = 2026) -> [MonthlyDeductionStat] {
        let cal = Calendar(identifier: .gregorian)
        let enMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let zhMonths = ["1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月"]

        return (1...12).map { m in
            let matching = deductibleDrives.filter {
                let c = cal.dateComponents([.year, .month], from: $0.startDate)
                return c.year == year && c.month == m
            }
            let miles = matching.reduce(0.0) { $0 + $1.distanceMiles }
            let ded = IRSRateEngine.roundCents(matching.reduce(0.0) { $0 + IRSRateEngine.deduction(for: $1, settings: settings) })
            return MonthlyDeductionStat(
                id: m,
                month: m,
                shortName: L10n.isChinese ? zhMonths[m - 1] : enMonths[m - 1],
                businessMiles: miles,
                deduction: ded,
                isH2: m >= 7
            )
        }
    }

    func vehicleName(for id: UUID?) -> String {
        guard let id, let v = vehicles.first(where: { $0.id == id }) else {
            return defaultVehicle?.displayName ?? L10n.t("Primary Vehicle", "主力车辆")
        }
        return v.displayName
    }

    func milesLogged(for vehicleId: UUID, businessOnly: Bool = false) -> Double {
        drives.filter {
            $0.vehicleId == vehicleId && (!businessOnly || $0.classification.isDeductible)
        }.reduce(0) { $0 + $1.distanceMiles }
    }

    // MARK: - Mutations
    func classifyDrive(_ id: UUID, as classification: DriveClassification, purpose: PurposeTag? = nil) {
        guard let idx = drives.firstIndex(where: { $0.id == id }) else { return }
        lastSwipedSnapshot = (id, drives[idx].classification, drives[idx].purpose)
        drives[idx].classification = classification
        if let purpose {
            drives[idx].purpose = purpose
        }
    }

    func undoLastSwipe() {
        guard let snap = lastSwipedSnapshot,
              let idx = drives.firstIndex(where: { $0.id == snap.driveId }) else { return }
        drives[idx].classification = snap.previousClassification
        drives[idx].purpose = snap.previousPurpose
        lastSwipedSnapshot = nil
    }

    func addDrive(_ drive: DriveRecord) {
        var record = drive
        if record.vehicleId == nil {
            record.vehicleId = defaultVehicle?.id
        }
        if let vid = record.vehicleId, let vIdx = vehicles.firstIndex(where: { $0.id == vid }) {
            if record.odometerStartMiles == nil {
                record.odometerStartMiles = vehicles[vIdx].currentOdometerMiles
            }
            if record.odometerEndMiles == nil {
                record.odometerEndMiles = vehicles[vIdx].currentOdometerMiles + record.distanceMiles
            }
            vehicles[vIdx].currentOdometerMiles = max(
                vehicles[vIdx].currentOdometerMiles,
                (record.odometerEndMiles ?? (vehicles[vIdx].currentOdometerMiles + record.distanceMiles))
            )
        }
        drives.insert(record, at: 0)
        drives.sort { $0.startDate > $1.startDate }
    }

    func updateDrive(_ drive: DriveRecord) {
        if let idx = drives.firstIndex(where: { $0.id == drive.id }) {
            drives[idx] = drive
            drives.sort { $0.startDate > $1.startDate }
        } else {
            addDrive(drive)
        }
    }

    func deleteDrive(_ id: UUID) {
        drives.removeAll { $0.id == id }
    }

    func saveVehicle(_ vehicle: Vehicle) {
        if vehicle.isDefault {
            for i in vehicles.indices {
                vehicles[i].isDefault = false
            }
        }
        if let idx = vehicles.firstIndex(where: { $0.id == vehicle.id }) {
            vehicles[idx] = vehicle
        } else {
            var v = vehicle
            if vehicles.isEmpty { v.isDefault = true }
            vehicles.append(v)
        }
    }

    func setDefaultVehicle(_ id: UUID) {
        for i in vehicles.indices {
            vehicles[i].isDefault = (vehicles[i].id == id)
        }
    }

    func updateVehicleOdometer(_ id: UUID, currentMiles: Double) {
        guard let idx = vehicles.firstIndex(where: { $0.id == id }) else { return }
        vehicles[idx].currentOdometerMiles = max(vehicles[idx].startOdometerMiles, currentMiles)
    }

    func deleteVehicle(_ id: UUID) {
        vehicles.removeAll { $0.id == id }
        if !vehicles.isEmpty && !vehicles.contains(where: { $0.isDefault }) {
            vehicles[0].isDefault = true
        }
    }

    // MARK: - CSV & JSON Export / Import
    func exportIRSCSV() -> String {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm"

        var rows: [String] = [
            "Date,Period,Classification,Purpose,StartLocation,EndLocation,Vehicle,OdometerStartMi,OdometerEndMi,DistanceMiles,DistanceKm,RateApplied,DeductionUSD,Notes"
        ]

        let sorted = drives.sorted { $0.startDate < $1.startDate }
        for d in sorted {
            let period = IRSRateEngine.period(for: d.startDate).csvLabel
            let km = d.distanceMiles * DistanceUnit.kmPerMile
            let ded = IRSRateEngine.deduction(for: d, settings: settings)
            let rate = IRSRateEngine.effectiveRateLabel(for: d, settings: settings)
            let odoStart = d.odometerStartMiles.map { String(format: "%.1f", $0) } ?? ""
            let odoEnd = d.odometerEndMiles.map { String(format: "%.1f", $0) } ?? ""
            let fields = [
                df.string(from: d.startDate),
                period,
                d.classification.rawValue.capitalized,
                d.purpose.title,
                d.startAddress,
                d.endAddress,
                vehicleName(for: d.vehicleId),
                odoStart,
                odoEnd,
                String(format: "%.2f", d.distanceMiles),
                String(format: "%.2f", km),
                rate,
                String(format: "%.2f", ded),
                d.notes,
            ]
            rows.append(fields.map(Self.csvEscape).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    func exportJSONBackupData() throws -> Data {
        let snap = MileageBackupSnapshot(settings: settings, vehicles: vehicles, drives: drives)
        return try JSONEncoder.mileDeckPretty.encode(snap)
    }

    func restoreJSONBackupData(_ data: Data) throws {
        let decoded = try JSONDecoder.mileDeck.decode(MileageBackupSnapshot.self, from: data)
        self.settings = decoded.settings
        self.vehicles = decoded.vehicles
        self.drives = decoded.drives.sorted { $0.startDate > $1.startDate }
        save()
    }

    private static func csvEscape(_ raw: String) -> String {
        if raw.contains(",") || raw.contains("\"") || raw.contains("\n") {
            return "\"\(raw.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return raw
    }

    private func save() {
        let snap = MileageBackupSnapshot(settings: settings, vehicles: vehicles, drives: drives)
        if let data = try? JSONEncoder.mileDeck.encode(snap) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    // MARK: - Realistic 2026 Starter Data (EN + ZH, 6 drives: 3 unclassified + 3 classified spanning H1 72.5¢ & H2 76¢)
    static func makeStarterData() -> (vehicles: [Vehicle], drives: [DriveRecord]) {
        let isCN = L10n.isChinese
        let v1 = Vehicle(
            year: 2023,
            make: isCN ? "丰田" : "Toyota",
            model: isCN ? "卡罗拉双擎" : "Prius LE",
            licensePlate: isCN ? "粤B·D2841" : "TX-7M248",
            startOdometerMiles: 24180,
            currentOdometerMiles: 28940,
            isDefault: true
        )
        let v2 = Vehicle(
            year: 2022,
            make: isCN ? "比亚迪" : "Ford",
            model: isCN ? "宋 PLUS DM-i" : "Maverick XLT",
            licensePlate: isCN ? "粤B·E9106" : "TX-9K411",
            startOdometerMiles: 18400,
            currentOdometerMiles: 20215,
            isDefault: false
        )

        func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
            var comps = DateComponents()
            comps.calendar = Calendar(identifier: .gregorian)
            comps.year = year
            comps.month = month
            comps.day = day
            comps.hour = hour
            comps.minute = minute
            return comps.date ?? Date()
        }

        // 3 Unclassified drives (H2 2026 @ $0.76/mi) ready to swipe on the Deck!
        let d1Start = makeDate(2026, 11, 24, 14, 15)
        let d1 = DriveRecord(
            startDate: d1Start,
            endDate: d1Start.addingTimeInterval(34 * 60),
            startAddress: isCN ? "南山科技园南区配送站" : "Downtown Market Hub, Austin",
            endAddress: isCN ? "前海自贸时代广场 B 座" : "Westlake Tech Park, Suite 400",
            distanceMiles: 18.5,
            classification: .unclassified,
            purpose: .deliveryGig,
            vehicleId: v1.id,
            odometerStartMiles: 28921.5,
            odometerEndMiles: 28940.0,
            isAutoDetected: true,
            notes: isCN ? "午高峰多单连送回路" : "Afternoon multi-drop delivery loop"
        )

        let d2Start = makeDate(2026, 11, 23, 9, 40)
        let d2 = DriveRecord(
            startDate: d2Start,
            endDate: d2Start.addingTimeInterval(42 * 60),
            startAddress: isCN ? "宝安国际五金建材城" : "Oakridge Supply Depot",
            endAddress: isCN ? "蛇口海上世界工地现场" : "Cedar Creek Remodel Site",
            distanceMiles: 24.2,
            classification: .unclassified,
            purpose: .supplyRun,
            vehicleId: v2.id,
            odometerStartMiles: 20190.8,
            odometerEndMiles: 20215.0,
            isAutoDetected: true,
            notes: isCN ? "拉铜阀配件与电线材料" : "Picked up plumbing valves & framing lumber"
        )

        let d3Start = makeDate(2026, 11, 22, 18, 20)
        let d3 = DriveRecord(
            startDate: d3Start,
            endDate: d3Start.addingTimeInterval(16 * 60),
            startAddress: isCN ? "后海滨城小区车库" : "Home Garage, South Lamar",
            endAddress: isCN ? "海岸城地下停车场" : "Northside Fitness & Grocery",
            distanceMiles: 6.4,
            classification: .unclassified,
            purpose: .errand,
            vehicleId: v1.id,
            odometerStartMiles: 28915.1,
            odometerEndMiles: 28921.5,
            isAutoDetected: true,
            notes: isCN ? "晚间健身采买" : "Evening gym and grocery run"
        )

        // 3 Classified drives spanning H1 ($0.725/mi) and H2 ($0.76/mi) 2026!
        let d4Start = makeDate(2026, 10, 18, 10, 5)
        let d4 = DriveRecord(
            startDate: d4Start,
            endDate: d4Start.addingTimeInterval(78 * 60),
            startAddress: isCN ? "福田中心商务区出发点" : "East Austin Fulfillment Center",
            endAddress: isCN ? "龙华北站及高新园沿线配送" : "Domain Northside & Cedar Park Route",
            distanceMiles: 64.5,
            classification: .business,
            purpose: .deliveryGig,
            vehicleId: v1.id,
            odometerStartMiles: 28850.6,
            odometerEndMiles: 28915.1,
            isAutoDetected: true,
            notes: isCN ? "2026 下半年 76¢ 费率档全天派送" : "Full morning gig shift (H2 76¢ IRS rate)"
        )

        let d5Start = makeDate(2026, 5, 14, 13, 20)
        let d5 = DriveRecord(
            startDate: d5Start,
            endDate: d5Start.addingTimeInterval(68 * 60),
            startAddress: isCN ? "南山工作室" : "South Congress Office",
            endAddress: isCN ? "东莞松山湖客户验厂" : "Round Rock & Georgetown Client Audits",
            distanceMiles: 58.0,
            classification: .business,
            purpose: .clientSite,
            vehicleId: v1.id,
            odometerStartMiles: 26410.0,
            odometerEndMiles: 26468.0,
            isAutoDetected: true,
            notes: isCN ? "2026 上半年 72.5¢ 费率档客户巡检" : "Quarterly client site inspection (H1 72.5¢ IRS rate)"
        )

        let d6Start = makeDate(2026, 3, 22, 11, 10)
        let d6 = DriveRecord(
            startDate: d6Start,
            endDate: d6Start.addingTimeInterval(24 * 60),
            startAddress: isCN ? "后海滨城小区" : "Home Garage, South Lamar",
            endAddress: isCN ? "深圳湾公园西段" : "Zilker Park Botanical Gardens",
            distanceMiles: 11.2,
            classification: .personal,
            purpose: .errand,
            vehicleId: v2.id,
            odometerStartMiles: 19402.0,
            odometerEndMiles: 19413.2,
            isAutoDetected: false,
            notes: isCN ? "周末家庭出游（不计入抵税）" : "Weekend family outing (non-deductible)"
        )

        return ([v1, v2], [d1, d2, d3, d4, d5, d6])
    }
}

extension JSONEncoder {
    static var mileDeck: JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    static var mileDeckPretty: JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }
}

extension JSONDecoder {
    static var mileDeck: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }
}
