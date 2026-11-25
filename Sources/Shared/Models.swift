import Foundation
import SwiftUI

enum DistanceUnit: String, Codable, CaseIterable, Identifiable {
    case miles
    case kilometers

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .miles: return L10n.t("mi", "英里")
        case .kilometers: return L10n.t("km", "公里")
        }
    }

    var fullLabel: String {
        switch self {
        case .miles: return L10n.t("Miles (mi)", "英里 (mi)")
        case .kilometers: return L10n.t("Kilometers (km)", "公里 (km)")
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
        case .unclassified: return L10n.t("Unclassified", "待分类")
        case .business: return L10n.t("Business", "商务抵税")
        case .personal: return L10n.t("Personal", "私人行程")
        case .medical: return L10n.t("Medical / Moving", "医疗 / 搬迁")
        case .charity: return L10n.t("Charity", "公益慈善")
        }
    }

    var shortTag: String {
        switch self {
        case .unclassified: return L10n.t("UNSORTED", "待滑选")
        case .business: return L10n.t("BUSINESS", "商务")
        case .personal: return L10n.t("PERSONAL", "私人")
        case .medical: return L10n.t("MEDICAL", "医疗")
        case .charity: return L10n.t("CHARITY", "公益")
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
        case .deliveryGig: return L10n.t("Delivery / Gig", "配送 / 网约接单")
        case .clientSite: return L10n.t("Client Site", "客户拜访")
        case .supplyRun: return L10n.t("Supply Run", "采购备货")
        case .propertyShowing: return L10n.t("Property Showing", "带看 / 勘查")
        case .errand: return L10n.t("Errand", "日常办事")
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
        case .low: return L10n.t("Highway (15+ mph)", "高速模式 (24+ km/h)")
        case .balanced: return L10n.t("Balanced (10+ mph)", "标准模式 (16+ km/h)")
        case .high: return L10n.t("City (6+ mph)", "市区灵敏 (10+ km/h)")
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
}

struct DriverSettings: Codable, Equatable {
    var driverName: String
    var taxYear: Int
    var distanceUnit: DistanceUnit
    var autoDriveEnabled: Bool
    var autoDriveSensitivity: AutoDriveSensitivity
    var useCustomRate: Bool
    var customRatePerUnit: Double
    var currencySymbol: String

    static func defaultSettings() -> DriverSettings {
        DriverSettings(
            driverName: L10n.t("Alex Rivera", "陈明远"),
            taxYear: 2026,
            distanceUnit: .miles,
            autoDriveEnabled: true,
            autoDriveSensitivity: .balanced,
            useCustomRate: false,
            customRatePerUnit: 0.76,
            currencySymbol: "$"
        )
    }
}

struct MileageBackupSnapshot: Codable {
    var schemaVersion: Int = 1
    var exportedAt: Date = Date()
    var settings: DriverSettings
    var vehicles: [Vehicle]
    var drives: [DriveRecord]
}
