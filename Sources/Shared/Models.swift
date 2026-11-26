import Foundation
import SwiftUI

enum TaxRegionPreset: String, Codable, CaseIterable, Identifiable {
    case usIRS2026
    case ukHMRC
    case auATO
    case caCRA
    case euStandard

    var id: String { rawValue }

    static func defaultForRegion(_ regionIdentifier: String? = Locale.current.region?.identifier) -> TaxRegionPreset {
        let code = (regionIdentifier ?? "").uppercased()
        switch code {
        case "GB":
            return .ukHMRC
        case "AU":
            return .auATO
        case "CA":
            return .caCRA
        case "DE", "FR", "NL", "AT", "CH", "ES", "IT":
            return .euStandard
        default:
            return .usIRS2026
        }
    }

    var flagEmoji: String {
        switch self {
        case .usIRS2026: return "🇺🇸"
        case .ukHMRC: return "🇬🇧"
        case .auATO: return "🇦🇺"
        case .caCRA: return "🇨🇦"
        case .euStandard: return "🇪🇺"
        }
    }

    var displayName: String {
        switch self {
        case .usIRS2026:
            return L10n.t("United States · IRS 2026", "美国 · IRS 2026 分段费率", "美國 · IRS 2026 分段費率")
        case .ukHMRC:
            return L10n.t("United Kingdom · HMRC", "英国 · HMRC 里程津贴", "英國 · HMRC 里程津貼")
        case .auATO:
            return L10n.t("Australia · ATO", "澳大利亚 · ATO 标准费率", "澳洲 · ATO 標準費率")
        case .caCRA:
            return L10n.t("Canada · CRA", "加拿大 · CRA 里程费率", "加拿大 · CRA 里程費率")
        case .euStandard:
            return L10n.t("Europe · Standard", "欧盟 · 标准公里费率", "歐盟 · 標準公里費率")
        }
    }

    var shortName: String {
        switch self {
        case .usIRS2026: return L10n.t("US IRS 2026", "美国 IRS", "美國 IRS")
        case .ukHMRC: return L10n.t("UK HMRC", "英国 HMRC", "英國 HMRC")
        case .auATO: return L10n.t("AU ATO", "澳洲 ATO", "澳洲 ATO")
        case .caCRA: return L10n.t("CA CRA", "加拿大 CRA", "加拿大 CRA")
        case .euStandard: return L10n.t("EU Standard", "欧盟标准", "歐盟標準")
        }
    }

    var authorityShort: String {
        switch self {
        case .usIRS2026: return "IRS"
        case .ukHMRC: return "HMRC"
        case .auATO: return "ATO"
        case .caCRA: return "CRA"
        case .euStandard: return "EU"
        }
    }

    var currencySymbol: String {
        switch self {
        case .usIRS2026: return "$"
        case .ukHMRC: return "£"
        case .auATO: return "A$"
        case .caCRA: return "CA$"
        case .euStandard: return "€"
        }
    }

    var currencyCode: String {
        switch self {
        case .usIRS2026: return "USD"
        case .ukHMRC: return "GBP"
        case .auATO: return "AUD"
        case .caCRA: return "CAD"
        case .euStandard: return "EUR"
        }
    }

    var defaultUnit: DistanceUnit {
        switch self {
        case .usIRS2026, .ukHMRC: return .miles
        case .auATO, .caCRA, .euStandard: return .kilometers
        }
    }

    var rateSummaryBadge: String {
        switch self {
        case .usIRS2026:
            return L10n.t("H1 72.5¢ • H2 76¢/mi", "上半年72.5¢ • 下半年76¢/mi", "上半年72.5¢ • 下半年76¢/mi")
        case .ukHMRC:
            return L10n.t("45p ≤10k mi • 25p after", "前1万mi 45p • 超出25p", "前1萬mi 45p • 超出25p")
        case .auATO:
            return L10n.t("88¢/km (AUD)", "A$0.88 / 公里", "A$0.88 / 公里")
        case .caCRA:
            return L10n.t("72¢ ≤5k km • 66¢ after", "前5千km 72¢ • 超出66¢", "前5千km 72¢ • 超出66¢")
        case .euStandard:
            return L10n.t("€0.30/km Standard", "€0.30 / 公里", "€0.30 / 公里")
        }
    }

    var heroTitle: String {
        switch self {
        case .usIRS2026:
            return L10n.t("2026 IRS TAX DEDUCTION", "2026 年度累计抵税", "2026 年度累計抵稅金額")
        case .ukHMRC:
            return L10n.t("HMRC MILEAGE ALLOWANCE", "英国 HMRC 累计抵税", "英國 HMRC 累計抵稅金額")
        case .auATO:
            return L10n.t("ATO MILEAGE DEDUCTION", "澳洲 ATO 累计抵税", "澳洲 ATO 累計抵稅金額")
        case .caCRA:
            return L10n.t("CRA MILEAGE DEDUCTION", "加拿大 CRA 累计抵税", "加拿大 CRA 累計抵稅金額")
        case .euStandard:
            return L10n.t("BUSINESS MILEAGE DEDUCTION", "欧盟商旅里程抵扣", "歐盟商務里程抵稅金額")
        }
    }

    var pdfHeaderTitle: String {
        switch self {
        case .usIRS2026:
            return L10n.t("IRS SCHEDULE C MILEAGE LOGBOOK", "IRS SCHEDULE C 报税里程总账", "IRS SCHEDULE C 里程報稅總帳")
        case .ukHMRC:
            return L10n.t("HMRC AMAP MILEAGE LOGBOOK", "英国 HMRC 报税里程总账", "英國 HMRC 里程報稅總帳")
        case .auATO:
            return L10n.t("ATO BUSINESS MILEAGE LOGBOOK", "澳洲 ATO 报税里程总账", "澳洲 ATO 里程報稅總帳")
        case .caCRA:
            return L10n.t("CRA AUTOMOBILE MILEAGE LOGBOOK", "加拿大 CRA 报税里程总账", "加拿大 CRA 里程報稅總帳")
        case .euStandard:
            return L10n.t("BUSINESS MILEAGE EXPENSE LOGBOOK", "欧盟商务里程报销总账", "歐盟商務里程報稅總帳")
        }
    }

    var pdfComplianceLabel: String {
        switch self {
        case .usIRS2026: return "IRS Pub 463 Compliant"
        case .ukHMRC: return "HMRC AMAP Record"
        case .auATO: return "ATO Cents-per-km Method"
        case .caCRA: return "CRA Automobile Log"
        case .euStandard: return "EU Standard Expense Log"
        }
    }

    var pdfRateBanner: String {
        switch self {
        case .usIRS2026:
            return L10n.t(
                "2026 Split-Period Standard Rates: Jan–Jun $0.725/mi  |  Jul–Dec $0.760/mi",
                "2026 分段标准费率：1–6月 $0.725/mi  |  7–12月 $0.760/mi",
                "2026 分段標準費率：1–6月 $0.725/mi  |  7–12月 $0.760/mi"
            )
        case .ukHMRC:
            return L10n.t(
                "UK HMRC Approved Mileage Rates: 45p/mi first 10,000 mi  |  25p/mi thereafter",
                "英国 HMRC 核定费率：前 10,000 英里 £0.45/mi  |  超出部分 £0.25/mi",
                "英國 HMRC 核定費率：前 10,000 英里 £0.45/mi  |  超出部分 £0.25/mi"
            )
        case .auATO:
            return L10n.t(
                "Australia ATO Cents-per-Kilometre Rate: A$0.88/km standard deduction",
                "澳大利亚 ATO 标准费率：每公里 A$0.88",
                "澳洲 ATO 標準費率：每公里 A$0.88"
            )
        case .caCRA:
            return L10n.t(
                "Canada CRA Automobile Allowance: CA$0.72/km first 5,000 km  |  CA$0.66/km thereafter",
                "加拿大 CRA 核定费率：前 5,000 公里 CA$0.72/km  |  超出部分 CA$0.66/km",
                "加拿大 CRA 核定費率：前 5,000 公里 CA$0.72/km  |  超出部分 CA$0.66/km"
            )
        case .euStandard:
            return L10n.t(
                "European Standard Business Mileage Allowance: €0.30/km",
                "欧盟标准商务里程津贴：每公里 €0.30",
                "歐盟標準商務里程津貼：每公里 €0.30"
            )
        }
    }

    var fileToken: String {
        switch self {
        case .usIRS2026: return "IRS"
        case .ukHMRC: return "HMRC"
        case .auATO: return "ATO"
        case .caCRA: return "CRA"
        case .euStandard: return "EU"
        }
    }
}

enum DistanceUnit: String, Codable, CaseIterable, Identifiable {
    case miles
    case kilometers

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .miles: return L10n.t("mi", "英里", "英里")
        case .kilometers: return L10n.t("km", "公里", "公里")
        }
    }

    var fullLabel: String {
        switch self {
        case .miles: return L10n.t("Miles (mi)", "英里 (mi)", "英里 (mi)")
        case .kilometers: return L10n.t("Kilometers (km)", "公里 (km)", "公里 (km)")
        }
    }

    static let kmPerMile: Double = 1.609344

    func fromMiles(_ miles: Double) -> Double {
        self == .miles ? miles : miles * Self.kmPerMile
    }

    func toMiles(_ value: Double) -> Double {
        self == .miles ? value : value / Self.kmPerMile
    }
}

enum DriveClassification: String, Codable, CaseIterable, Identifiable {
    case unclassified
    case business
    case personal
    case medical
    case charity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unclassified: return L10n.t("Unclassified", "待分类", "待分類")
        case .business: return L10n.t("Business", "商务抵税", "商務抵稅")
        case .personal: return L10n.t("Personal", "私人行程", "私人行程")
        case .medical: return L10n.t("Medical / Moving", "医疗 / 搬迁", "醫療 / 搬遷")
        case .charity: return L10n.t("Charity", "公益慈善", "公益慈善")
        }
    }

    var shortTag: String {
        switch self {
        case .unclassified: return L10n.t("UNSORTED", "待滑选", "待滑選")
        case .business: return L10n.t("BUSINESS", "商务", "商務")
        case .personal: return L10n.t("PERSONAL", "私人", "私人")
        case .medical: return L10n.t("MEDICAL", "医疗", "醫療")
        case .charity: return L10n.t("CHARITY", "公益", "公益")
        }
    }

    var icon: String {
        switch self {
        case .unclassified: return "rectangle.stack.fill"
        case .business: return "briefcase.fill"
        case .personal: return "house.fill"
        case .medical: return "cross.case.fill"
        case .charity: return "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .unclassified: return MileTheme.amber
        case .business: return MileTheme.emerald
        case .personal: return MileTheme.personalSlate
        case .medical: return MileTheme.medicalBlue
        case .charity: return MileTheme.charityPurple
        }
    }

    var softBackground: Color {
        switch self {
        case .unclassified: return MileTheme.amberSoft
        case .business: return MileTheme.emeraldSoft
        case .personal: return MileTheme.personalSoft
        case .medical: return MileTheme.medicalSoft
        case .charity: return MileTheme.charitySoft
        }
    }

    var isDeductible: Bool {
        switch self {
        case .business, .medical, .charity: return true
        case .personal, .unclassified: return false
        }
    }
}

enum PurposeTag: String, Codable, CaseIterable, Identifiable {
    case deliveryGig
    case clientSite
    case supplyRun
    case propertyShowing
    case errand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deliveryGig: return L10n.t("Delivery / Gig", "配送 / 网约接单", "外送 / 接單")
        case .clientSite: return L10n.t("Client Site", "客户拜访", "客戶拜訪")
        case .supplyRun: return L10n.t("Supply Run", "采购备货", "採購備貨")
        case .propertyShowing: return L10n.t("Property Showing", "带看 / 勘查", "帶看 / 勘查")
        case .errand: return L10n.t("Errand", "日常办事", "日常辦事")
        }
    }

    var icon: String {
        switch self {
        case .deliveryGig: return "shippingbox.fill"
        case .clientSite: return "building.2.fill"
        case .supplyRun: return "wrench.and.screwdriver.fill"
        case .propertyShowing: return "key.fill"
        case .errand: return "bag.fill"
        }
    }
}

enum AutoDriveSensitivity: String, Codable, CaseIterable, Identifiable {
    case low
    case balanced
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return L10n.t("Highway (15+ mph)", "高速模式 (24+ km/h)", "高速模式 (24+ km/h)")
        case .balanced: return L10n.t("Balanced (10+ mph)", "标准模式 (16+ km/h)", "標準模式 (16+ km/h)")
        case .high: return L10n.t("City (6+ mph)", "市区灵敏 (10+ km/h)", "市區靈敏 (10+ km/h)")
        }
    }

    var triggerSpeedMPS: Double {
        switch self {
        case .low: return 6.7       // ~15 mph
        case .balanced: return 4.5  // ~10 mph
        case .high: return 2.7      // ~6 mph
        }
    }
}

struct Vehicle: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var year: Int
    var make: String
    var model: String
    var licensePlate: String
    var startOdometerMiles: Double
    var currentOdometerMiles: Double
    var isDefault: Bool

    var displayName: String {
        "\(year) \(make) \(model)".trimmingCharacters(in: .whitespaces)
    }
}

struct DriveRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var startDate: Date
    var endDate: Date
    var startAddress: String
    var endAddress: String
    var distanceMiles: Double
    var classification: DriveClassification
    var purpose: PurposeTag
    var vehicleId: UUID?
    var odometerStartMiles: Double?
    var odometerEndMiles: Double?
    var isAutoDetected: Bool
    var notes: String
    var startLatitude: Double? = nil
    var startLongitude: Double? = nil
    var endLatitude: Double? = nil
    var endLongitude: Double? = nil
}

struct DriverSettings: Codable, Equatable {
    var driverName: String
    var taxYear: Int
    var taxRegion: TaxRegionPreset
    var distanceUnit: DistanceUnit
    var autoDriveEnabled: Bool
    var autoDriveSensitivity: AutoDriveSensitivity
    var useCustomRate: Bool
    var customRatePerUnit: Double
    var currencySymbol: String

    enum CodingKeys: String, CodingKey {
        case driverName
        case taxYear
        case taxRegion
        case distanceUnit
        case autoDriveEnabled
        case autoDriveSensitivity
        case useCustomRate
        case customRatePerUnit
        case currencySymbol
    }

    init(
        driverName: String,
        taxYear: Int,
        taxRegion: TaxRegionPreset = .usIRS2026,
        distanceUnit: DistanceUnit,
        autoDriveEnabled: Bool,
        autoDriveSensitivity: AutoDriveSensitivity,
        useCustomRate: Bool,
        customRatePerUnit: Double,
        currencySymbol: String
    ) {
        self.driverName = driverName
        self.taxYear = taxYear
        self.taxRegion = taxRegion
        self.distanceUnit = distanceUnit
        self.autoDriveEnabled = autoDriveEnabled
        self.autoDriveSensitivity = autoDriveSensitivity
        self.useCustomRate = useCustomRate
        self.customRatePerUnit = customRatePerUnit
        self.currencySymbol = currencySymbol
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        driverName = try c.decode(String.self, forKey: .driverName)
        taxYear = try c.decode(Int.self, forKey: .taxYear)
        taxRegion = try c.decodeIfPresent(TaxRegionPreset.self, forKey: .taxRegion) ?? .usIRS2026
        distanceUnit = try c.decode(DistanceUnit.self, forKey: .distanceUnit)
        autoDriveEnabled = try c.decode(Bool.self, forKey: .autoDriveEnabled)
        autoDriveSensitivity = try c.decode(AutoDriveSensitivity.self, forKey: .autoDriveSensitivity)
        useCustomRate = try c.decode(Bool.self, forKey: .useCustomRate)
        customRatePerUnit = try c.decode(Double.self, forKey: .customRatePerUnit)
        currencySymbol = try c.decode(String.self, forKey: .currencySymbol)
    }

    mutating func applyTaxRegion(_ preset: TaxRegionPreset) {
        taxRegion = preset
        distanceUnit = preset.defaultUnit
        currencySymbol = preset.currencySymbol
        switch preset {
        case .usIRS2026: customRatePerUnit = IRSRateEngine.business2026H2
        case .ukHMRC: customRatePerUnit = IRSRateEngine.ukHMRCTier1
        case .auATO: customRatePerUnit = IRSRateEngine.auATORatePerKm
        case .caCRA: customRatePerUnit = IRSRateEngine.caCRATier1PerKm
        case .euStandard: customRatePerUnit = IRSRateEngine.euStandardPerKm
        }
    }

    static func defaultSettings(for regionIdentifier: String? = Locale.current.region?.identifier) -> DriverSettings {
        let region = TaxRegionPreset.defaultForRegion(regionIdentifier)
        var settings = DriverSettings(
            driverName: L10n.t("Alex Rivera", "陈明远", "陳明遠"),
            taxYear: 2026,
            taxRegion: region,
            distanceUnit: region.defaultUnit,
            autoDriveEnabled: true,
            autoDriveSensitivity: .balanced,
            useCustomRate: false,
            customRatePerUnit: 0.76,
            currencySymbol: region.currencySymbol
        )
        settings.applyTaxRegion(region)
        return settings
    }
}

struct MileageBackupSnapshot: Codable {
    var schemaVersion: Int = 2
    var exportedAt: Date = Date()
    var settings: DriverSettings
    var vehicles: [Vehicle]
    var drives: [DriveRecord]
}
