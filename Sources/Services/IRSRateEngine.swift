import Foundation

enum IRS2026Period: String, Codable {
    case h1_2026 // Jan 1 – Jun 30, 2026 ($0.725/mi)
    case h2_2026 // Jul 1 – Dec 31, 2026 ($0.760/mi)
    case otherYear

    var shortBadge: String {
        switch self {
        case .h1_2026: return L10n.t("2026 H1 • 72.5¢/mi", "2026 上半年 • $0.725/mi")
        case .h2_2026: return L10n.t("2026 H2 • 76¢/mi", "2026 下半年 • $0.76/mi")
        case .otherYear: return L10n.t("Standard IRS", "IRS 标准费率")
        }
    }

    var csvLabel: String {
        switch self {
        case .h1_2026: return "2026-H1 (Jan-Jun)"
        case .h2_2026: return "2026-H2 (Jul-Dec)"
        case .otherYear: return "Standard"
        }
    }
}

enum IRSRateEngine {
    // Official IRS 2026 Split-Period Standard Mileage Rates (IRS Announcement 2026-11)
    static let business2026H1: Double = 0.725   // Jan 1 – Jun 30, 2026
    static let business2026H2: Double = 0.760   // Jul 1 – Dec 31, 2026
    static let business2025: Double = 0.700
    static let medicalMovingRate: Double = 0.210
    static let charityRate: Double = 0.140

    private static var utcGregorian: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return cal
    }()

    static func period(for date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> IRS2026Period {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return .h2_2026 }
        if year == 2026 {
            return month <= 6 ? .h1_2026 : .h2_2026
        }
        return .otherYear
    }

    /// Official IRS rate per mile for a given date & classification (ignoring custom override)
    static func irsRatePerMile(for classification: DriveClassification, on date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Double {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let year = comps.year ?? 2026
        let month = comps.month ?? 7

        switch classification {
        case .business, .unclassified:
            if year == 2026 {
                return month <= 6 ? business2026H1 : business2026H2
            } else if year <= 2025 {
                return business2025
            } else {
                return business2026H2
            }
        case .medical:
            return medicalMovingRate
        case .charity:
            return charityRate
        case .personal:
            return 0.0
        }
    }

    /// Calculates tax deduction in USD (or custom currency) for a drive.
    /// For unclassified drives, `includePotentialForUnclassified` returns what the drive WOULD be worth if swiped Business.
    static func deduction(
        for drive: DriveRecord,
        settings: DriverSettings,
        includePotentialForUnclassified: Bool = false
    ) -> Double {
        if drive.classification == .personal { return 0.0 }
        if drive.classification == .unclassified && !includePotentialForUnclassified { return 0.0 }

        let miles = max(0, drive.distanceMiles)
        if settings.useCustomRate && (drive.classification == .business || drive.classification == .unclassified) {
            let units = settings.distanceUnit.fromMiles(miles)
            return roundCents(units * max(0, settings.customRatePerUnit))
        }
        let rate = irsRatePerMile(for: drive.classification, on: drive.startDate)
        return roundCents(miles * rate)
    }

    static func effectiveRateLabel(for drive: DriveRecord, settings: DriverSettings) -> String {
        if drive.classification == .personal {
            return "\(settings.currencySymbol)0.00"
        }
        if settings.useCustomRate && (drive.classification == .business || drive.classification == .unclassified) {
            return String(format: "%@%.3f/%@", settings.currencySymbol, settings.customRatePerUnit, settings.distanceUnit.shortLabel)
        }
        let rate = irsRatePerMile(for: drive.classification, on: drive.startDate)
        if abs(rate - 0.725) < 0.0001 {
            return "$0.725/mi"
        }
        return String(format: "$%.2f/mi", rate)
    }

    static func roundCents(_ value: Double) -> Double {
        (value * 100.0).rounded() / 100.0
    }

    static func formatMoney(_ amount: Double, symbol: String = "$") -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 2
        nf.maximumFractionDigits = 2
        let formatted = nf.string(from: NSNumber(value: abs(amount))) ?? String(format: "%.2f", abs(amount))
        return amount < 0 ? "-\(symbol)\(formatted)" : "\(symbol)\(formatted)"
    }

    static func formatDistance(_ miles: Double, unit: DistanceUnit) -> String {
        let val = unit.fromMiles(miles)
        return String(format: "%.1f %@", val, unit.shortLabel)
    }

    static func formatOdometer(_ miles: Double, unit: DistanceUnit) -> String {
        let val = unit.fromMiles(miles)
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 0
        let str = nf.string(from: NSNumber(value: val.rounded())) ?? "\(Int(val.rounded()))"
        return "\(str) \(unit.shortLabel)"
    }
}
