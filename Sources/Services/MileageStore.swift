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

    var deductionsByDriveID: [UUID: Double] {
        IRSRateEngine.deductionsByDriveID(for: drives, settings: settings)
    }

    var ytdTaxDeduction: Double {
        let map = deductionsByDriveID
        return IRSRateEngine.roundCents(deductibleDrives.reduce(0) { $0 + (map[$1.id] ?? 0) })
    }

    var formattedYTDDeduction: String {
        IRSRateEngine.formatMoney(ytdTaxDeduction, symbol: settings.currencySymbol)
    }

    var pendingPotentialDeduction: Double {
        var runningPrior = ytdDeductibleMiles
        var total = 0.0
        for d in unclassifiedDrives.sorted(by: { $0.startDate < $1.startDate }) {
            total += IRSRateEngine.deduction(
                for: d,
                settings: settings,
                includePotentialForUnclassified: true,
                priorDeductibleMilesInYear: runningPrior
            )
            runningPrior += max(0, d.distanceMiles)
        }
        return IRSRateEngine.roundCents(total)
    }

    var h1BusinessMiles: Double {
        drives.filter {
            $0.classification == .business && IRSRateEngine.period(for: $0.startDate) == .h1_2026
        }.reduce(0) { $0 + $1.distanceMiles }
    }

    var h1BusinessDeduction: Double {
        let map = deductionsByDriveID
        return IRSRateEngine.roundCents(drives.filter {
            $0.classification == .business && IRSRateEngine.period(for: $0.startDate) == .h1_2026
        }.reduce(0) { $0 + (map[$1.id] ?? 0) })
    }

    var h2BusinessMiles: Double {
        drives.filter {
            $0.classification == .business && IRSRateEngine.period(for: $0.startDate) == .h2_2026
        }.reduce(0) { $0 + $1.distanceMiles }
    }

    var h2BusinessDeduction: Double {
        let map = deductionsByDriveID
        return IRSRateEngine.roundCents(drives.filter {
            $0.classification == .business && IRSRateEngine.period(for: $0.startDate) == .h2_2026
        }.reduce(0) { $0 + (map[$1.id] ?? 0) })
    }

    func monthlyStats(for year: Int = 2026) -> [MonthlyDeductionStat] {
        let cal = Calendar(identifier: .gregorian)
        let enMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let zhMonths = ["1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月"]
        let map = deductionsByDriveID

        return (1...12).map { m in
            let matching = deductibleDrives.filter {
                let c = cal.dateComponents([.year, .month], from: $0.startDate)
                return c.year == year && c.month == m
            }
            let miles = matching.reduce(0.0) { $0 + $1.distanceMiles }
            let ded = IRSRateEngine.roundCents(matching.reduce(0.0) { $0 + (map[$1.id] ?? 0) })
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
            return defaultVehicle?.displayName ?? L10n.t("Primary Vehicle", "主力车辆", "主力車輛")
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

    func updateDriveAddresses(id: UUID, startAddress: String? = nil, endAddress: String? = nil) {
        guard let idx = drives.firstIndex(where: { $0.id == id }) else { return }
        var updated = drives[idx]
        var changed = false
        if let startAddress, !startAddress.isEmpty, updated.startAddress != startAddress {
            updated.startAddress = startAddress
            changed = true
        }
        if let endAddress, !endAddress.isEmpty, updated.endAddress != endAddress {
            updated.endAddress = endAddress
            changed = true
        }
        if changed {
            drives[idx] = updated
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

        let deductionCol = "Deduction\(settings.taxRegion.currencyCode)"
        var rows: [String] = [
            "Date,Period,Classification,Purpose,StartLocation,EndLocation,Vehicle,OdometerStartMi,OdometerEndMi,DistanceMiles,DistanceKm,RateApplied,\(deductionCol),Notes"
        ]

        let cal = Calendar(identifier: .gregorian)
        var priorMilesByYear: [Int: Double] = [:]
        let sorted = drives.sorted { $0.startDate < $1.startDate }
        for d in sorted {
            let year = cal.component(.year, from: d.startDate)
            let prior = priorMilesByYear[year, default: 0]
            let period = settings.taxRegion == .usIRS2026
                ? IRSRateEngine.period(for: d.startDate).csvLabel
                : "\(year)-\(settings.taxRegion.fileToken)"
            let km = d.distanceMiles * DistanceUnit.kmPerMile
            let ded = IRSRateEngine.deduction(for: d, settings: settings, priorDeductibleMilesInYear: prior)
            let rate = IRSRateEngine.effectiveRateLabel(for: d, settings: settings, priorDeductibleMilesInYear: prior)
            if d.classification.isDeductible {
                priorMilesByYear[year] = prior + max(0, d.distanceMiles)
            }
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

    // MARK: - Realistic 2026 Starter Data (EN + ZH-Hans + ZH-Hant, 6 drives)
    static func makeStarterData() -> (vehicles: [Vehicle], drives: [DriveRecord]) {
        let v1 = Vehicle(
            year: 2023,
            make: L10n.t("Toyota", "丰田", "豐田"),
            model: L10n.t("Prius LE", "卡罗拉双擎", "Prius 油電"),
            licensePlate: L10n.t("TX-7M248", "粤B·D2841", "BHK-2841"),
            startOdometerMiles: 24180,
            currentOdometerMiles: 28940,
            isDefault: true
        )
        let v2 = Vehicle(
            year: 2022,
            make: L10n.t("Ford", "比亚迪", "本田"),
            model: L10n.t("Maverick XLT", "宋 PLUS DM-i", "CR-V"),
            licensePlate: L10n.t("TX-9K411", "粤B·E9106", "BNK-9106"),
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

        // 3 Unclassified drives (H2 2026) ready to swipe on the Deck!
        let d1Start = makeDate(2026, 11, 24, 14, 15)
        let d1 = DriveRecord(
            startDate: d1Start,
            endDate: d1Start.addingTimeInterval(34 * 60),
            startAddress: L10n.t("Downtown Market Hub, Austin", "南山科技园南区配送站", "信義商業中心配送點"),
            endAddress: L10n.t("Westlake Tech Park, Suite 400", "前海自贸时代广场 B 座", "內湖科學園區 B 棟"),
            distanceMiles: 18.5,
            classification: .unclassified,
            purpose: .deliveryGig,
            vehicleId: v1.id,
            odometerStartMiles: 28921.5,
            odometerEndMiles: 28940.0,
            isAutoDetected: true,
            notes: L10n.t("Afternoon multi-drop delivery loop", "午高峰多单连送回路", "午間多點外送路線")
        )

        let d2Start = makeDate(2026, 11, 23, 9, 40)
        let d2 = DriveRecord(
            startDate: d2Start,
            endDate: d2Start.addingTimeInterval(42 * 60),
            startAddress: L10n.t("Oakridge Supply Depot", "宝安国际五金建材城", "新莊五金建材中心"),
            endAddress: L10n.t("Cedar Creek Remodel Site", "蛇口海上世界工地现场", "大安區裝修案場"),
            distanceMiles: 24.2,
            classification: .unclassified,
            purpose: .supplyRun,
            vehicleId: v2.id,
            odometerStartMiles: 20190.8,
            odometerEndMiles: 20215.0,
            isAutoDetected: true,
            notes: L10n.t("Picked up plumbing valves & framing lumber", "拉铜阀配件与电线材料", "採購管線零件與線材")
        )

        let d3Start = makeDate(2026, 11, 22, 18, 20)
        let d3 = DriveRecord(
            startDate: d3Start,
            endDate: d3Start.addingTimeInterval(16 * 60),
            startAddress: L10n.t("Home Garage, South Lamar", "后海滨城小区车库", "住家社區停車場"),
            endAddress: L10n.t("Northside Fitness & Grocery", "海岸城地下停车场", "社區超市與健身房"),
            distanceMiles: 6.4,
            classification: .unclassified,
            purpose: .errand,
            vehicleId: v1.id,
            odometerStartMiles: 28915.1,
            odometerEndMiles: 28921.5,
            isAutoDetected: true,
            notes: L10n.t("Evening gym and grocery run", "晚间健身采买", "晚間健身與日常採買")
        )

        // 3 Classified drives spanning H1 ($0.725/mi) and H2 ($0.76/mi) 2026!
        let d4Start = makeDate(2026, 10, 18, 10, 5)
        let d4 = DriveRecord(
            startDate: d4Start,
            endDate: d4Start.addingTimeInterval(78 * 60),
            startAddress: L10n.t("East Austin Fulfillment Center", "福田中心商务区出发点", "南港轉運物流中心"),
            endAddress: L10n.t("Domain Northside & Cedar Park Route", "龙华北站及高新园沿线配送", "板橋與中和沿線派送"),
            distanceMiles: 64.5,
            classification: .business,
            purpose: .deliveryGig,
            vehicleId: v1.id,
            odometerStartMiles: 28850.6,
            odometerEndMiles: 28915.1,
            isAutoDetected: true,
            notes: L10n.t("Full morning gig shift (H2 76¢ IRS rate)", "2026 下半年 76¢ 费率档全天派送", "2026 下半年 76¢ 費率檔全天派送")
        )

        let d5Start = makeDate(2026, 5, 14, 13, 20)
        let d5 = DriveRecord(
            startDate: d5Start,
            endDate: d5Start.addingTimeInterval(68 * 60),
            startAddress: L10n.t("South Congress Office", "南山工作室", "中山區工作室"),
            endAddress: L10n.t("Round Rock & Georgetown Client Audits", "东莞松山湖客户验厂", "新竹園區客戶駐點巡檢"),
            distanceMiles: 58.0,
            classification: .business,
            purpose: .clientSite,
            vehicleId: v1.id,
            odometerStartMiles: 26410.0,
            odometerEndMiles: 26468.0,
            isAutoDetected: true,
            notes: L10n.t("Quarterly client site inspection (H1 72.5¢ IRS rate)", "2026 上半年 72.5¢ 费率档客户巡检", "2026 上半年 72.5¢ 費率檔客戶巡檢")
        )

        let d6Start = makeDate(2026, 3, 22, 11, 10)
        let d6 = DriveRecord(
            startDate: d6Start,
            endDate: d6Start.addingTimeInterval(24 * 60),
            startAddress: L10n.t("Home Garage, South Lamar", "后海滨城小区", "住家社區"),
            endAddress: L10n.t("Zilker Park Botanical Gardens", "深圳湾公园西段", "河濱公園步道"),
            distanceMiles: 11.2,
            classification: .personal,
            purpose: .errand,
            vehicleId: v2.id,
            odometerStartMiles: 19402.0,
            odometerEndMiles: 19413.2,
            isAutoDetected: false,
            notes: L10n.t("Weekend family outing (non-deductible)", "周末家庭出游（不计入抵税）", "週末家庭出遊（不計入抵稅）")
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
